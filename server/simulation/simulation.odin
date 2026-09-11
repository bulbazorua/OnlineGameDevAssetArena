package simulation

import "../content"

// The authoritative runtime: the public session everyone may see beside the private
// battle runtime only the host holds. Each brain gets its own repeatable random stream.
Simulation :: struct {
    session: Session,
    battle: Battle_Runtime,
    seed: u32,
    observe_only: bool,
}

// What the session step found out for the battle phases that follow it.
Tick_Start :: struct {
    session_changed: bool, // A public countdown second passed.
    in_arena: bool,
    can_act: bool, // Summoning had already finished before this step began.
}

// Advance the public session one fixed step and bind the private runtime to it.
begin_tick :: proc(sim: ^Simulation, catalog: ^content.Game_Content) -> (start: Tick_Start) {
    start.can_act = sim.session.phase == .In_Arena && sim.session.summon_elapsed_ticks == SUMMON_DURATION_TICKS
    start.session_changed = session_tick(&sim.session, catalog)
    battle_sync(&sim.battle, &sim.session, catalog, sim.seed, .Observe if sim.observe_only else .Search)
    start.in_arena = sim.session.phase == .In_Arena
    return
}

// One complete fixed step on the calling thread: the serial reference that the
// host's threaded step must match. Nothing here records diagnostics.
advance :: proc(sim: ^Simulation, catalog: ^content.Game_Content) -> (session_changed: bool) {
    start := begin_tick(sim, catalog)
    if start.in_arena {
        requests := battle_prepare_decisions(&sim.battle, &sim.session, catalog, start.can_act, trace = false)
        responses := decide_serially(requests)
        battle_resolve_decisions(&sim.battle, &sim.session, catalog, start.can_act, responses)
    }
    return start.session_changed
}
