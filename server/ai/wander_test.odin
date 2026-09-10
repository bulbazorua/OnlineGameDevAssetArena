package ai

import "core:testing"

@(test)
wandering_is_seeded_private_and_bounded :: proc(t: ^testing.T) {
    cfg := wander_defaults()
    a := agent_reset(3, 1, 42)
    b := a
    other := agent_reset(4, 1, 42)
    testing.expect(t, a.random != other.random)
    ctx := Decision_Context{entity_id = 3, round_id = 1, can_move = true}
    idle, walked := false, false
    for tick in u32(0)..<2400 {
        ctx.tick = tick
        request := agent_decide(&a, ctx, cfg)
        testing.expect(t, request == agent_decide(&b, ctx, cfg) && a == b)
        result := Action_Result{kind = .Held}
        if request.kind == .Move {
            length := request.direction.x * request.direction.x + request.direction.y * request.direction.y
            testing.expect(t, length > 0.999 && length < 1.001)
            ctx.position += request.direction * (cfg.speed / 60)
            result = {kind = .Moved, displacement = request.direction * (cfg.speed / 60)}
            // Simulate the executor's boundary response, not a global map query.
            offset := ctx.position + request.direction * (cfg.speed / 60)
            if offset.x * offset.x + offset.y * offset.y > cfg.roam_radius * cfg.roam_radius { result.kind = .Anchor_Limit }
            walked = true
        } else { idle = true }
        agent_record_result(&a, result, tick, cfg)
        agent_record_result(&b, result, tick, cfg)
    }
    testing.expect(t, idle && walked && a == b)
    testing.expect(t, other == agent_reset(4, 1, 42), "another instance was mutated")
}

@(test)
locks_and_blocked_actions_do_not_spin_or_keep_moving :: proc(t: ^testing.T) {
    cfg := wander_defaults()
    a := agent_reset(1, 2, 0)
    initial := a.random
    ctx := Decision_Context{entity_id = 1, round_id = 2}
    for _ in 0..<90 {
        testing.expect(t, agent_decide(&a, ctx, cfg).kind == .Hold)
        testing.expect(t, a.random == initial && !a.wander.started)
        ctx.tick += 1
    }
    ctx.can_move = true
    attempts := 0
    last_attempt: u32
    for _ in 0..<3600 {
        intent := agent_decide(&a, ctx, cfg)
        if intent.kind == .Move {
            if attempts > 0 { testing.expect(t, ctx.tick - last_attempt >= cfg.idle_min_ticks) }
            attempts += 1
            last_attempt = ctx.tick
            agent_record_result(&a, {kind = .Terrain_Blocked}, ctx.tick, cfg)
            testing.expect(t, a.intent.kind == .Hold && a.last.requested.kind == .Move && a.last.result.kind == .Terrain_Blocked)
        }
        ctx.tick += 1
    }
    testing.expect(t, attempts > 10 && attempts < 80)
    ctx.can_move = false
    testing.expect(t, agent_decide(&a, ctx, cfg).kind == .Hold && !a.wander.started)
}

@(test)
deadlines_survive_tick_wrap_and_config_is_validated :: proc(t: ^testing.T) {
    cfg := wander_defaults()
    testing.expect(t, wander_config_valid(cfg))
    invalid := cfg
    invalid.idle_min_ticks = 0
    testing.expect(t, !wander_config_valid(invalid))
    invalid = cfg; invalid.speed = 9999
    testing.expect(t, !wander_config_valid(invalid))
    invalid = cfg; invalid.decision_interval = 0
    testing.expect(t, !wander_config_valid(invalid))
    a := agent_reset(1, 1, 42)
    ctx := Decision_Context{entity_id = 1, round_id = 1, tick = 0xfffffff0, can_move = true}
    walked := false
    for _ in 0..<300 {
        intent := agent_decide(&a, ctx, cfg)
        if intent.kind == .Move { walked = true }
        ctx.tick += 1
    }
    testing.expect(t, walked && ctx.tick < 300)
}
