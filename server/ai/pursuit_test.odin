package ai

import obs "../observations"
import "core:math"
import "core:testing"

@(private = "file")
pursuit_test_context :: proc(tick: u32, target: Vector = {244, 132}) -> Decision_Context {
    ctx := search_test_context(tick)
    ctx.motion = {64, 8, 1.0 / 60.0}
    ctx.senses.vision.focused_count = 1
    ctx.senses.vision.focused[0] = {tick + 1, 8, .Creature, 5, target, .West, .Walk}
    ctx.senses.vision.terrain = {valid = true, origin = {0, 0}, tile_size = 32}
    for &cell in ctx.senses.vision.terrain.cells { cell = obs.terrain_cell(.Clear) }
    return ctx
}

@(private = "file")
pursuit_expect_goal :: proc(t: ^testing.T, agent: Agent, position: Vector) {
    delta := agent.search.target_position - position
    direction := delta / math.sqrt(search_alignment(delta, delta))
    testing.expect(t, agent.navigation.preferred.kind == .Move && agent.navigation.preferred.approach.active)
    testing.expectf(t, search_alignment(agent.navigation.preferred.direction, direction) > 0.9999,
        "pursuit wandered away from its own sighting: preferred %v, target direction %v", agent.navigation.preferred.direction, direction)
}

@(test)
pursuit_ignores_wandering_noise_visits_and_old_heading_blocks :: proc(t: ^testing.T) {
    for seed in u32(1)..=16 {
        agent := agent_reset(3, 1, .Search, seed)
        agent.search.started, agent.search.heading = true, .West
        ctx := pursuit_test_context(100)
        agent.search.blocked_origin = ctx.position
        for index in 1..=3 {
            agent.search.blocked[index], agent.search.blocked_until[index] = true, 400
            search_remember_visit(&agent.search, ctx.position + obs.facing_direction(Facing(index)) * 64, 99)
        }
        random := agent.search.random_state
        agent_decide(&agent, ctx, observe_defaults())
        testing.expect(t, agent.search.state == .Pursue && agent.search.target == 8)
        testing.expect(t, agent.search.random_state == random, "pursuit consumed wandering randomness")
        pursuit_expect_goal(t, agent, ctx.position)
    }
}

@(test)
pursuit_follows_updated_sightings_with_continuous_goal_directions :: proc(t: ^testing.T) {
    agent := agent_reset(3, 1, .Search, 42)
    ctx := pursuit_test_context(100)
    for tick in u32(100)..<160 {
        ctx.tick = tick
        ctx.senses.vision_is_new = (tick - 100) % 6 == 0
        if ctx.senses.vision_is_new {
            ctx.senses.vision.sample_id, ctx.senses.vision.sample_tick = tick + 1, tick
            ctx.senses.vision.pose = {ctx.position, ctx.facing}
            ctx.senses.vision.focused[0].position = {244 + f32(tick - 100) * 0.25, 132 + f32(tick - 100) * 0.1}
        }
        command := agent_decide(&agent, ctx, observe_defaults())
        pursuit_expect_goal(t, agent, ctx.position)
        testing.expect(t, agent.search.state == .Pursue && agent.search.acquisition_count == 1)
        testing.expect(t, agent.search.target_tick == ctx.senses.vision.sample_tick)
        result := Action_Result{kind = .Held, facing = ctx.facing}
        if command.kind == .Move {
            result.kind, result.displacement = .Moved, command.direction * (64.0 / 60.0)
            ctx.position += result.displacement
        } else if command.kind == .Face {
            ctx.facing = obs.facing_rotate(ctx.facing, clamp(obs.facing_step(ctx.facing, command.facing), -1, 1))
            result.kind, result.facing = .Turned, ctx.facing
        }
        agent_record_result(&agent, result, tick, observe_defaults())
    }
}

@(test)
pursuit_keeps_its_target_through_distraction_without_refreshing_old_evidence :: proc(t: ^testing.T) {
    agent := agent_reset(3, 1, .Search, 42)
    other := agent_reset(4, 1, .Search, 42)
    config := observe_defaults()
    first := pursuit_test_context(100)
    agent_decide(&agent, first, config)
    for tick in u32(106)..<280 {
        ctx := pursuit_test_context(tick, {100, 20})
        ctx.senses.vision.focused[0].subject = 9
        agent_decide(&agent, ctx, config)
        testing.expect(t, agent.search.target == 8 && agent.search.state == .Last_Known_Position)
        testing.expect(t, !agent.search.target_visible && agent.search.evidence == .Focused_Memory)
        testing.expect(t, agent.search.target_tick == 100 && agent.search.target_position == first.senses.vision.focused[0].position)
        pursuit_expect_goal(t, agent, ctx.position)
        own := ctx
        own.entity_id, own.senses.vision.observer = 4, 4
        own.senses.vision.focused_count = 0
        agent_decide(&other, own, config)
        testing.expect(t, other.search.target == 0 && other.memory.focused_count == 0)
    }
    expired := search_test_context(280)
    agent_decide(&agent, expired, config)
    testing.expect(t, agent.search.target == 0 && agent.memory.focused_count == 0)
    testing.expect(t, agent.search.evidence_tick == 100 && agent.search.state == .Intensive_Search)
}

@(test)
pursuit_reacquisition_is_the_same_episode_until_the_sighting_expires :: proc(t: ^testing.T) {
    agent := agent_reset(3, 1, .Search, 42)
    config := observe_defaults()
    agent_decide(&agent, pursuit_test_context(100), config)
    agent_decide(&agent, search_test_context(106), config)
    agent_decide(&agent, pursuit_test_context(142, {244, 140}), config)
    testing.expect(t, agent.search.acquisition_count == 1 && agent.search.acquired_tick == 100)
    testing.expect(t, agent.search.target_visible && agent.search.target_tick == 142)
    agent_decide(&agent, pursuit_test_context(322, {244, 140}), config)
    testing.expect(t, agent.search.acquisition_count == 2 && agent.search.acquired_tick == 322)
}

@(test)
pursuit_replaces_a_wandering_bout_but_preserves_its_own_safe_detour :: proc(t: ^testing.T) {
    agent := agent_reset(3, 1, .Search, 42)
    agent.navigation.preferred = {kind = .Move, direction = {1, 0}}
    agent.navigation.committed, agent.navigation.passing_side = true, .Right
    agent.navigation.heading, agent.navigation.preferred_facing = .South_East, .East
    agent.navigation.commitment_until = 200
    ctx := pursuit_test_context(100, {244, 100})
    agent_decide(&agent, ctx, observe_defaults())
    testing.expect(t, agent.navigation.heading == .East && !agent.navigation.committed,
        "a wandering turn kept control after target acquisition")
    ctx.senses.vision.terrain.cells[3 * 13 + 4] = obs.terrain_cell(.Solid)
    side := Pass_Side.None
    for tick in u32(106)..=130 {
        ctx.tick, ctx.senses.vision.sample_id, ctx.senses.vision.sample_tick = tick, tick + 1, tick
        agent_decide(&agent, ctx, observe_defaults())
        testing.expect(t, agent.navigation.choices[int(Facing.East)].rejection == .Solid,
            "target attraction overrode a known solid obstacle")
        if side == .None { side = agent.navigation.passing_side }
        testing.expect(t, side != .None && agent.navigation.passing_side == side, "pursuit kept restarting its passing maneuver")
        testing.expect(t, agent.search.target == 8 && agent.search.acquisition_count == 1)
        pursuit_expect_goal(t, agent, ctx.position)
    }
}

@(test)
pursuit_trace_collection_does_not_change_the_private_decision :: proc(t: ^testing.T) {
    plain := agent_reset(3, 1, .Search, 42)
    traced := plain
    for tick in u32(100)..<200 {
        ctx := pursuit_test_context(tick)
        trace: Trace_Buffer
        agent_decide(&plain, ctx, observe_defaults())
        agent_decide(&traced, ctx, observe_defaults(), &trace)
        testing.expect(t, plain == traced && trace.truncated == 0)
    }
}
