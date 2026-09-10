package main

import "core:flags"
import "core:fmt"
import "core:math"
import "core:os"
import "core:time"

Options :: struct {
    bind: string,
    port: u16,
    content_dir: string,
    audience_delay: f64, // Seconds, configured by the host only.
    dev: bool,
    dev_p1, dev_p2, dev_arena: string,
    dev_countdown: u8,
    dev_validate_only: bool,
}

main :: proc() {
    options := Options{bind = "127.0.0.1", port = 7000, content_dir = "client/content/data", audience_delay = 5}
    flags.parse_or_exit(&options, os.args, .Unix)
    os.exit(run_host(options))
}

run_host :: proc(options: Options) -> int {
    if !(options.audience_delay >= 0 && options.audience_delay <= 60) {
        fmt.eprintln("[host] --audience-delay must be a finite number from 0 to 60 seconds.")
        return 1
    }
    delay_ms := u32(math.ceil(options.audience_delay * 1000))
    content: Game_Content
    if !content_load(&content, options.content_dir) { return 1 }
    defer content_destroy(&content)
    scenario, scenario_ok := dev_scenario_load(options, &content)
    if !scenario_ok { return 1 }
    if options.dev_validate_only { return 0 }
    session: Session
    network, ok := network_open(options.bind, options.port, &session, &content, delay_ms)
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
        if dev_scenario_start(&scenario, &session, &content) { network.session_dirty = true }
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
        network_publish_audience(&network)
    }
}
