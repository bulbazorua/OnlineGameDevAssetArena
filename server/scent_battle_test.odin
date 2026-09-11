package main

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

// QA arena, two picks, no creature movement (Observe) so trails come only from
// trainers that the test walks with real input commands.
@(private = "file")
scent_test_scenario :: proc(content: ^Game_Content, map_id: u16, picks: [2]u16, seed: u32 = 42) -> Simulation {
    sim := Simulation{seed = seed, observe_only = true}
    sim.session.map_id = map_id
    sim.session.round_id = 1
    for &player, index in sim.session.players { player = {present = true, ready = true, character_id = picks[index]} }
    session_enter_arena(&sim.session, content)
    return sim
}

@(private = "file")
walk_trainer :: proc(sim: ^Simulation, content: ^Game_Content, player: u8, mask: u8, ticks: int, sequence: ^u32) {
    for _ in 0..<ticks {
        sequence^ += 1
        session_apply(&sim.session, content, player, {kind = .Input, round_id = sim.session.round_id, input_sequence = sequence^, input_mask = mask})
        simulation_tick(sim, content)
    }
}

@(private = "file")
reading_of :: proc(sample: obs.Scent_Sample, class: obs.Scent_Class) -> (obs.Scent_Reading, bool) {
    readings := sample.readings
    for reading in readings[:sample.reading_count] { if reading.class == class { return reading, true } }
    return {}, false
}

@(private = "file")
silence_creature_emitters :: proc(content: ^Game_Content) {
    for &character in content.characters { character.emitter.enabled = false }
}

@(test)
trail_persists_after_the_trainer_leaves_then_fades_while_reset_paints_nothing :: proc(t: ^testing.T) {
    content: Game_Content
    map_id := battle_test_content_with_qa(t, &content)
    defer content_destroy(&content)
    silence_creature_emitters(&content)
    sim := scent_test_scenario(&content, map_id, {5, 5})
    arena := content_arena(&content, map_id)
    // Trainer 1 starts just east of its creature so its whole trail lies east of the nose.
    sim.session.trainers[0].position = arena_cell_center(arena, {8, 5})
    for _ in 0..<91 { simulation_tick(&sim, &content) }
    field := &sim.battle.scent.field
    testing.expect(t, perception.scent_field_valid(field) && field.width == arena.width && field.tile_size == 32)
    testing.expect(t, sim.battle.receptors[0].olfaction.last.status == .Sampled && sim.battle.receptors[0].olfaction.schedule.sample_counter == 1)
    // Summoning painted nothing; the very first live tick deposits under the standing trainers.
    testing.expect(t, field.bounds.active && perception.scent_field_level(field, .Human, arena_world_to_cell(arena, sim.session.trainers[0].position)) > 0)
    testing.expect(t, perception.scent_field_level(field, .Human, arena_world_to_cell(arena, sim.session.characters[0].position)) == 0, "a silenced creature emits nothing")
    // Trainer 1 walks east along row 5 for three seconds, right past its creature.
    sequence: u32
    start := sim.session.trainers[0].position
    walk_trainer(&sim, &content, 1, 2, 180, &sequence)
    trainer := sim.session.trainers[0].position
    testing.expect(t, trainer.x > start.x + 300, "the trainer should have walked away")
    p1 := sim.session.characters[0].position
    testing.expect(t, trainer.x - p1.x > 160 + TRAINER_RADIUS, "the trainer itself is outside the human nose range")
    for x in arena_world_to_cell(arena, start).x + 1..<arena_world_to_cell(arena, trainer).x {
        testing.expectf(t, perception.scent_field_level(field, .Human, {x, 5}) > 0.3, "crossed cell %d should hold a strong trace", x)
    }
    for _ in 0..<12 { simulation_tick(&sim, &content) }
    nose := sim.battle.receptors[0].olfaction.last
    human, present := reading_of(nose, .Human)
    testing.expect(t, present && human.bearing_valid && human.bearing == .East && human.strength != .None, "P1 smells the trail east of it after the trainer left")
    testing.expect(t, human.freshness == .Very_Recent || human.freshness == .Recent)
    testing.expect(t, nose.observer == sim.session.characters[0].entity_id && nose.position == p1 && nose.profile.range == 160)
    _, orc_present := reading_of(nose, .Orc)
    testing.expect(t, !orc_present)
    // The brain received the same anonymous reading and nothing more.
    testing.expect(t, sim.battle.agents[0].scent.count == 1 && sim.battle.agents[0].scent.entries[0].observation_id == human.observation_id)
    testing.expect(t, sim.battle.agents[0].search.acquisition_count == 0 && !sim.session.characters[0].target_alert, "smell never acquires a target")
    // Sixty seconds later the trail has faded below detection and the field cells are fading out.
    for _ in 0..<3600 { simulation_tick(&sim, &content) }
    faded := sim.battle.receptors[0].olfaction.last
    later, still := reading_of(faded, .Human)
    testing.expect(t, !still || (later.zones[obs.scent_zone_index(2, true)] == .None && later.strength == .Weak), "the far eastern trail has faded")
    testing.expect(t, perception.scent_field_level(field, .Human, {10, 5}) < perception.SCENT_WEAK_LEVEL)
    testing.expect(t, perception.scent_field_level(field, .Human, arena_world_to_cell(arena, sim.session.trainers[0].position)) >= 0.9, "the standing trainer keeps its cell near saturation")
    // A new round clears the ground and both minds; teleporting to the new placement paints no trail.
    when ODIN_DEBUG {
        changed, rejected := session_apply(&sim.session, &content, 1, {kind = .Dev_Reset_Search, round_id = sim.session.round_id}, true)
        if !changed || rejected != .None { session_reset(&sim.session) }
    } else {
        session_reset(&sim.session)
    }
    if sim.session.phase != .In_Arena {
        sim.session.map_id = map_id
        for &player in sim.session.players { player = {present = true, ready = true, character_id = 5} }
        session_enter_arena(&sim.session, &content)
    }
    simulation_tick(&sim, &content)
    testing.expect(t, !sim.battle.scent.field.bounds.active && perception.scent_field_total(&sim.battle.scent.field, .Human) == 0, "reset must clear the field")
    testing.expect(t, sim.battle.agents[0].scent == ai.Scent_Memory{} && sim.battle.receptors[0].olfaction.last.status == .Waiting_For_Summon)
    for _ in 0..<89 { simulation_tick(&sim, &content) }
    testing.expect(t, !sim.battle.scent.field.bounds.active, "nothing is painted while summoning")
    simulation_tick(&sim, &content)
    testing.expect(t, sim.battle.scent.field.bounds.active, "emission resumes on the first live tick of the new round")
}

@(test)
orc_nose_reaches_a_trail_the_human_nose_cannot_and_scentless_bodies_add_nothing :: proc(t: ^testing.T) {
    content: Game_Content
    map_id := battle_test_content_with_qa(t, &content)
    defer content_destroy(&content)
    silence_creature_emitters(&content)
    arena := content_arena(&content, map_id)
    // Same trainer trail, two noses: the archer's 160 units versus the orc's 256.
    samples: [2]obs.Scent_Sample
    for pick, index in ([2]u16{5, 6}) {
        sim := scent_test_scenario(&content, map_id, {pick, 5})
        // Everybody else stands beyond even the orc's reach before the round goes live.
        sim.session.trainers[0].position = arena_cell_center(arena, {2, 12})
        sim.session.characters[1].position = arena_cell_center(arena, {20, 12})
        sim.session.trainers[1].position = arena_cell_center(arena, {13, 8})
        for _ in 0..<90 { simulation_tick(&sim, &content) }
        // Trainer 2 lays a north-south line about 192 units east of P1, then stands at its top.
        sequence: u32
        walk_trainer(&sim, &content, 2, 4, 150, &sequence)
        for _ in 0..<12 { simulation_tick(&sim, &content) }
        samples[index] = sim.battle.receptors[0].olfaction.last
        testing.expect(t, samples[index].status == .Sampled && samples[index].profile.range == (160 if pick == 5 else 256))
    }
    _, human_smells := reading_of(samples[0], .Human)
    orc_reading, orc_smells := reading_of(samples[1], .Human)
    testing.expect(t, !human_smells, "the human nose cannot reach a trail 192 units away")
    testing.expect(t, orc_smells && orc_reading.bearing_valid && (orc_reading.bearing == .East || orc_reading.bearing == .North_East), "the orc nose reaches it and smells generic human scent to the east")
    testing.expect(t, samples[1].readings[0].class == .Human && samples[1].reading_count == 1, "the class is generic human, nothing more")
    // Scentless sensors: diamond bodies emit nothing, yet their nose reads the trainers.
    scentless := scent_test_scenario(&content, map_id, {4, 4})
    content_character(&content, 4).emitter.enabled = false
    for _ in 0..<600 { simulation_tick(&scentless, &content) }
    field := &scentless.battle.scent.field
    for character in scentless.session.characters {
        cell := arena_world_to_cell(arena, character.position)
        testing.expect(t, perception.scent_field_level(field, .Human, cell) == 0 && perception.scent_field_level(field, .Orc, cell) == 0, "a scentless body leaves no trace")
    }
    for trainer in scentless.session.trainers { testing.expect(t, perception.scent_field_level(field, .Human, arena_world_to_cell(arena, trainer.position)) == perception.SCENT_CAP) }
    nose := scentless.battle.receptors[0].olfaction.last
    reading, smells := reading_of(nose, .Human)
    testing.expect(t, nose.status == .Sampled && smells && reading.strength != .None, "the scentless diamond still smells its trainer")
    testing.expect(t, !scentless.battle.scent.emitters[0].emitter.enabled && scentless.battle.scent.emitters[MAX_PLAYERS].emitter.enabled)
    // Emission and sensing are separate settings in the shipped catalog.
    shipped: Game_Content
    testing.expect(t, content_load(&shipped, "client/content/data"))
    defer content_destroy(&shipped)
    diamond, archer := content_character(&shipped, 4), content_character(&shipped, 5)
    testing.expect(t, diamond.olfaction.enabled && !diamond.olfaction.estimates_freshness && !diamond.emitter.enabled && archer.olfaction.enabled && archer.emitter.enabled && archer.emitter.class == .Human)
    for shape in ([]u16{1, 2, 3}) {
        placeholder := content_character(&shipped, shape)
        testing.expect(t, !placeholder.olfaction.enabled && !placeholder.emitter.enabled, "placeholder shapes neither smell nor emit")
    }
    testing.expect(t, content_character(&shipped, 6).olfaction.range > archer.olfaction.range && content_character(&shipped, 6).emitter.class == .Orc)
}

// A pocket arena: P1 stands west of a stone column it cannot see through, while
// the ground just east of the column is inside its nose range.
@(private = "file")
pocket_arena :: proc(t: ^testing.T, content: ^Game_Content) -> u16 {
    testing.expect(t, content_load(content, "client/content/data"))
    rows := `["tttttttttttttttttttt","t.......#..........t","t.......#..........t","t.......#..........t","t.......#..........t","t.......#..........t","t.......#..........t","t.......#..........t","t.......#..........t","tttttttttttttttttttt"]`
    heights := `["00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000"]`
    catalog := strings.concatenate({`{"schema_version": 2, "arenas": [{"id": 8, "key": "scent_pocket", "display_name": "Scent Pocket", "width": 20, "height": 10, "tile_size": 32, "rows": `, rows, `, "elevation_rows": `, heights, `, "spawns": [[2, 5], [16, 5]]}]}`}, context.temp_allocator)
    testing.expect(t, content_parse_extra(content, transmute([]u8)catalog, .Arenas))
    return content.arenas[len(content.arenas) - 1].id
}

@(test)
hidden_emitter_identity_and_private_state_do_not_change_what_is_smelled :: proc(t: ^testing.T) {
    content_a, content_b: Game_Content
    map_a := pocket_arena(t, &content_a)
    map_b := pocket_arena(t, &content_b)
    defer content_destroy(&content_a)
    defer content_destroy(&content_b)
    silence_creature_emitters(&content_a)
    silence_creature_emitters(&content_b)
    arena := content_arena(&content_a, map_a)
    a := scent_test_scenario(&content_a, map_a, {5, 5})
    b := scent_test_scenario(&content_b, map_b, {5, 5})
    // P1 sits in the pocket. In A trainer 2 walks the line east of the column; in B
    // trainer 1 walks the same line while the other bodies and P2's mind differ.
    line := arena_cell_center(arena, {10, 8})
    for sim in ([]^Simulation{&a, &b}) { sim.session.characters[0].position = arena_cell_center(arena, {6, 5}) }
    a.session.trainers[1].position, a.session.trainers[0].position = line, arena_cell_center(arena, {16, 2})
    b.session.trainers[0].position, b.session.trainers[1].position = line, arena_cell_center(arena, {17, 7})
    a.session.characters[1].position = arena_cell_center(arena, {15, 7})
    b.session.characters[1].position = arena_cell_center(arena, {13, 2})
    b.session.characters[1].facing = .North
    sequence_a, sequence_b: u32
    smelled := false
    for tick in 0..<720 {
        mask: u8 = 4 if tick >= 90 && tick < 200 else 0 // north along the line, then stand
        sequence_a += 1
        sequence_b += 1
        session_apply(&a.session, &content_a, 2, {kind = .Input, round_id = a.session.round_id, input_sequence = sequence_a, input_mask = mask})
        session_apply(&b.session, &content_b, 1, {kind = .Input, round_id = b.session.round_id, input_sequence = sequence_b, input_mask = mask})
        simulation_tick(&a, &content_a)
        simulation_tick(&b, &content_b)
        if tick == 300 { b.battle.agents[1].memory, b.battle.agents[1].scent = {}, {} }
        testing.expect(t, a.battle.receptors[0].olfaction.last == b.battle.receptors[0].olfaction.last, "who laid the trail changed P1's smell")
        testing.expect(t, a.battle.receptors[0].vision.last == b.battle.receptors[0].vision.last, "hidden bodies changed P1's sight")
        testing.expect(t, a.battle.agents[0] == b.battle.agents[0] && a.session.characters[0] == b.session.characters[0], "hidden differences reached P1's mind or actions")
        if _, present := reading_of(a.battle.receptors[0].olfaction.last, .Human); present { smelled = true }
    }
    testing.expect(t, smelled && a.battle.agents[0].scent.ingested_samples > 40, "the trail beyond the column was actually smelled")
    testing.expect(t, a.battle.agents[0].memory.focused_count == 0, "nobody was ever seen through the column")
    testing.expect(t, a.battle.receptors[0].olfaction.audit != b.battle.receptors[0].olfaction.audit || a.session.trainers[0].position != b.session.trainers[0].position, "the hidden worlds really differ")
}

@(test)
replacing_one_creature_keeps_the_other_mind_and_the_ground_and_workers_agree :: proc(t: ^testing.T) {
    content: Game_Content
    map_id := battle_test_content_with_qa(t, &content)
    defer content_destroy(&content)
    a := battle_test_scenario(&content, map_id, 5, 77)
    a.observe_only = false
    b := a
    workers := new(Brain_Workers)
    defer free(workers)
    brain_workers_init(workers)
    defer brain_workers_destroy(workers)
    for _ in 0..<900 {
        simulation_tick(&a, &content)
        simulation_tick(&b, &content, workers)
        testing.expect(t, a.battle == b.battle && a.session == b.session, "dedicated workers changed the field, the samples or the search")
    }
    testing.expect(t, a.battle.scent.field.bounds.active && a.battle.agents[0].scent.ingested_samples > 60)
    kept := a.battle.agents[1]
    kept_receptor := a.battle.receptors[1]
    ground := a.battle.scent.field
    a.session.characters[0].entity_id += 1000
    battle_sync(&a.battle, &a.session, &content, a.seed, .Search)
    testing.expect(t, a.battle.agents[1] == kept && a.battle.receptors[1] == kept_receptor, "replacement touched the other creature's mind or nose")
    testing.expect(t, a.battle.agents[0].scent == ai.Scent_Memory{} && a.battle.receptors[0].olfaction == Olfaction_Receptor{profile = kept_receptor.olfaction.profile})
    testing.expect(t, a.battle.scent.field == ground, "old deposits stay on the ground for the replacement to smell")
    testing.expect(t, a.battle.scent.emitters[0].entity_id == a.session.characters[0].entity_id && a.battle.scent.emitters[0].armed)
    total := perception.scent_field_total(&a.battle.scent.field, .Human)
    simulation_tick(&a, &content)
    testing.expect(t, perception.scent_field_total(&a.battle.scent.field, .Human) <= total + 4 * perception.SCENT_EMISSION_PER_TICK + 0.001, "a re-armed emitter paints no jump trail")
}

@(test)
scent_field_capture_matches_the_field_and_its_publication_stays_bounded :: proc(t: ^testing.T) {
    content: Game_Content
    map_id := battle_test_content_with_qa(t, &content)
    defer content_destroy(&content)
    debug := new(AI_Debug)
    defer free(debug)
    directory := fmt.aprintf("build/scent-debug-test-%d", sync.current_thread_id())
    defer delete(directory)
    testing.expect(t, os.make_directory(directory) == nil)
    debug.directory, debug.run_id, debug.fingerprint = directory, "scent-capture", "00"
    sim := battle_test_scenario(&content, map_id, 5)
    for _ in 0..<300 { simulation_tick(&sim, &content, nil, debug) }
    capture := &debug.scent_capture
    field := &sim.battle.scent.field
    // The capture follows field steps (10 Hz); compare right after a tick that stepped.
    for capture.tick != sim.session.server_tick { simulation_tick(&sim, &content, nil, debug) }
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
    session_reset(&sim.session)
    simulation_tick(&sim, &content, nil, debug)
    testing.expect(t, !debug.scent_capture.valid)
}
