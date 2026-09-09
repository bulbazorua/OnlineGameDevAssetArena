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
}

Network_Host :: struct {
    host: ^enet.Host,
    clients: []Client,
    session: ^Session,
    content: ^Game_Content,
    session_dirty: bool,
}

network_open :: proc(bind: string, port: u16, session: ^Session, content: ^Game_Content) -> (Network_Host, bool) {
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
    host.maximumPacketSize = 128
    host.maximumWaitingData = 4096
    fmt.printfln("[host] Listening on %s:%d (2 fighters, up to %d total connections)", bind, port, MAX_CONNECTIONS)
    return Network_Host{host = host, clients = make([]Client, MAX_CONNECTIONS), session = session, content = content}, true
}

network_close :: proc(network: ^Network_Host) {
    enet.host_destroy(network.host)
    delete(network.clients)
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
        welcome := protocol_encode_welcome(client.player_id)
        if !network_send(network, client, welcome[:]) { return }
        if !joining {
            state := protocol_encode_session(network.session)
            network_send(network, client, state[:protocol_session_size(network.session)])
        }
    } else {
        if !client.welcomed {
            network_drop(network, client, u32(Reject_Reason.Protocol))
            return
        }
        changed, rejection := session_apply(network.session, network.content, client.player_id, command)
        if rejection != .None {
            reply := protocol_encode_rejection(network.session.round_id, command.kind, rejection)
            network_send(network, client, reply[:])
        } else if changed {
            network.session_dirty = true
        } else if command.kind != .Input {
            state := protocol_encode_session(network.session)
            network_send(network, client, state[:protocol_session_size(network.session)])
        }
    }
    enet.host_flush(network.host)
}

network_publish_session :: proc(network: ^Network_Host) {
    network.session_dirty = false
    roster := protocol_encode_session(network.session)
    roster_size := protocol_session_size(network.session)
    for &client in network.clients {
        if client.welcomed {
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
        if client.welcomed { network_send(network, &client, state[:], 1) }
    }
    enet.host_flush(network.host)
}
