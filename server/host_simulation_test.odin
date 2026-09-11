package main

import "simulation"
import "content"
import ai "ai"
import obs "observations"
import "perception"
import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"

@(test)
audience_attachment_and_diagnostics_cannot_change_decisions :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    testing.expect(t, content.load(&catalog, "client/content/data"))
    defer content.destroy(&catalog)
    a := simulation.battle_test_scenario(&catalog, 4, 5)
    b := a
    simulation.session_join(&b.session, true)
    // No writer: a full diagnostics queue also exercises non-blocking record loss.
    debug := new(AI_Debug)
    defer free(debug)
    debug.origin = time.tick_now()
    stream := audience_init(5000)
    defer audience_destroy(&stream)
    audience_advance(&stream, &a.session, 0)
    historical := a.session.characters
    for tick in u32(1)..<1800 {
        simulation.advance(&a, &catalog)
        host_simulation_step(&b, &catalog, nil, debug)
        testing.expect(t, a.session.characters == b.session.characters && a.battle == b.battle)
    }
    testing.expect(t, debug.count == AI_DEBUG_QUEUE && debug.dropped > 0)
    testing.expect(t, audience_advance(&stream, &a.session, 5000 * time.Millisecond))
    testing.expect(t, stream.latest.characters == historical && stream.latest.summon_elapsed_ticks == 0)
    testing.expect(t, a.session.characters != historical, "creatures never turned")
}

@(test)
replacing_one_creature_keeps_the_other_mind_and_the_ground_and_workers_agree :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := simulation.battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    a := simulation.battle_test_scenario(&catalog, map_id, 5, 77)
    a.observe_only = false
    b := a
    workers := new(Brain_Workers)
    defer free(workers)
    brain_workers_init(workers)
    defer brain_workers_destroy(workers)
    for _ in 0..<900 {
        simulation.advance(&a, &catalog)
        host_simulation_step(&b, &catalog, workers)
        testing.expect(t, a.battle == b.battle && a.session == b.session, "dedicated workers changed the field, the samples or the search")
    }
    testing.expect(t, a.battle.scent.field.bounds.active && a.battle.agents[0].scent.ingested_samples > 60)
    kept := a.battle.agents[1]
    kept_receptor := a.battle.receptors[1]
    ground := a.battle.scent.field
    a.session.characters[0].entity_id += 1000
    simulation.battle_sync(&a.battle, &a.session, &catalog, a.seed, .Search)
    testing.expect(t, a.battle.agents[1] == kept && a.battle.receptors[1] == kept_receptor, "replacement touched the other creature's mind or nose")
    testing.expect(t, a.battle.agents[0].scent == ai.Scent_Memory{} && a.battle.receptors[0].olfaction == simulation.Olfaction_Receptor{profile = kept_receptor.olfaction.profile})
    testing.expect(t, a.battle.scent.field == ground, "old deposits stay on the ground for the replacement to smell")
    testing.expect(t, a.battle.scent.emitters[0].entity_id == a.session.characters[0].entity_id && a.battle.scent.emitters[0].armed)
    total := perception.scent_field_total(&a.battle.scent.field, .Human)
    simulation.advance(&a, &catalog)
    testing.expect(t, perception.scent_field_total(&a.battle.scent.field, .Human) <= total + 4 * perception.SCENT_EMISSION_PER_TICK + 0.001, "a re-armed emitter paints no jump trail")
}

@(test)
scent_field_capture_matches_the_field_and_its_publication_stays_bounded :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := simulation.battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    debug := new(AI_Debug)
    defer free(debug)
    directory := fmt.aprintf("build/scent-debug-test-%d", sync.current_thread_id())
    defer delete(directory)
    testing.expect(t, os.make_directory(directory) == nil)
    debug.directory, debug.run_id, debug.fingerprint = directory, "scent-capture", "00"
    sim := simulation.battle_test_scenario(&catalog, map_id, 5)
    for _ in 0..<300 { host_simulation_step(&sim, &catalog, nil, debug) }
    capture := &debug.scent_capture
    field := &sim.battle.scent.field
    // The capture follows field steps (10 Hz); compare right after a tick that stepped.
    for capture.tick != sim.session.server_tick { host_simulation_step(&sim, &catalog, nil, debug) }
    testing.expect(t, capture.valid && capture.round_id == sim.session.round_id && capture.width == field.width && capture.height == field.height)
    for class in obs.Scent_Class {
        for index in 0..<field.width * field.height {
            expected := u8(clamp(field.levels[class][index] * 255 + 0.5, 0, 255))
            testing.expect(t, capture.levels[class][index] == expected, "captured level differs from the live field")
        }
    }
    ai_debug_publish_scent(debug)
    path := fmt.aprintf("%s/scent.json", directory)
    defer delete(path)
    data, error := os.read_entire_file(path, context.allocator)
    defer delete(data)
    testing.expect(t, error == nil && len(data) <= SCENT_DEBUG_BYTES)
    temporary: mem.Dynamic_Arena
    mem.dynamic_arena_init(&temporary)
    defer mem.dynamic_arena_destroy(&temporary)
    snapshot: Scent_Debug_Snapshot
    testing.expect(t, json.unmarshal(data, &snapshot, allocator = mem.dynamic_arena_allocator(&temporary)) == nil)
    testing.expect(t, snapshot.schema_version == SCENT_DEBUG_SCHEMA && snapshot.field.valid && len(snapshot.field.levels) == 2 && snapshot.field.classes[0] == "Human")
    decoded, decode_error := base64.decode(snapshot.field.levels[0], allocator = mem.dynamic_arena_allocator(&temporary))
    testing.expect(t, decode_error == nil && len(decoded) == field.width * field.height)
    for index in 0..<len(decoded) { testing.expect(t, decoded[index] == capture.levels[.Human][index]) }
    // The widest accepted field still fits the declared ceiling.
    capture.width, capture.height = perception.MAX_GRID_SIDE, perception.MAX_GRID_SIDE
    for class in obs.Scent_Class { for index in 0..<perception.MAX_GRID_CELLS { capture.levels[class][index], capture.ages[class][index] = 255, 255 } }
    ai_debug_publish_scent(debug)
    widest, widest_error := os.read_entire_file(path, context.allocator)
    defer delete(widest)
    testing.expect(t, widest_error == nil && len(widest) <= SCENT_DEBUG_BYTES && len(widest) > 80 * 1024)
    // Leaving the arena invalidates the capture instead of showing an old field.
    simulation.session_reset(&sim.session)
    host_simulation_step(&sim, &catalog, nil, debug)
    testing.expect(t, !debug.scent_capture.valid)
}

@(test)
delivered_coverage_reaches_diagnostics_without_a_map :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := simulation.battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    arena := content.find_arena(&catalog, map_id)
    // The archer stands in the north-west corner pocket; the orc in the open middle.
    sim := simulation.scent_test_scenario(&catalog, map_id, {5, 6})
    sim.session.characters[0].position = content.arena_cell_center(arena, {2, 1})
    sim.session.characters[1].position = content.arena_cell_center(arena, {16, 6})
    for _ in 0..<91 { simulation.advance(&sim, &catalog) }
    when ODIN_DEBUG {
        // The same coverage reaches the journal, the snapshot and the live senses file; the audit stays outside the brain input.
        directory := fmt.aprintf("build/scent-coverage-test-%d", sync.current_thread_id())
        defer delete(directory)
        testing.expect(t, os.make_directory(directory) == nil)
        debug := ai_debug_open(directory, "coverage-run", catalog.fingerprint, &catalog, seed = 42)
        for _ in 0..<30 { host_simulation_step(&sim, &catalog, nil, debug) }
        latest := sim.battle.receptors[0].olfaction.last
        ai_debug_close(debug)
        temporary: mem.Dynamic_Arena
        mem.dynamic_arena_init(&temporary)
        defer mem.dynamic_arena_destroy(&temporary)
        snapshot_path := fmt.aprintf("%s/ai-1.json", directory)
        defer delete(snapshot_path)
        data, error := os.read_entire_file(snapshot_path, context.allocator)
        defer delete(data)
        snapshot: AI_Debug_Snapshot
        testing.expect(t, error == nil && json.unmarshal(data, &snapshot, allocator = mem.dynamic_arena_allocator(&temporary)) == nil && len(snapshot.records) > 0)
        record := snapshot.records[len(snapshot.records) - 1]
        testing.expect(t, snapshot.schema_version == AI_DEBUG_SCHEMA && record.input.senses.olfaction.coverage == latest.coverage && record.host_scent_audit.cells_excluded > 0)
        text := string(data)
        brain_side := text[:strings.index(text, "\"host_audit\"")]
        testing.expect(t, strings.contains(brain_side, "\"coverage\"") && !strings.contains(brain_side, "cells_excluded") && !strings.contains(brain_side, "newest_detectable"), "the audit must stay outside the brain input")
        senses_path := fmt.aprintf("%s/senses.json", directory)
        defer delete(senses_path)
        live, live_error := os.read_entire_file(senses_path, context.allocator)
        defer delete(live)
        senses: Sense_Debug_Snapshot
        testing.expect(t, live_error == nil && json.unmarshal(live, &senses, allocator = mem.dynamic_arena_allocator(&temporary)) == nil)
        testing.expect(t, senses.schema_version == SENSE_DEBUG_SCHEMA && len(senses.records) == 2 && senses.records[0].olfaction.coverage == latest.coverage)
    }
}

@(test)
search_workers_match_serial_with_trace_loss_and_private_entity_lifecycle :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := simulation.battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    a := simulation.battle_test_scenario(&catalog, map_id, 5, 72)
    a.observe_only = false
    b := a
    workers := new(Brain_Workers)
    defer free(workers)
    brain_workers_init(workers)
    defer brain_workers_destroy(workers)
    debug := new(AI_Debug)
    defer free(debug)
    debug.origin = time.tick_now()
    for tick in 0..<2400 {
        simulation.advance(&a, &catalog)
        host_simulation_step(&b, &catalog, workers, debug)
        testing.expect(t, a.battle == b.battle && a.session == b.session, "thread order or diagnostics changed search")
        if tick == 1200 {
            kept := a.battle.agents[1]
            kept_character := a.session.characters[1]
            a.session.characters[0].target_alert = true
            a.session.characters[0].target_acquired_tick = a.session.server_tick
            b.session.characters[0].target_alert = true
            b.session.characters[0].target_acquired_tick = b.session.server_tick
            a.session.characters[0].entity_id += 10
            b.session.characters[0].entity_id += 10
            simulation.battle_sync(&a.battle, &a.session, &catalog, a.seed, .Search)
            simulation.battle_sync(&b.battle, &b.session, &catalog, b.seed, .Search)
            testing.expect(t, a.battle.agents[1] == kept && a.battle.agents[0].search.visit_count == 0 && a.battle.agents[0].search.acquisition_count == 0)
            testing.expect(t, !a.session.characters[0].target_alert && a.session.characters[0].target_acquired_tick == 0 && a.session.characters[1] == kept_character)
        }
    }
    testing.expect(t, debug.dropped > 0 && workers.slots[0].response.worker_id != workers.slots[1].response.worker_id)
    simulation.session_reset(&a.session)
    simulation.advance(&a, &catalog)
    testing.expect(t, a.battle == simulation.Battle_Runtime{})
}
