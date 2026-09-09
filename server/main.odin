package main

import "core:flags"
import "core:os"
import "core:time"

Options :: struct {
    bind: string,
    port: u16,
    content_dir: string,
}

main :: proc() {
    options := Options{bind = "127.0.0.1", port = 7000, content_dir = "client/content/data"}
    flags.parse_or_exit(&options, os.args, .Unix)
    os.exit(run_host(options))
}

run_host :: proc(options: Options) -> int {
    content: Game_Content
    if !content_load(&content, options.content_dir) { return 1 }
    defer content_destroy(&content)
    session: Session
    network, ok := network_open(options.bind, options.port, &session, &content)
    if !ok {
        return 1
    }
    defer network_close(&network)
    previous := time.tick_now()
    accumulator: time.Duration
    step :: time.Second / SIMULATION_HZ
    for {
        if !network_poll(&network) {
            return 1
        }
        now := time.tick_now()
        accumulator += min(time.tick_diff(previous, now), 250 * time.Millisecond)
        previous = now
        world_due := false
        for accumulator >= step {
            accumulator -= step
            if session_tick(&session, &content) { network.session_dirty = true }
            if session.server_tick % SNAPSHOT_INTERVAL == 0 { world_due = true }
        }
        if network.session_dirty { network_publish_session(&network) }
        if world_due { network_publish_world(&network) }
    }
}
