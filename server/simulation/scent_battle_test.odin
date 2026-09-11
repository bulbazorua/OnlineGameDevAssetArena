package simulation

import "../content"
import ai "../ai"
import obs "../observations"
import "../perception"
import "core:math"
import "core:strings"
import "core:testing"

@(private = "file")
walk_trainer :: proc(sim: ^Simulation, catalog: ^content.Game_Content, player: u8, mask: u8, ticks: int, sequence: ^u32) {
    for _ in 0..<ticks {
        sequence^ += 1
        session_apply(&sim.session, catalog, player, {kind = .Input, round_id = sim.session.round_id, input_sequence = sequence^, input_mask = mask})
        advance(sim, catalog)
    }
}

@(private = "file")
reading_of :: proc(sample: obs.Scent_Sample, class: obs.Scent_Class) -> (obs.Scent_Reading, bool) {
    readings := sample.readings
    for reading in readings[:sample.reading_count] { if reading.class == class { return reading, true } }
    return {}, false
}

@(private = "file")
silence_creature_emitters :: proc(catalog: ^content.Game_Content) {
    for &character in catalog.characters { character.emitter.enabled = false }
}

// A pocket arena: P1 stands west of a stone column it cannot see through, while
// the ground just east of the column is inside its nose range.
@(private = "file")
pocket_arena :: proc(t: ^testing.T, catalog: ^content.Game_Content) -> u16 {
    testing.expect(t, content.load(catalog, "client/content/data"))
    rows := `["tttttttttttttttttttt","t.......#..........t","t.......#..........t","t.......#..........t","t.......#..........t","t.......#..........t","t.......#..........t","t.......#..........t","t.......#..........t","tttttttttttttttttttt"]`
    heights := `["00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000","00000000000000000000"]`
    arena_json := strings.concatenate({`{"schema_version": 2, "arenas": [{"id": 8, "key": "scent_pocket", "display_name": "Scent Pocket", "width": 20, "height": 10, "tile_size": 32, "rows": `, rows, `, "elevation_rows": `, heights, `, "spawns": [[2, 5], [16, 5]]}]}`}, context.temp_allocator)
    testing.expect(t, content.parse_extra(catalog, transmute([]u8)arena_json, .Arenas))
    return catalog.arenas[len(catalog.arenas) - 1].id
}

// Independent oracle: classify every cell centre inside reach with the arena's own
// media and edges, then fold the counts into the same three coverage words.
@(private = "file")
expected_coverage :: proc(arena: ^content.Arena_Definition, nose: [2]f32, range: f32) -> (coverage: [obs.SCENT_ZONES]obs.Scent_Coverage) {
    sampled, excluded: [obs.SCENT_ZONES]int
    tile := f32(arena.tile_size)
    reach := int(math.ceil(range / tile)) + 1
    origin := content.arena_world_to_cell(arena, nose)
    for y in origin.y - reach..=origin.y + reach {
        for x in origin.x - reach..=origin.x + reach {
            offset := content.arena_cell_center(arena, {x, y}) - nose
            distance := math.sqrt(offset.x * offset.x + offset.y * offset.y)
            if distance > range || distance <= perception.SCENT_BLIND_RADIUS_TILES * tile { continue }
            zone := obs.scent_zone_index(perception.scent_sector_of(offset), distance > range * 0.5)
            inside := x >= 0 && y >= 0 && x < arena.width && y < arena.height
            if inside && arena.scent_media[y * arena.width + x] != .Solid { sampled[zone] += 1 } else { excluded[zone] += 1 }
        }
    }
    for zone in 0..<obs.SCENT_ZONES { coverage[zone] = perception.scent_coverage_of(sampled[zone], excluded[zone]) }
    return
}

@(test)
trail_persists_after_the_trainer_leaves_then_fades_while_reset_paints_nothing :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    silence_creature_emitters(&catalog)
    sim := scent_test_scenario(&catalog, map_id, {5, 5})
    arena := content.find_arena(&catalog, map_id)
    // Trainer 1 starts just east of its creature so its whole trail lies east of the nose.
    sim.session.trainers[0].position = content.arena_cell_center(arena, {8, 5})
    for _ in 0..<91 { advance(&sim, &catalog) }
    field := &sim.battle.scent.field
    testing.expect(t, perception.scent_field_valid(field) && field.width == arena.width && field.tile_size == 32)
    testing.expect(t, sim.battle.receptors[0].olfaction.last.status == .Sampled && sim.battle.receptors[0].olfaction.schedule.sample_counter == 1)
    // Summoning painted nothing; the very first live tick deposits under the standing trainers.
    testing.expect(t, field.bounds.active && perception.scent_field_level(field, .Human, content.arena_world_to_cell(arena, sim.session.trainers[0].position)) > 0)
    testing.expect(t, perception.scent_field_level(field, .Human, content.arena_world_to_cell(arena, sim.session.characters[0].position)) == 0, "a silenced creature emits nothing")
    // Trainer 1 walks east along row 5 for three seconds, right past its creature.
    sequence: u32
    start := sim.session.trainers[0].position
    walk_trainer(&sim, &catalog, 1, 2, 180, &sequence)
    trainer := sim.session.trainers[0].position
    testing.expect(t, trainer.x > start.x + 300, "the trainer should have walked away")
    p1 := sim.session.characters[0].position
    testing.expect(t, trainer.x - p1.x > 160 + TRAINER_RADIUS, "the trainer itself is outside the human nose range")
    for x in content.arena_world_to_cell(arena, start).x + 1..<content.arena_world_to_cell(arena, trainer).x {
        testing.expectf(t, perception.scent_field_level(field, .Human, {x, 5}) > 0.3, "crossed cell %d should hold a strong trace", x)
    }
    for _ in 0..<12 { advance(&sim, &catalog) }
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
    for _ in 0..<3600 { advance(&sim, &catalog) }
    faded := sim.battle.receptors[0].olfaction.last
    later, still := reading_of(faded, .Human)
    testing.expect(t, !still || (later.zones[obs.scent_zone_index(2, true)] == .None && later.strength == .Weak), "the far eastern trail has faded")
    testing.expect(t, perception.scent_field_level(field, .Human, {10, 5}) < perception.SCENT_WEAK_LEVEL)
    testing.expect(t, perception.scent_field_level(field, .Human, content.arena_world_to_cell(arena, sim.session.trainers[0].position)) >= 0.9, "the standing trainer keeps its cell near saturation")
    // A new round clears the ground and both minds; teleporting to the new placement paints no trail.
    when ODIN_DEBUG {
        changed, rejected := session_apply(&sim.session, &catalog, 1, {kind = .Dev_Reset_Search, round_id = sim.session.round_id}, true)
        if !changed || rejected != .None { session_reset(&sim.session) }
    } else {
        session_reset(&sim.session)
    }
    if sim.session.phase != .In_Arena {
        sim.session.map_id = map_id
        for &player in sim.session.players { player = {present = true, ready = true, character_id = 5} }
        session_enter_arena(&sim.session, &catalog)
    }
    advance(&sim, &catalog)
    testing.expect(t, !sim.battle.scent.field.bounds.active && perception.scent_field_total(&sim.battle.scent.field, .Human) == 0, "reset must clear the field")
    testing.expect(t, sim.battle.agents[0].scent == ai.Scent_Memory{} && sim.battle.receptors[0].olfaction.last.status == .Waiting_For_Summon)
    for _ in 0..<89 { advance(&sim, &catalog) }
    testing.expect(t, !sim.battle.scent.field.bounds.active, "nothing is painted while summoning")
    advance(&sim, &catalog)
    testing.expect(t, sim.battle.scent.field.bounds.active, "emission resumes on the first live tick of the new round")
}

@(test)
orc_nose_reaches_a_trail_the_human_nose_cannot_and_scentless_bodies_add_nothing :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    silence_creature_emitters(&catalog)
    arena := content.find_arena(&catalog, map_id)
    // Same trainer trail, two noses: the archer's 160 units versus the orc's 256.
    samples: [2]obs.Scent_Sample
    for pick, index in ([2]u16{5, 6}) {
        sim := scent_test_scenario(&catalog, map_id, {pick, 5})
        // Everybody else stands beyond even the orc's reach before the round goes live.
        sim.session.trainers[0].position = content.arena_cell_center(arena, {2, 12})
        sim.session.characters[1].position = content.arena_cell_center(arena, {20, 12})
        sim.session.trainers[1].position = content.arena_cell_center(arena, {13, 8})
        for _ in 0..<90 { advance(&sim, &catalog) }
        // Trainer 2 lays a north-south line about 192 units east of P1, then stands at its top.
        sequence: u32
        walk_trainer(&sim, &catalog, 2, 4, 150, &sequence)
        for _ in 0..<12 { advance(&sim, &catalog) }
        samples[index] = sim.battle.receptors[0].olfaction.last
        testing.expect(t, samples[index].status == .Sampled && samples[index].profile.range == (160 if pick == 5 else 256))
    }
    _, human_smells := reading_of(samples[0], .Human)
    orc_reading, orc_smells := reading_of(samples[1], .Human)
    testing.expect(t, !human_smells, "the human nose cannot reach a trail 192 units away")
    testing.expect(t, orc_smells && orc_reading.bearing_valid && (orc_reading.bearing == .East || orc_reading.bearing == .North_East), "the orc nose reaches it and smells generic human scent to the east")
    testing.expect(t, samples[1].readings[0].class == .Human && samples[1].reading_count == 1, "the class is generic human, nothing more")
    // Scentless sensors: diamond bodies emit nothing, yet their nose reads the trainers.
    scentless := scent_test_scenario(&catalog, map_id, {4, 4})
    content.find_character(&catalog, 4).emitter.enabled = false
    for _ in 0..<600 { advance(&scentless, &catalog) }
    field := &scentless.battle.scent.field
    for character in scentless.session.characters {
        cell := content.arena_world_to_cell(arena, character.position)
        testing.expect(t, perception.scent_field_level(field, .Human, cell) == 0 && perception.scent_field_level(field, .Orc, cell) == 0, "a scentless body leaves no trace")
    }
    for trainer in scentless.session.trainers { testing.expect(t, perception.scent_field_level(field, .Human, content.arena_world_to_cell(arena, trainer.position)) == perception.SCENT_CAP) }
    nose := scentless.battle.receptors[0].olfaction.last
    reading, smells := reading_of(nose, .Human)
    testing.expect(t, nose.status == .Sampled && smells && reading.strength != .None, "the scentless diamond still smells its trainer")
    testing.expect(t, !scentless.battle.scent.emitters[0].emitter.enabled && scentless.battle.scent.emitters[MAX_PLAYERS].emitter.enabled)
    // Emission and sensing are separate settings in the shipped catalog.
    shipped: content.Game_Content
    testing.expect(t, content.load(&shipped, "client/content/data"))
    defer content.destroy(&shipped)
    diamond, archer := content.find_character(&shipped, 4), content.find_character(&shipped, 5)
    testing.expect(t, diamond.olfaction.enabled && !diamond.olfaction.estimates_freshness && !diamond.emitter.enabled && archer.olfaction.enabled && archer.emitter.enabled && archer.emitter.class == .Human)
    for shape in ([]u16{1, 2, 3}) {
        placeholder := content.find_character(&shipped, shape)
        testing.expect(t, !placeholder.olfaction.enabled && !placeholder.emitter.enabled, "placeholder shapes neither smell nor emit")
    }
    testing.expect(t, content.find_character(&shipped, 6).olfaction.range > archer.olfaction.range && content.find_character(&shipped, 6).emitter.class == .Orc)
}

@(test)
hidden_emitter_identity_and_private_state_do_not_change_what_is_smelled :: proc(t: ^testing.T) {
    catalog_a, catalog_b: content.Game_Content
    map_a := pocket_arena(t, &catalog_a)
    map_b := pocket_arena(t, &catalog_b)
    defer content.destroy(&catalog_a)
    defer content.destroy(&catalog_b)
    silence_creature_emitters(&catalog_a)
    silence_creature_emitters(&catalog_b)
    arena := content.find_arena(&catalog_a, map_a)
    a := scent_test_scenario(&catalog_a, map_a, {5, 5})
    b := scent_test_scenario(&catalog_b, map_b, {5, 5})
    // P1 sits in the pocket. In A trainer 2 walks the line east of the column; in B
    // trainer 1 walks the same line while the other bodies and P2's mind differ.
    line := content.arena_cell_center(arena, {10, 8})
    for sim in ([]^Simulation{&a, &b}) { sim.session.characters[0].position = content.arena_cell_center(arena, {6, 5}) }
    a.session.trainers[1].position, a.session.trainers[0].position = line, content.arena_cell_center(arena, {16, 2})
    b.session.trainers[0].position, b.session.trainers[1].position = line, content.arena_cell_center(arena, {17, 7})
    a.session.characters[1].position = content.arena_cell_center(arena, {15, 7})
    b.session.characters[1].position = content.arena_cell_center(arena, {13, 2})
    b.session.characters[1].facing = .North
    sequence_a, sequence_b: u32
    smelled := false
    for tick in 0..<720 {
        mask: u8 = 4 if tick >= 90 && tick < 200 else 0 // north along the line, then stand
        sequence_a += 1
        sequence_b += 1
        session_apply(&a.session, &catalog_a, 2, {kind = .Input, round_id = a.session.round_id, input_sequence = sequence_a, input_mask = mask})
        session_apply(&b.session, &catalog_b, 1, {kind = .Input, round_id = b.session.round_id, input_sequence = sequence_b, input_mask = mask})
        advance(&a, &catalog_a)
        advance(&b, &catalog_b)
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
delivered_coverage_matches_the_arena_geometry :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    arena := content.find_arena(&catalog, map_id)
    // The archer stands in the north-west corner pocket; the orc in the open middle.
    sim := scent_test_scenario(&catalog, map_id, {5, 6})
    sim.session.characters[0].position = content.arena_cell_center(arena, {2, 1})
    sim.session.characters[1].position = content.arena_cell_center(arena, {16, 6})
    for _ in 0..<91 { advance(&sim, &catalog) }
    for index in 0..<MAX_PLAYERS {
        sample := sim.battle.receptors[index].olfaction.last
        testing.expect(t, sample.status == .Sampled && sample.position == sim.session.characters[index].position)
        expected := expected_coverage(arena, sample.position, sample.profile.range)
        testing.expectf(t, sample.coverage == expected, "P%d coverage %v differs from the arena geometry %v", index + 1, sample.coverage, expected)
    }
    corner := sim.battle.receptors[0].olfaction.last
    testing.expect(t, corner.coverage[obs.scent_zone_index(0, true)] == .Unsampled && corner.coverage[obs.scent_zone_index(6, true)] == .Unsampled, "beyond the trees and the edge is unknown, not empty")
    testing.expect(t, corner.coverage[obs.scent_zone_index(3, false)] == .Sampled && corner.coverage[obs.scent_zone_index(3, true)] == .Sampled, "the open south-east is fully measured")
    testing.expect(t, sim.battle.receptors[0].olfaction.audit.cells_excluded > 0, "the corner pocket leaves unmeasurable ground inside reach")
}
