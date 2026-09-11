package ai

import obs "../observations"
import "core:testing"

search_test_context :: proc(tick: u32, entity: u32 = 3) -> Decision_Context {
    return {entity_id = entity, round_id = 1, tick = tick, position = {100, 100}, facing = .East, can_act = true, turn_ready = true,
        senses = {vision_is_new = true, vision = {sample_id = tick + 1, observer = entity, round_id = 1, sample_tick = tick, delivered_tick = tick,
            status = .Sampled, pose = {{100, 100}, .East}, profile = {true, 256, 60, 160, 6}}}}
}

@(test)
search_acquires_only_focused_creatures_and_abandons_unchanged_last_position :: proc(t: ^testing.T) {
    a := agent_reset(3, 1, .Search, 42)
    config := observe_defaults()
    ctx := search_test_context(100)
    ctx.senses.vision.focused_count = 1
    ctx.senses.vision.focused[0] = {101, 7, .Trainer, 1, {200, 100}, .East, .Idle}
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.state == .Extensive_Search && a.search.target == 0 && a.search.acquisition_count == 0)
    ctx = search_test_context(106)
    ctx.senses.vision.focused_count = 1
    ctx.senses.vision.focused[0] = {102, 8, .Creature, 5, {200, 100}, .West, .Walk}
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.state == .Pursue && a.search.target == 8 && a.intent.kind == .Move && a.intent.direction.x > 0)
    testing.expect(t, a.search.acquisition_count == 1 && a.search.acquired_tick == 106)
    for tick in u32(107)..<112 {
        ctx.tick, ctx.senses.vision_is_new = tick, false
        agent_decide(&a, ctx, config)
        testing.expect(t, a.search.acquisition_count == 1 && a.search.target_tick == 106)
    }
    ctx = search_test_context(112)
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.state == .Last_Known_Position && !a.search.target_visible && a.search.target_position == Vector{200, 100})
    ctx = search_test_context(120)
    ctx.position = {199, 100}
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.state == .Intensive_Search && a.search.center == Vector{200, 100})
    for tick in u32(121)..=586 {
        ctx = search_test_context(tick)
        ctx.position = {199, 100}
        agent_decide(&a, ctx, config)
    }
    testing.expect(t, a.search.state == .Extensive_Search && !a.search.center_valid && a.search.target == 0 && a.search.abandoned_count == 1)
    testing.expect(t, a.memory.focused_count == 0 && a.search.evidence == .None)
}

@(test)
coarse_cue_drives_a_hypothesis_then_local_search_without_inventing_a_target :: proc(t: ^testing.T) {
    a := agent_reset(3, 1, .Search, 42)
    ctx := search_test_context(100)
    ctx.senses.vision.cue_count = 1
    ctx.senses.vision.cues[0] = {101, 1, .Far}
    agent_decide(&a, ctx, observe_defaults())
    testing.expect(t, a.search.state == .Investigate && a.search.cue_direction == .South_East)
    testing.expect(t, a.search.target == 0 && a.search.target_position == Vector{} && a.search.center == ctx.position && a.search.acquisition_count == 0)
    testing.expect(t, a.search.confidence > 0 && a.search.confidence < 1)
    agent_decide(&a, search_test_context(130), observe_defaults())
    testing.expect(t, a.search.state == .Intensive_Search && a.search.evidence_tick == 100)
    initial_radius := a.search.radius
    agent_decide(&a, search_test_context(400), observe_defaults())
    testing.expect(t, a.search.radius > initial_radius && a.search.target == 0)
    agent_decide(&a, search_test_context(580), observe_defaults())
    testing.expect(t, a.search.state == .Extensive_Search && !a.search.cue_valid)
}

@(test)
search_visits_are_private_bounded_and_decay_including_tick_wrap :: proc(t: ^testing.T) {
    a := agent_reset(3, 1, .Search)
    b := agent_reset(4, 1, .Search)
    search_remember_visit(&a.search, {100, 100}, 0xfffffff0)
    testing.expect(t, b.search.visit_count == 0)
    testing.expect(t, search_recent_penalty(&a.search, {100, 100}, 0x10) > 0.9)
    testing.expect(t, search_recent_penalty(&a.search, {100, 100}, 0x10 + 3600) == 0)
    testing.expect(t, search_recent_penalty(&a.search, {1000, 1000}, 0x10) == 0)
    a.search.profile.memory_capacity = 4
    a.search.visit_count = 0
    for tick in u32(0)..<100 { search_remember_visit(&a.search, {f32(tick) * 64, 0}, tick) }
    testing.expect(t, a.search.visit_count == 4 && b.search.visit_count == 0)
    for entry in a.search.visits[:a.search.visit_count] { testing.expect(t, entry.visited_tick >= 96) }
    search_remember_visit(&a.search, {0, 0}, 4000)
    testing.expect(t, a.search.visit_count == 1)
    testing.expect(t, search_profile_valid(search_defaults()))
    invalid := search_defaults()
    invalid.memory_capacity = SEARCH_MEMORY_CAPACITY + 1
    testing.expect(t, !search_profile_valid(invalid))
}

@(test)
search_commits_headings_relocates_and_changes_direction_after_blocked_feedback :: proc(t: ^testing.T) {
    a := agent_reset(3, 1, .Search, 42)
    ctx := search_test_context(100)
    config := observe_defaults()
    first := agent_decide(&a, ctx, config)
    for tick in u32(101)..<150 {
        ctx = search_test_context(tick)
        testing.expect(t, agent_decide(&a, ctx, config) == first, "heading jittered without a new reason")
    }
    heading := a.search.heading
    agent_record_result(&a, {kind = .Terrain_Blocked}, 150, config)
    agent_decide(&a, search_test_context(151), config)
    testing.expect(t, a.search.heading != heading && a.search.blocked[int(heading)] && a.search.blocked_count == 1)
    for tick in u32(152)..<5000 { agent_decide(&a, search_test_context(tick), config) }
    testing.expect(t, a.search.relocation_count > 0 && !a.search.blocked[int(heading)])
}

@(test)
search_seed_and_private_history_are_repeatable_and_diagnostics_do_not_change_decisions :: proc(t: ^testing.T) {
    a := agent_reset(3, 1, .Search, 42)
    b := a
    other := agent_reset(4, 1, .Search, 42)
    different :=  false
    config := observe_defaults()
    for tick in u32(0)..<1500 {
        ctx := search_test_context(tick)
        ctx.can_act = tick >= 90
        trace: Trace_Buffer
        agent_decide(&a, ctx, config)
        agent_decide(&b, ctx, config, &trace)
        testing.expect(t, a == b && trace.truncated == 0)
        if tick < 90 { testing.expect(t, a.intent.kind == .Hold && a.search.visit_count == 0 && !a.search.started) }
        own := ctx
        own.entity_id, own.senses.vision.observer = 4, 4
        agent_decide(&other, own, config)
        if tick >= 90 && a.intent != other.intent { different = true }
    }
    testing.expect(t, different && a.search.random_state != other.search.random_state)
}

@(test)
repeated_weak_cues_cannot_trap_search_forever_but_focus_still_interrupts :: proc(t: ^testing.T) {
    a := agent_reset(3, 1, .Search)
    config := observe_defaults()
    for tick in u32(100)..=600 {
        ctx := search_test_context(tick)
        ctx.senses.vision.cue_count = 1
        ctx.senses.vision.cues[0] = {tick + 1, 1, .Near}
        agent_decide(&a, ctx, config)
    }
    testing.expect(t, a.search.state == .Extensive_Search && a.search.cue_cooldown && a.search.acquisition_count == 0)
    ctx := search_test_context(601)
    ctx.senses.vision.focused_count = 1
    ctx.senses.vision.focused[0] = {602, 8, .Creature, 5, {160, 100}, .West, .Idle}
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.state == .Pursue && a.search.acquisition_count == 1 && !a.search.cue_cooldown)
}
