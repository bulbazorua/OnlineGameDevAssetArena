package simulation

import "../content"
import "core:testing"
import ai "../ai"
import obs "../observations"
import "../perception"

@(test)
qa_arena_geometry_matches_the_documented_setup :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    sim := battle_test_scenario(&catalog, map_id, 5)
    arena := content.find_arena(&catalog, map_id)
    testing.expect(t, arena.key == "vision_range" && arena.width == 24 && arena.height == 14)
    p1, p2 := sim.session.characters[0], sim.session.characters[1]
    testing.expect(t, p1.position == content.arena_cell_center(arena, {7, 5}) && p2.position == content.arena_cell_center(arena, {12, 10}))
    testing.expect(t, p1.facing == .East && p2.facing == .West)
    testing.expect(t, sim.session.trainers[0].position == content.arena_cell_center(arena, {5, 5}) && sim.session.trainers[1].position == content.arena_cell_center(arena, {14, 10}))
    for _ in 0..<91 { advance(&sim, &catalog) }
    // First unlocked tick: each eye samples once, and each creature is a coarse
    // peripheral cue for the other (sector 1, far band), not a focused sighting.
    for receptor, index in sim.battle.receptors {
        testing.expect(t, receptor.vision.schedule.sample_counter == 1 && receptor.vision.last.sample_tick == 91 && receptor.vision.last.status == .Sampled)
        testing.expect(t, receptor.vision.last.focused_count == 0 && receptor.vision.last.cue_count == 1 && receptor.vision.last.cues[0].sector == 1 && receptor.vision.last.cues[0].band == .Far)
        testing.expect(t, receptor.vision.audit.candidates[0].verdict == .Peripheral, "other creature")
        // Own trainer is behind; the other trainer is out of range.
        testing.expect(t, receptor.vision.audit.candidates[1 + index].verdict == .Outside_Field && receptor.vision.audit.candidates[2 - index].verdict == .Out_Of_Range)
        testing.expect(t, sim.battle.agents[index].last.reason == .Orient && sim.battle.agents[index].last.result.kind == .Turned)
    }
    testing.expect(t, sim.session.characters[0].facing == .South_East && sim.session.characters[1].facing == .North_West)
    for _ in 0..<6 { advance(&sim, &catalog) }
    for receptor, index in sim.battle.receptors {
        testing.expect(t, receptor.vision.schedule.sample_counter == 2 && receptor.vision.last.sample_tick == 97 && receptor.vision.last.focused_count == 1 && receptor.vision.last.cue_count == 0)
        testing.expect(t, receptor.vision.last.focused[0].subject == obs.Subject_Handle(sim.session.characters[1 - index].entity_id) && receptor.vision.last.focused[0].kind == .Creature)
        testing.expect(t, sim.battle.agents[index].last.reason == .Observe && sim.battle.agents[index].attention.subject == receptor.vision.last.focused[0].subject)
    }
    // Cover: the wall hides the east column two rows above P2; water does not hide.
    grid := content.arena_opacity_grid(arena)
    p1_eye := sim.session.characters[0].position
    testing.expect(t, !perception.line_of_sight(grid, p1_eye, content.arena_cell_center(arena, {14, 8})), "wall should hide (14,8) from P1")
    testing.expect(t, perception.line_of_sight(grid, p1_eye, content.arena_cell_center(arena, {14, 6})), "(14,6) is visible past the wall")
    testing.expect(t, perception.line_of_sight(grid, p1_eye, content.arena_cell_center(arena, {11, 1})), "water pool does not block sight")
    testing.expect(t, content.arena_cell_is_blocked(arena, &catalog, {10, 2}) && !content.arena_cell_blocks_sight(arena, &catalog, {10, 2}))
}

@(test)
sampling_uses_frozen_poses_with_independent_deadlines_and_slot_order_independence :: proc(t: ^testing.T) {
    catalog: content.Game_Content
    map_id := battle_test_content_with_qa(t, &catalog)
    defer content.destroy(&catalog)
    sim := battle_test_scenario(&catalog, map_id, 6)
    // P1 already faces the periphery of P2 and turns on its first unlocked tick;
    // P2's eye, which samples on that same tick, must record P1's pre-turn facing.
    sim.session.characters[1].position = sim.session.characters[0].position + {100, 0}
    sim.session.characters[0].facing = .North_East
    for _ in 0..<90 { advance(&sim, &catalog) }
    sim.battle.receptors[1].vision.profile.sample_interval = 12 // Private host schedule differs per instance.
    before := sim.session.characters
    advance(&sim, &catalog)
    testing.expect(t, sim.session.characters[0].facing == .East && before[0].facing == .North_East, "P1 should turn toward the cue at tick 91")
    p2 := sim.battle.receptors[1].vision.last
    // P2 sees P1 and, beyond it, P1's trainer: two focused sightings from one sample.
    testing.expect(t, p2.sample_tick == 91 && p2.focused_count == 2 && p2.focused[0].subject == obs.Subject_Handle(before[0].entity_id))
    testing.expect(t, p2.focused[0].facing == .North_East && p2.focused[0].position == before[0].position, "P2 observed a pose from after P1's action")
    testing.expect(t, p2.focused[1].kind == .Trainer && p2.pose.facing == character_facing_to_observation(before[1].facing))
    // P2 is already aligned and holds; its retained sample keeps P1's original pose and time
    // for eleven more ticks even though P1 has turned.
    testing.expect(t, sim.session.characters[1].facing == before[1].facing && sim.battle.agents[1].last.reason == .Observe)
    for tick in u32(92)..<103 {
        advance(&sim, &catalog)
        retained := sim.battle.receptors[1].vision.last
        testing.expect(t, retained == p2 && sim.battle.receptors[1].vision.schedule.sample_counter == 1, "P2's retained sample changed between its samples")
        testing.expect(t, sim.battle.receptors[0].vision.schedule.sample_counter == u32(1 + (tick - 91) / 6))
    }
    advance(&sim, &catalog)
    testing.expect(t, sim.battle.receptors[1].vision.schedule.sample_counter == 2 && sim.battle.receptors[1].vision.last.sample_tick == 103)
    // Slot order cannot change an observer's evidence: swap the two creature slots
    // in a copied session and compare each observer's sample by entity.
    copied := sim
    copied.session.characters[0], copied.session.characters[1] = sim.session.characters[1], sim.session.characters[0]
    copied.session.trainers[0], copied.session.trainers[1] = sim.session.trainers[1], sim.session.trainers[0]
    copied.battle.receptors[0], copied.battle.receptors[1] = sim.battle.receptors[1], sim.battle.receptors[0]
    copied.battle.receptors[0].vision.profile.sample_interval = 6
    copied.battle.receptors[1].vision.profile.sample_interval = 6
    original := sim
    original.battle.receptors[0].vision.profile.sample_interval = 6
    original.battle.receptors[1].vision.profile.sample_interval = 6
    original.battle.receptors[0].vision.schedule.armed, original.battle.receptors[1].vision.schedule.armed = false, false
    copied.battle.receptors[0].vision.schedule.armed, copied.battle.receptors[1].vision.schedule.armed = false, false
    straight := senses_prepare(&original.battle.receptors, &original.battle.scent.field, &original.session, &catalog, true)
    swapped := senses_prepare(&copied.battle.receptors, &copied.battle.scent.field, &copied.session, &catalog, true)
    testing.expect(t, straight[0].vision == swapped[1].vision && straight[1].vision == swapped[0].vision && straight[0].vision_is_new && swapped[1].vision_is_new)
    testing.expect(t, straight[0].vision.observer != straight[1].vision.observer)
    // Statuses: summon lock waits; a disabled profile is explicit, not an empty sample.
    locked := battle_test_scenario(&catalog, map_id, 5)
    advance(&locked, &catalog)
    testing.expect(t, locked.battle.receptors[0].vision.last.status == .Waiting_For_Summon && locked.battle.receptors[0].vision.schedule.sample_counter == 0)
    testing.expect(t, locked.battle.agents[0].last.reason == .Locked && locked.battle.agents[0].memory.ingested_samples == 0)
    locked.battle.receptors[0].vision.profile.enabled = false
    for _ in 0..<95 { advance(&locked, &catalog) }
    testing.expect(t, locked.battle.receptors[0].vision.last.status == .Disabled && locked.battle.receptors[0].vision.schedule.sample_counter == 0 && locked.battle.agents[0].last.reason == .Scan)
    testing.expect(t, locked.battle.receptors[1].vision.last.status == .Sampled && locked.battle.agents[1].last.reason == .Orient)
    // Reset clears receptors and memories; a new round starts from nothing.
    session_reset(&locked.session)
    advance(&locked, &catalog)
    testing.expect(t, locked.battle == Battle_Runtime{})
    testing.expect(t, size_of(ai.Decision_Context) < 1024, "worker request payload should stay small")
}
