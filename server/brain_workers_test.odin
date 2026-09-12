package main

import "content"
import "diagnostics"
import "simulation"
import ai "ai"
import "core:sync"
import "core:testing"

@(test)
dedicated_brains_match_serial_simulation_and_use_distinct_threads :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    workers := new(Brain_Workers)
    defer free(workers)
    brain_workers_init(workers)
    defer brain_workers_destroy(workers)
    // No writer: a full diagnostics queue also exercises non-blocking trace loss.
    debug := diagnostics.test_open_without_writer()
    defer free(debug)
    for &arena in catalog.arenas {
        a := simulation.battle_test_scenario(&catalog, arena.id, 5, 71)
        b := a
        for tick in u32(1)..<700 {
            if tick % 3 == 0 {
                command := simulation.Client_Command{kind = .Input, round_id = a.session.round_id, input_sequence = tick, input_mask = 2}
                simulation.session_apply(&a.session, &catalog, 1, command)
                simulation.session_apply(&b.session, &catalog, 1, command)
            }
            simulation.advance(&a, &catalog)
            host_simulation_step(&b, &catalog, workers, debug)
            testing.expect(t, a.session == b.session && a.battle == b.battle)
        }
        id1, id2 := workers.slots[0].response.worker_id, workers.slots[1].response.worker_id
        testing.expect(t, id1 != id2 && id1 != sync.current_thread_id() && id2 != sync.current_thread_id())
        simulation.session_reset(&a.session)
        simulation.session_reset(&b.session)
        simulation.advance(&a, &catalog)
        host_simulation_step(&b, &catalog, workers, debug)
        testing.expect(t, a.battle == simulation.Battle_Runtime{} && b.battle == simulation.Battle_Runtime{})
    }
    testing.expect(t, diagnostics.test_queue_full(debug) && diagnostics.test_dropped(debug) > 0)
}

@(test)
second_brain_completes_without_collecting_first_brain :: proc(t: ^testing.T) {
    workers := new(Brain_Workers)
    defer free(workers)
    brain_workers_init(workers)
    defer brain_workers_destroy(workers)
    for i in 0..<2 {
        brain_worker_submit(&workers.slots[i], {agent = ai.agent_reset(u32(i + 1), 2),
            ctx = {entity_id = u32(i + 1), round_id = 2, tick = 30, can_act = true, turn_ready = true}, config = ai.observe_defaults(), trace = true})
    }
    second := brain_worker_collect(&workers.slots[1])
    testing.expect(t, workers.slots[0].busy && !workers.slots[1].busy && second.agent.entity_id == 2)
    first := brain_worker_collect(&workers.slots[0])
    testing.expect(t, first.worker_id != second.worker_id)
    testing.expect(t, first.trace.nodes[0].thread_id == first.worker_id && second.trace.nodes[0].thread_id == second.worker_id)
}
