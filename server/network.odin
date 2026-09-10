package main

import "core:fmt"
import "core:strings"
import "core:time"
import enet "vendor:ENet"

MAX_CONNECTIONS :: enet.PROTOCOL_MAXIMUM_PEER_ID
HELLO_TIMEOUT :: 5 * time.Second

Client :: struct {
    peer: ^enet.Peer,
    connected_at: time.Tick,
    welcomed: bool,
    player_id: u8,
    audience_seeded: bool,
    audience_revision: u32,
}

Network_Host :: struct {
    host: ^enet.Host,
    clients: []Client,
    session: ^Session,
    content: ^Game_Content,
    session_dirty: bool,
    audience: Audience_Stream,
    started_at: time.Tick,
}

network_open :: proc(bind: string, port: u16, session: ^Session, content: ^Game_Content, audience_delay_ms: u32 = DEFAULT_AUDIENCE_DELAY_MS) -> (Network_Host, bool) {
    if port == 0 {
        fmt.eprintln("[host] Port must be between 1 and 65535.")
        return {}, false
    }
    if enet.initialize() != 0 {
        fmt.eprintln("[host] Could not initialize ENet.")
        return {}, false
    }
    address := enet.Address{port = port}
    bind_ip := strings.clone_to_cstring(bind)
    defer delete(bind_ip)
    if enet.address_set_host_ip(&address, bind_ip) != 0 {
        fmt.eprintln("[host] Bind address must be an IPv4 address.")
        enet.deinitialize()
        return {}, false
    }
    host := enet.host_create(&address, MAX_CONNECTIONS, 2, 0, 0)
    if host == nil {
        fmt.eprintfln("[host] Could not listen on %s:%d. The port may already be in use.", bind, port)
        enet.deinitialize()
        return {}, false
    }
    host.maximumPacketSize = 160
    host.maximumWaitingData = 4096
    fmt.printfln("[host] Listening on %s:%d (2 fighters, up to %d total connections)", bind, port, MAX_CONNECTIONS)
    fmt.printfln("[host] Audience delay: %.3f seconds.", f64(audience_delay_ms) / 1000)
    return Network_Host{host = host, clients = make([]Client, MAX_CONNECTIONS), session = session, content = content,
        audience = audience_init(audience_delay_ms), started_at = time.tick_now()}, true
}

network_close :: proc(network: ^Network_Host) {
    enet.host_destroy(network.host)
    delete(network.clients)
    audience_destroy(&network.audience)
    enet.deinitialize()
    network^ = {}
}

network_poll :: proc(network: ^Network_Host) -> bool {
    event: enet.Event
    result := enet.host_service(network.host, &event, 1)
    if result < 0 {
        fmt.eprintln("[host] Network service failed.")
        return false
    }
    if result > 0 {
        slot := int(event.peer.incomingPeerID)
        client := &network.clients[slot]
        switch event.type {
        case .CONNECT:
            client^ = Client{peer = event.peer, connected_at = time.tick_now()}
            enet.peer_timeout(event.peer, 32, 1500, 5000)
            fmt.printfln("[host] Transport connected in slot %d; waiting for Hello.", slot + 1)
        case .RECEIVE:
            network_receive(network, client, &event)
        case .DISCONNECT:
            fmt.printfln("[host] Slot %d disconnected.", slot + 1)
            network_forget_client(network, client)
        case .NONE:
        }
    }
    for &client, slot in network.clients {
        if client.peer != nil && !client.welcomed && time.tick_since(client.connected_at) >= HELLO_TIMEOUT {
            fmt.printfln("[host] Slot %d timed out waiting for Hello.", slot + 1)
            network_drop(network, &client, u32(Reject_Reason.Protocol))
        }
    }
    if network.session_dirty {
        network_publish_session(network)
    }
    return true
}

network_receive :: proc(network: ^Network_Host, client: ^Client, event: ^enet.Event) {
    defer enet.packet_destroy(event.packet)
    command, valid := protocol_decode(event.packet.data[:event.packet.dataLength], event.channelID)
    if !valid || client.peer != event.peer {
        fmt.eprintln("[host] Rejected invalid message.")
        network_drop(network, client, u32(Reject_Reason.Protocol))
        return
    }

    if command.kind == .Hello {
        if command.fingerprint != network.content.fingerprint {
            network_drop(network, client, u32(Reject_Reason.Content_Mismatch))
            return
        }
        joining := !client.welcomed
        if joining {
            client.player_id = session_join(network.session, command.wants_audience)
            // Mark membership first so a send failure rolls it back once.
            client.welcomed = true
            network.session_dirty = true
            fmt.printfln("[host] Joined as role %d (0 = audience).", client.player_id)
        }
        delay_ms: u32
        if client.player_id == 0 { delay_ms = network.audience.delay_ms }
        welcome := protocol_encode_welcome(client.player_id, delay_ms)
        if !network_send(network, client, welcome[:]) { return }
        if !joining || client.player_id == 0 { network_send_client_session(network, client) }
    } else {
        if !client.welcomed {
            network_drop(network, client, u32(Reject_Reason.Protocol))
            return
        }
        changed, rejection := session_apply(network.session, network.content, client.player_id, command)
        if rejection != .None {
            round_id := network.session.round_id
            if client.player_id == 0 && network.audience.delay_ms > 0 {
                round_id = 0
                if network.audience.has_latest { round_id = network.audience.latest.round_id }
            }
            reply := protocol_encode_rejection(round_id, command.kind, rejection)
            network_send(network, client, reply[:])
        } else if changed {
            network.session_dirty = true
        } else if command.kind != .Input {
            network_send_client_session(network, client)
        }
    }
    enet.host_flush(network.host)
}

network_publish_session :: proc(network: ^Network_Host) {
    network.session_dirty = false
    roster := protocol_encode_session(network.session)
    roster_size := protocol_session_size(network.session)
    for &client in network.clients {
        if client.welcomed && (client.player_id > 0 || network.audience.delay_ms == 0) {
            network_send(network, &client, roster[:roster_size])
        }
    }
    // A failed send removes its member and sets dirty for the next poll.
    enet.host_flush(network.host)
}

network_send :: proc(network: ^Network_Host, client: ^Client, payload: []u8, channel: u8 = 0) -> bool {
    flags: enet.PacketFlags
    if channel == 0 { flags = {.RELIABLE} }
    packet := enet.packet_create(raw_data(payload), len(payload), flags)
    if packet == nil {
        fmt.eprintln("[host] Could not allocate a message.")
        network_drop(network, client, 0)
        return false
    }
    if enet.peer_send(client.peer, channel, packet) != 0 {
        enet.packet_destroy(packet) // ENet owns the packet only after a successful send.
        network_drop(network, client, 0)
        return false
    }
    return true
}

network_drop :: proc(network: ^Network_Host, client: ^Client, reason: u32) {
    enet.peer_disconnect_now(client.peer, reason)
    network_forget_client(network, client)
}

network_forget_client :: proc(network: ^Network_Host, client: ^Client) {
    if client.welcomed {
        session_leave(network.session, client.player_id)
        network.session_dirty = true
    }
    client^ = {}
}

network_publish_world :: proc(network: ^Network_Host) {
    if network.session.phase != .In_Arena { return }
    state := protocol_encode_world(network.session)
    for &client in network.clients {
        if client.welcomed && (client.player_id > 0 || network.audience.delay_ms == 0) { network_send(network, &client, state[:], 1) }
    }
    enet.host_flush(network.host)
}

// All direct state replies use the connection's permitted timeline. Repeating
// Hello or reconnecting must never fall back to the live fighter state.
network_send_client_session :: proc(network: ^Network_Host, client: ^Client) {
    state := network.session
    if client.player_id == 0 && network.audience.delay_ms > 0 {
        if !network.audience.has_latest { return }
        state = &network.audience.latest
    }
    bytes := protocol_encode_session(state)
    if network_send(network, client, bytes[:protocol_session_size(state)]) {
        client.audience_seeded = true
        client.audience_revision = state.revision
    }
}

network_publish_audience :: proc(network: ^Network_Host) {
    if !audience_advance(&network.audience, network.session, time.tick_since(network.started_at)) { return }
    state := &network.audience.latest
    roster := protocol_encode_session(state)
    world: [121]u8
    if state.phase == .In_Arena { world = protocol_encode_world(state) }
    for &client in network.clients {
        if !client.welcomed || client.player_id != 0 { continue }
        if !client.audience_seeded || client.audience_revision != state.revision {
            if network_send(network, &client, roster[:protocol_session_size(state)]) {
                client.audience_seeded = true
                client.audience_revision = state.revision
            }
        } else if state.phase == .In_Arena {
            network_send(network, &client, world[:], 1)
        }
    }
    enet.host_flush(network.host)
}
