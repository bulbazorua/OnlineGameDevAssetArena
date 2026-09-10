package main

// Only the session is visible to transport/history. Brains stay private and owned.
Simulation :: struct {
    session: Session,
    battle: Battle_Runtime,
    seed: u32,
}

simulation_tick :: proc(sim: ^Simulation, content: ^Game_Content, workers: ^Brain_Workers = nil, debug: ^AI_Debug = nil) -> bool {
    was_unlocked := sim.session.phase == .In_Arena && sim.session.summon_elapsed_ticks == SUMMON_DURATION_TICKS
    changed := session_tick(&sim.session, content)
    battle_sync(&sim.battle, &sim.session, sim.seed)
    if sim.session.phase == .In_Arena {
        battle_tick(&sim.battle, &sim.session, content, was_unlocked, workers, debug)
    }
    ai_debug_capture_world(debug, &sim.session)
    return changed
}
