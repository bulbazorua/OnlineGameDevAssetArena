package main

import "core:flags"
import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import "core:c/libc"
import "core:sync"

host_stop_requested: i32

host_stop_signal :: proc "c" (_: libc.int) {
    sync.atomic_store(&host_stop_requested, 1)
}

Options :: struct {
    bind: string,
    port: u16,
    content_dir: string,
    audience_delay: f64, // Seconds, configured by the host only.
    seed: u32,
    dev: bool,
    dev_p1, dev_p2, dev_arena: string,
    dev_countdown: u8,
    dev_validate_only: bool,
    dev_ai_dir, dev_ai_run: string,
}

main :: proc() {
    libc.signal(libc.SIGINT, host_stop_signal)
    libc.signal(libc.SIGTERM, host_stop_signal)
    options := Options{bind = "127.0.0.1", port = 7000, content_dir = "client/content/data", audience_delay = 5, seed = 1}
    flags.parse_or_exit(&options, os.args, .Unix)
    os.exit(run_host(options))
}

run_host :: proc(options: Options) -> int {
    if !ai_debug_options_valid(options) { return 1 }
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
    simulation := Simulation{seed = options.seed}
    workers: Brain_Workers
    brain_workers_init(&workers)
    defer brain_workers_destroy(&workers)
    debug := ai_debug_open(options.dev_ai_dir, options.dev_ai_run, content.fingerprint, seed = options.seed)
    defer ai_debug_close(debug)
    session := &simulation.session
    network, ok := network_open(options.bind, options.port, session, &content, delay_ms)
    if !ok {
        return 1
    }
    defer network_close(&network)
    fmt.printfln("[AI] idle_wander; source=scenario_default; seed=%d; two dedicated brain threads; 60 Hz actions, 10 Hz scheduled decisions", options.seed)
    previous := time.tick_now()
    accumulator: time.Duration
    step :: time.Second / SIMULATION_HZ
    for sync.atomic_load(&host_stop_requested) == 0 {
        if !network_poll(&network) {
            return 1
        }
        if dev_scenario_start(&scenario, session, &content) { network.session_dirty = true }
        now := time.tick_now()
        accumulator += min(time.tick_diff(previous, now), 250 * time.Millisecond)
        previous = now
        world_due := false
        for accumulator >= step {
            accumulator -= step
            if simulation_tick(&simulation, &content, &workers, debug) { network.session_dirty = true }
            if session.server_tick % SNAPSHOT_INTERVAL == 0 { world_due = true }
        }
        if network.session_dirty { network_publish_session(&network) }
        if world_due { network_publish_world(&network) }
        network_publish_audience(&network)
    }
    return 0
}
