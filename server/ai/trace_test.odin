package ai

import obs "../observations"
import "core:testing"

@(test)
tracing_preserves_private_state_and_decisions :: proc(t: ^testing.T) {
    a := agent_reset(11, 3)
    b := a
    config := observe_defaults()
    facing := obs.Facing.East
    for tick in u32(0)..<2400 {
        input: obs.Sense_Input
        if tick < 90 { input.vision.status = .Waiting_For_Summon } else {
            input.vision = {sample_id = (tick - 90) / 6 + 1, observer = 11, round_id = 3, sample_tick = tick - (tick - 90) % 6, status = .Sampled, pose = {{300, 300}, facing}}
            input.vision.delivered_tick = input.vision.sample_tick
            input.vision_is_new = (tick - 90) % 6 == 0
            phase := ((tick - 90) / 6) % 40
            if phase < 5 { input.vision.cues[0] = {observation_id = input.vision.sample_id * 8 + 1, sector = 1, band = .Near}; input.vision.cue_count = 1 }
            else if phase < 12 {
                input.vision.focused[0] = {observation_id = input.vision.sample_id * 8 + 1, subject = 5, kind = .Trainer, appearance_id = 1, position = {300 + f32(phase) * 10, 340}}
                input.vision.focused_count = 1
            }
        }
        ctx := Decision_Context{entity_id = 11, round_id = 3, tick = tick, position = {300, 300}, facing = facing, can_act = tick >= 90, turn_ready = tick % 6 == 0, senses = input}
        trace: Trace_Buffer
        lhs := agent_decide(&a, ctx, config)
        rhs := agent_decide(&b, ctx, config, &trace)
        testing.expect(t, lhs == rhs && a == b)
        testing.expect(t, trace.count > 0 && trace.truncated == 0)
        for node, index in trace.nodes[:trace.count] {
            testing.expect(t, node.id == index + 1 && node.parent < node.id && node.thread_id > 0)
        }
        testing.expect(t, trace.nodes[trace.count - 1].stage == .Decision)
        result := Action_Result{kind = .Held, facing = facing}
        if lhs.kind == .Face {
            if tick % 6 == 0 { facing = obs.facing_rotate(facing, obs.facing_step(facing, lhs.facing) > 0 ? 1 : -1); result = {kind = .Turned, facing = facing} }
            else { result = {kind = .Turn_Pending, facing = facing} }
        }
        agent_record_result(&a, result, tick, config)
        agent_record_result(&b, result, tick, config)
        testing.expect(t, a == b)
    }
    testing.expect(t, a.memory.ingested_samples > 300)
}

@(test)
trace_references_evidence_and_reports_capacity_loss :: proc(t: ^testing.T) {
    agent := agent_reset(1, 2)
    input := obs.Sense_Input{vision_is_new = true}
    input.vision = {sample_id = 4, observer = 1, round_id = 2, sample_tick = 96, delivered_tick = 96, status = .Sampled, pose = {{64, 64}, .North}}
    input.vision.focused[0] = {observation_id = 33, subject = 8, kind = .Creature, appearance_id = 6, position = {64, 10}}
    input.vision.focused[1] = {observation_id = 34, subject = 9, kind = .Trainer, appearance_id = 1, position = {80, 30}}
    input.vision.focused_count = 2
    input.vision.cues[0] = {observation_id = 35, sector = 2, band = .Far}
    input.vision.cue_count = 1
    trace: Trace_Buffer
    intent := agent_decide(&agent, {entity_id = 1, round_id = 2, tick = 98, position = {64, 64}, facing = .North, can_act = true, turn_ready = true, senses = input}, observe_defaults(), &trace)
    testing.expect(t, intent.kind == .Hold && agent.last.reason == .Observe && agent.attention.subject == 8)
    referenced, rejected, skipped := 0, 0, 0
    for node in trace.nodes[:trace.count] {
        if node.reference == 33 && node.subject == 8 { referenced += 1 }
        if node.label == "Candidate focused subject" && node.status == .Rejected { rejected += 1 }
        if node.status == .Skipped { skipped += 1 }
    }
    testing.expect(t, referenced >= 2 && rejected == 1 && skipped == 1)
    for i in 0..<TRACE_NODE_CAPACITY + 7 { trace_add(&trace, 0, .State, .Info, "capacity test") }
    testing.expect(t, trace.count == TRACE_NODE_CAPACITY && trace.truncated > 0)
}
