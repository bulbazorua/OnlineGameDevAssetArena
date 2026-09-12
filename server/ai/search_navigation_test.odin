package ai

import "core:testing"

@(test)
expired_search_legs_use_the_executed_heading_without_replacing_goals :: proc(t: ^testing.T) {
    agent := agent_reset(3, 1, .Search, 42)
    original := agent.search
    original.started, original.leg_active, original.heading = true, true, .North
    ctx := Decision_Context{entity_id = 3, round_id = 1, tick = 100, position = {200, 200}, facing = .East, motion = {64, 12, 1.0 / 60.0}}
    expected := original
    expected.heading = ctx.facing
    legacy := ctx
    legacy.motion = {}
    search_choose_heading(&expected, legacy, nil, 0)
    actual := original
    search_choose_heading(&actual, ctx, nil, 0)
    testing.expect(t, actual == expected, "the next leg persisted in the unexecuted heading")
    for state in ([3]Search_State{.Extensive_Search, .Pursue, .Investigate}) {
        actual, expected = original, original
        actual.state, expected.state = state, state
        actual.leg_active, expected.leg_active = false, false
        search_choose_heading(&actual, ctx, nil, 0)
        search_choose_heading(&expected, legacy, nil, 0)
        testing.expect(t, actual == expected, "a new or evidence-driven leg was overwritten")
    }
}
