package main

// Only the session is visible to transport/history. Brains stay private and owned.
// Each brain gets its own repeatable random stream.
Simulation :: struct {
    session: Session,
    battle: Battle_Runtime,
    seed: u32,
    observe_only: bool,
}

simulation_tick :: proc(sim: ^Simulation, content: ^Game_Content, workers: ^Brain_Workers = nil, debug: ^AI_Debug = nil) -> bool {
    was_unlocked := sim.session.phase == .In_Arena && sim.session.summon_elapsed_ticks == SUMMON_DURATION_TICKS
    changed := session_tick(&sim.session, content)
    battle_sync(&sim.battle, &sim.session, content, sim.seed, .Observe if sim.observe_only else .Search)
    if sim.session.phase == .In_Arena {
        battle_tick(&sim.battle, &sim.session, content, was_unlocked, workers, debug)
    }
    ai_debug_capture_world(debug, &sim.session)
    ai_debug_capture_scent(debug, &sim.battle, &sim.session)
    return changed
}
