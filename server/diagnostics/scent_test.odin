package diagnostics

import "../content"
import "../simulation"
import obs "../observations"
import "../perception"
import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:sync"
import "core:testing"

@(test)
scent_field_capture_matches_the_field_and_its_publication_stays_bounded :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := simulation.battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    debug := new(Diagnostics)
    defer free(debug)
    directory := fmt.aprintf("build/scent-debug-test-%d", sync.current_thread_id())
    defer delete(directory)
    testing.expect(t, os.make_directory(directory) == nil)
    debug.directory, debug.run_id, debug.fingerprint = directory, "scent-capture", "00"
    sim := simulation.battle_test_scenario(&catalog, map_id, 5)
    // The serial reference step followed by the capture: what the host step does after each tick.
    for _ in 0..<300 { simulation.advance(&sim, &catalog); capture_scent(debug, &sim.battle, &sim.session) }
    capture := &debug.scent_capture
    field := &sim.battle.scent.field
    // The capture follows field steps (10 Hz); compare right after a tick that stepped.
    for capture.tick != sim.session.server_tick { simulation.advance(&sim, &catalog); capture_scent(debug, &sim.battle, &sim.session) }
    testing.expect(t, capture.valid && capture.round_id == sim.session.round_id && capture.width == field.width && capture.height == field.height)
    for class in obs.Scent_Class {
        for index in 0..<field.width * field.height {
            expected := u8(clamp(field.levels[class][index] * 255 + 0.5, 0, 255))
            testing.expect(t, capture.levels[class][index] == expected, "captured level differs from the live field")
        }
    }
    publish_scent(debug)
    path := fmt.aprintf("%s/scent.json", directory)
    defer delete(path)
    data, error := os.read_entire_file(path, context.allocator)
    defer delete(data)
    testing.expect(t, error == nil && len(data) <= SCENT_BYTES)
    temporary: mem.Dynamic_Arena
    mem.dynamic_arena_init(&temporary)
    defer mem.dynamic_arena_destroy(&temporary)
    snapshot: Scent_Snapshot
    testing.expect(t, json.unmarshal(data, &snapshot, allocator = mem.dynamic_arena_allocator(&temporary)) == nil)
    testing.expect(t, snapshot.schema_version == SCENT_SCHEMA && snapshot.field.valid && len(snapshot.field.levels) == 2 && snapshot.field.classes[0] == "Human")
    decoded, decode_error := base64.decode(snapshot.field.levels[0], allocator = mem.dynamic_arena_allocator(&temporary))
    testing.expect(t, decode_error == nil && len(decoded) == field.width * field.height)
    for index in 0..<len(decoded) { testing.expect(t, decoded[index] == capture.levels[.Human][index]) }
    // The widest accepted field still fits the declared ceiling.
    capture.width, capture.height = perception.MAX_GRID_SIDE, perception.MAX_GRID_SIDE
    for class in obs.Scent_Class { for index in 0..<perception.MAX_GRID_CELLS { capture.levels[class][index], capture.ages[class][index] = 255, 255 } }
    publish_scent(debug)
    widest, widest_error := os.read_entire_file(path, context.allocator)
    defer delete(widest)
    testing.expect(t, widest_error == nil && len(widest) <= SCENT_BYTES && len(widest) > 80 * 1024)
    // Leaving the arena invalidates the capture instead of showing an old field.
    simulation.session_reset(&sim.session)
    simulation.advance(&sim, &catalog)
    capture_scent(debug, &sim.battle, &sim.session)
    testing.expect(t, !debug.scent_capture.valid)
}
