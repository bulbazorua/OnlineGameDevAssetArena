package main

import "content"
import "simulation"

// One authoritative step with the host's dedicated brain threads and diagnostics
// attached. simulation.advance is the serial reference; both run the same phases in order.
host_simulation_step :: proc(sim: ^simulation.Simulation, catalog: ^content.Game_Content, workers: ^Brain_Workers = nil, debug: ^AI_Debug = nil) -> (session_changed: bool) {
    start := simulation.begin_tick(sim, catalog)
    if start.in_arena {
        requests := simulation.battle_prepare_decisions(&sim.battle, &sim.session, catalog, start.can_act, trace = debug != nil)
        responses: [simulation.MAX_PLAYERS]simulation.Brain_Response
        if workers != nil {
            responses = brain_workers_decide(workers, requests)
        } else {
            responses = simulation.decide_serially(requests)
        }
        outcomes := simulation.battle_resolve_decisions(&sim.battle, &sim.session, catalog, start.can_act, responses)
        ai_debug_record_decisions(debug, sim, requests, &responses, outcomes)
    }
    ai_debug_capture_world(debug, &sim.session)
    ai_debug_capture_scent(debug, &sim.battle, &sim.session)
    return start.session_changed
}
