package ai

import obs "../observations"
import "core:testing"

@(private = "file")
context_at :: proc(tick: u32, facing: obs.Facing, input: obs.Sense_Input, can_act := true, turn_ready := true) -> Decision_Context {
    return {entity_id = 3, round_id = 1, tick = tick, position = {100, 100}, facing = facing, can_act = can_act, turn_ready = turn_ready, senses = input}
}

@(private = "file")
sample :: proc(id, tick: u32, facing: obs.Facing, is_new := true) -> obs.Sense_Input {
    input := obs.Sense_Input{vision_is_new = is_new}
    input.vision = {sample_id = id, observer = 3, round_id = 1, sample_tick = tick, delivered_tick = tick, status = .Sampled, pose = {{100, 100}, facing}}
    return input
}

@(private = "file")
add_focus :: proc(input: ^obs.Sense_Input, subject: u32, position: Vector, kind: obs.Subject_Kind = .Creature) {
    v := &input.vision
    v.focused[v.focused_count] = {observation_id = v.sample_id * 8 + u32(v.focused_count) + 1, subject = obs.Subject_Handle(subject), kind = kind, appearance_id = 6, position = position}
    v.focused_count += 1
}

@(private = "file")
add_cue :: proc(input: ^obs.Sense_Input, sector: u8, band: obs.Range_Band) {
    v := &input.vision
    v.cues[v.cue_count] = {observation_id = v.sample_id * 8 + u32(v.focused_count + v.cue_count) + 1, sector = sector, band = band}
    v.cue_count += 1
}

@(test)
cue_orients_focus_observes_memory_reacquires_then_scan_resumes :: proc(t: ^testing.T) {
    config := observe_defaults()
    agent := agent_reset(3, 1)
    facing := obs.Facing.East
    // 1. A coarse cue at the right edge: turn one step toward its sector.
    cue := sample(1, 100, facing)
    add_cue(&cue, 1, .Far)
    intent := agent_decide(&agent, context_at(100, facing, cue), config)
    testing.expect(t, intent.kind == .Face && intent.facing == .South_East && agent.last.reason == .Orient && agent.attention.evidence == .Cue)
    testing.expect(t, agent.memory.cue_count == 1 && agent.memory.ingested_samples == 1)
    // Retained sample between eye samples: same request, nothing re-ingested.
    retained := cue
    retained.vision_is_new = false
    for tick in u32(101)..<106 {
        intent = agent_decide(&agent, context_at(tick, facing, retained), config)
        testing.expect(t, intent.kind == .Face && intent.facing == .South_East && agent.memory.ingested_samples == 1)
    }
    agent_record_result(&agent, {kind = .Turned, facing = .South_East}, 101, config)
    facing = .South_East
    // 2. The next sample brings the subject into focus: observe it.
    focus := sample(2, 106, facing)
    add_focus(&focus, 9, {150, 150})
    intent = agent_decide(&agent, context_at(106, facing, focus), config)
    testing.expect(t, intent.kind == .Hold && agent.last.reason == .Observe && agent.attention.subject == 9 && agent.attention.evidence == .Focused)
    testing.expect(t, agent.memory.focused_count == 1 && agent.memory.focused[0].position == Vector{150, 150} && agent.memory.focused[0].observed_tick == 106)
    // A focused sighting elsewhere requires a turn: Orient toward the observed position.
    moved := sample(3, 112, facing)
    add_focus(&moved, 9, {100, 40})
    intent = agent_decide(&agent, context_at(112, facing, moved), config)
    testing.expect(t, intent.kind == .Face && intent.facing == .North && agent.last.reason == .Orient && agent.memory.focused[0].position == Vector{100, 40})
    // 3. The subject vanishes: reacquire from memory at the fixed last-known position.
    lost := sample(4, 118, facing)
    intent = agent_decide(&agent, context_at(118, facing, lost), config)
    testing.expect(t, intent.kind == .Face && intent.facing == .North && agent.last.reason == .Reacquire && agent.attention.evidence == .Focused_Memory)
    testing.expect(t, agent.memory.focused[0].position == Vector{100, 40} && agent.memory.focused[0].observed_tick == 112)
    facing = .North
    stale := lost
    stale.vision_is_new = false
    for tick in u32(119)..<292 {
        intent = agent_decide(&agent, context_at(tick, facing, stale), config)
        testing.expect(t, intent.kind == .Hold && agent.last.reason == .Reacquire, "memory should hold until 112 + 180")
        testing.expect(t, agent.memory.focused[0].position == Vector{100, 40}, "remembered position drifted")
    }
    // 4. Expiry at tick 292: scanning resumes with an armed deadline, then rotates clockwise.
    intent = agent_decide(&agent, context_at(292, facing, stale), config)
    testing.expect(t, intent.kind == .Hold && agent.last.reason == .Scan && agent.memory.focused_count == 0 && agent.attention.scan_deadline == 322)
    for tick in u32(293)..<322 { testing.expect(t, agent_decide(&agent, context_at(tick, facing, stale), config).kind == .Hold) }
    intent = agent_decide(&agent, context_at(322, facing, stale), config)
    testing.expect(t, intent.kind == .Face && intent.facing == .North_East && agent.attention.scan_deadline == 352)
    facing = .North_East
    for tick in u32(323)..<352 { testing.expect(t, agent_decide(&agent, context_at(tick, facing, stale), config).kind == .Hold) }
    intent = agent_decide(&agent, context_at(352, facing, stale), config)
    testing.expect(t, intent.kind == .Face && intent.facing == .East)
}

@(test)
selection_rules_are_fixed_and_evidence_only :: proc(t: ^testing.T) {
    config := observe_defaults()
    // Nearer band wins, then the smaller turn, then clockwise.
    agent := agent_reset(3, 1)
    input := sample(1, 10, .North)
    add_cue(&input, 2, .Far)   // east, far
    add_cue(&input, 7, .Near)  // north-west, near: 1 step counter-clockwise
    add_cue(&input, 1, .Near)  // north-east, near: 1 step clockwise
    intent := agent_decide(&agent, context_at(10, .North, input), config)
    testing.expect(t, intent.kind == .Face && intent.facing == .North_East)
    // Cues are interpreted in their sampled frame even after the body turned.
    agent = agent_reset(3, 1)
    turned := sample(2, 12, .East)
    add_cue(&turned, 1, .Near) // south-east absolute
    intent = agent_decide(&agent, context_at(12, .South, turned), config)
    testing.expect(t, intent.kind == .Face && intent.facing == .South_East && obs.facing_step(.South, .South_East) == -1)
    // Focused: a visibly identified creature beats a nearer trainer; nearest among equals; stable ties.
    agent = agent_reset(3, 1)
    focus := sample(3, 20, .East)
    add_focus(&focus, 20, {110, 100}, .Trainer)
    add_focus(&focus, 21, {100, 220}, .Creature)
    add_focus(&focus, 22, {100, 200}, .Creature)
    intent = agent_decide(&agent, context_at(20, .East, focus), config)
    testing.expect(t, intent.kind == .Face && intent.facing == .South && agent.attention.subject == 22)
    // Once attended, the same subject is kept while it stays focused.
    next := sample(4, 26, .South)
    add_focus(&next, 21, {100, 102}, .Creature)
    add_focus(&next, 22, {100, 260}, .Creature)
    intent = agent_decide(&agent, context_at(26, .South, next), config)
    testing.expect(t, intent.kind == .Hold && agent.attention.subject == 22 && agent.last.reason == .Observe)
    // Equal-appearance ties use the lower handle.
    agent = agent_reset(3, 1)
    tie := sample(5, 30, .East)
    add_focus(&tie, 31, {100, 140})
    add_focus(&tie, 30, {60, 100})
    agent_decide(&agent, context_at(30, .East, tie), config)
    testing.expect(t, agent.attention.subject == 30)
    // Memory reacquisition prefers the attended subject, then the newest memory, then a cue memory.
    agent = agent_reset(3, 1)
    seen := sample(6, 40, .East)
    add_focus(&seen, 40, {100, 20})
    add_focus(&seen, 41, {170, 100})
    agent_decide(&agent, context_at(40, .East, seen), config)
    testing.expect(t, agent.attention.subject == 41 && agent.last.reason == .Observe)
    silent := sample(7, 46, .East)
    intent = agent_decide(&agent, context_at(46, .East, silent), config)
    testing.expect(t, agent.last.reason == .Reacquire && agent.attention.evidence == .Focused_Memory && agent.attention.subject == 41 && intent.kind == .Hold)
    // Without an attended subject the newest original evidence is used.
    later := sample(8, 52, .East)
    add_focus(&later, 40, {100, 20})
    agent_decide(&agent, context_at(52, .East, later), config)
    agent.attention = {}
    intent = agent_decide(&agent, context_at(58, .East, sample(9, 58, .East)), config)
    testing.expect(t, agent.last.reason == .Reacquire && agent.attention.subject == 40 && intent.kind == .Face && intent.facing == .North)
    // A remembered cue keeps its sampled frame: East plus six sectors clockwise is North.
    agent.memory = {}
    agent.attention = {}
    cue_memory := sample(10, 64, .East)
    add_cue(&cue_memory, 6, .Far)
    intent = agent_decide(&agent, context_at(64, .East, cue_memory), config)
    testing.expect(t, agent.last.reason == .Orient && intent.kind == .Face && intent.facing == .North)
    intent = agent_decide(&agent, context_at(70, .North, sample(11, 70, .North)), config)
    testing.expect(t, agent.last.reason == .Reacquire && agent.attention.evidence == .Cue_Memory && intent.kind == .Hold, "remembered north cue while facing north holds")
    intent = agent_decide(&agent, context_at(76, .South, sample(12, 76, .South)), config)
    testing.expect(t, agent.last.reason == .Reacquire && intent.kind == .Face && intent.facing == .North)
    intent = agent_decide(&agent, context_at(94, .South, sample(13, 94, .South)), config)
    testing.expect(t, agent.last.reason == .Scan && intent.kind == .Hold, "cue memory expired after 30 ticks")
    testing.expect(t, observe_config_valid(config) && !observe_config_valid({{180, 30}, 0, 1}) && !observe_config_valid({{180, 30}, 30, 8}))
}

@(test)
locks_resets_and_private_ownership_hold :: proc(t: ^testing.T) {
    config := observe_defaults()
    a := agent_reset(3, 1)
    b := agent_reset(4, 1)
    waiting := obs.Sense_Input{}
    waiting.vision.status = .Waiting_For_Summon
    for tick in u32(0)..<90 {
        intent := agent_decide(&a, context_at(tick, .East, waiting, false), config)
        testing.expect(t, intent.kind == .Hold && a.last.reason == .Locked && a.attention == Attention{} && a.memory == Visual_Memory{})
    }
    seen := sample(1, 90, .East)
    add_focus(&seen, 9, {140, 100})
    agent_decide(&a, context_at(90, .East, seen), config)
    testing.expect(t, a.last.reason == .Observe && a.memory.focused_count == 1)
    // B shares the definition and configuration but has its own memory/attention.
    other := context_at(90, .East, sample(1, 90, .East))
    other.entity_id = 4
    agent_decide(&b, other, config)
    testing.expect(t, b.memory.focused_count == 0 && b.attention.state == .Scan && a.memory.focused_count == 1)
    saved := a
    b.memory = {}
    b.attention = {}
    testing.expect(t, a == saved, "resetting one instance changed another")
    // A lock mid-round clears attention but not private memory; a reset clears everything.
    agent_decide(&a, context_at(91, .East, sample(1, 90, .East, false), false), config)
    testing.expect(t, a.last.reason == .Locked && a.attention == Attention{} && a.memory.focused_count == 1)
    agent_record_result(&a, {kind = .Locked}, 91, config)
    testing.expect(t, a.intent.kind == .Hold)
    a = agent_reset(30, 2)
    testing.expect(t, a.memory == Visual_Memory{} && a.attention == Attention{} && a.entity_id == 30 && a.round_id == 2)
    // Disabled vision is explicit: no evidence, deliberate scanning only.
    disabled := obs.Sense_Input{}
    disabled.vision.status = .Disabled
    c := agent_reset(5, 1)
    ctx := context_at(0, .North, disabled)
    ctx.entity_id = 5
    agent_decide(&c, ctx, config)
    testing.expect(t, c.last.reason == .Scan && c.memory.ingested_samples == 0)
}
