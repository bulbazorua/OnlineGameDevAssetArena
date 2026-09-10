package main

import "core:fmt"

Dev_Scenario :: struct {
    enabled, applied: bool,
    character_ids: [2]u16,
    map_id: u16,
    countdown_seconds: u8,
}

dev_scenario_load :: proc(options: Options, content: ^Game_Content) -> (scenario: Dev_Scenario, valid: bool) {
    requested := options.dev_p1 != "" || options.dev_p2 != "" || options.dev_arena != "" || options.dev_countdown != 0 || options.dev_validate_only
    if !options.dev && !requested { return {}, true }
    when !ODIN_DEBUG {
        fmt.eprintln("[dev] Development scenarios require a debug host build.")
        return {}, false
    }
    if !options.dev || options.bind != "127.0.0.1" {
        fmt.eprintln("[dev] Scenarios require --dev and --bind=127.0.0.1.")
        return {}, false
    }
    if !requested { return {}, true }
    if options.dev_countdown != 0 && options.dev_countdown != 5 {
        fmt.eprintln("[dev] Countdown must be 0 or 5.")
        return {}, false
    }
    for key, index in ([2]string{options.dev_p1, options.dev_p2}) {
        for definition in content.characters {
            if definition.key == key { scenario.character_ids[index] = definition.id; break }
        }
        if scenario.character_ids[index] == 0 {
            fmt.eprintfln("[dev] Unknown P%d character '%s'. Available:", index + 1, key)
            for definition in content.characters { fmt.eprintfln("  %s", definition.key) }
            return {}, false
        }
    }
    for arena in content.arenas { if arena.key == options.dev_arena { scenario.map_id = arena.id; break } }
    if scenario.map_id == 0 {
        fmt.eprintfln("[dev] Unknown arena '%s'. Available:", options.dev_arena)
        for arena in content.arenas { fmt.eprintfln("  %s", arena.key) }
        return {}, false
    }
    scenario.enabled = true
    scenario.countdown_seconds = options.dev_countdown
    return scenario, true
}

dev_scenario_start :: proc(scenario: ^Dev_Scenario, session: ^Session, content: ^Game_Content) -> bool {
    if !scenario.enabled || scenario.applied || session_player_mask(session) != 3 || session.phase != .Lobby { return false }
    scenario.applied = true
    session.round_id += 1
    session.revision += 1
    session.map_id = scenario.map_id
    for &player, index in session.players {
        player.character_id = scenario.character_ids[index]
        player.ready = true
    }
    if scenario.countdown_seconds == 0 {
        session_enter_arena(session, content)
    } else {
        session.phase = .Countdown
        session.countdown_ticks = u16(scenario.countdown_seconds) * SIMULATION_HZ
    }
    fmt.printfln("[dev] Scenario started: P1=%d P2=%d arena=%d countdown=%d", scenario.character_ids[0], scenario.character_ids[1], scenario.map_id, scenario.countdown_seconds)
    return true
}
