// The Observe tactic: scan, orient toward evidence, observe, briefly reacquire from
// memory, then resume scanning. It requests only Hold and Face and owns attention and
// scan deadlines; the host resolver alone decides whether a turn happens.
package ai

import obs "../observations"
import "core:math"

Observe_Config :: struct {
    memory: Memory_Config,
    scan_interval_ticks: u32,
    scan_step: int, // 45° sectors per scan turn, clockwise.
}

// Gameplay defaults: 3 s focused retention, 0.5 s peripheral retention, one
// 45° scan step every 30 ticks. Tunable; not a physiological claim.
observe_defaults :: proc() -> Observe_Config { return {{180, 30}, 30, 1} }

observe_config_valid :: proc(c: Observe_Config) -> bool {
    return memory_config_valid(c.memory) && c.scan_interval_ticks >= 1 && c.scan_interval_ticks <= 3600 && c.scan_step >= 1 && c.scan_step <= 7
}

@(private)
distance_between :: proc(a, b: Vector) -> f32 {
    d := b - a
    return math.sqrt(d.x * d.x + d.y * d.y)
}

// Request a turn toward `desired`, or hold when already aligned. Returns aligned.
@(private)
observe_aim :: proc(agent: ^Agent, ctx: Decision_Context, desired: Facing, aligned_label, turn_label: string, trace: ^Trace_Buffer, parent: int) -> bool {
    agent.attention.desired_facing = desired
    if desired == ctx.facing {
        agent.intent = {}
        trace_add(trace, parent, .Branch, .Selected, aligned_label, "current_facing", f64(ctx.facing))
        return true
    }
    agent.intent = {kind = .Face, facing = desired}
    trace_add(trace, parent, .Branch, .Selected, turn_label, "desired_facing / current_facing", f64(desired), f64(ctx.facing), obs.facing_direction(desired))
    return false
}

@(private)
observe_aim_at_position :: proc(agent: ^Agent, ctx: Decision_Context, target: Vector, aligned_label, turn_label: string, trace: ^Trace_Buffer, parent: int) -> bool {
    desired, has_bearing := obs.facing_toward(ctx.position, target)
    if !has_bearing { desired = ctx.facing }
    return observe_aim(agent, ctx, desired, aligned_label, turn_label, trace, parent)
}

@(private)
observe_note_sample :: proc(vision: obs.Vision_Sample, decision_tick: u32, trace: ^Trace_Buffer, parent: int) {
    switch vision.status {
    case .Sampled:
        trace_add(trace, parent, .Input, .Info, "Eye sample received", "sample_tick / decision_tick", f64(vision.sample_tick), f64(decision_tick), {}, vision.sample_id)
    case .Waiting_For_Summon:
        trace_add(trace, parent, .Input, .Unavailable, "Eye sample: waiting for summon", "decision_tick", f64(decision_tick))
    case .Disabled:
        trace_add(trace, parent, .Input, .Unavailable, "Eye sample: vision disabled by profile", "decision_tick", f64(decision_tick))
    case .Unsupported:
        trace_add(trace, parent, .Input, .Unavailable, "Eye sample: unsupported sense", "decision_tick", f64(decision_tick))
    }
    trace_add(trace, parent, .Input, .Info, "Read own focused sightings / peripheral cues", "focused / cues", f64(vision.focused_count), f64(vision.cue_count), {}, vision.sample_id)
}

// Ingest a genuinely new sample once, then age memory relative to the decision tick.
@(private)
observe_update_memory :: proc(agent: ^Agent, ctx: Decision_Context, config: Observe_Config, trace: ^Trace_Buffer, parent: int) {
    vision := ctx.senses.vision
    fresh := ctx.senses.vision_is_new && vision.status == .Sampled && (agent.memory.ingested_samples == 0 || vision.sample_id != agent.memory.last_sample_id)
    ingest := trace_condition(trace, parent, "Ingest new sample?", fresh, "sample_id / last_ingested", f64(vision.sample_id), f64(agent.memory.last_sample_id), {}, vision.sample_id)
    if fresh {
        change := memory_ingest(&agent.memory, ctx.senses, config.memory, trace, ingest)
        trace_add(trace, ingest, .State, .Selected, "Memory updated from this sample", "added / updated", f64(change.focused_added + change.cues_added), f64(change.focused_updated + change.cues_updated), {}, vision.sample_id)
    } else {
        trace_add(trace, ingest, .State, .Selected, "Retain original evidence times; no new experience")
    }
    expired := memory_expire(&agent.memory, ctx.tick)
    trace_add(trace, parent, .State, .Info, "Age private memory", "expired / retained", f64(expired), f64(agent.memory.focused_count + agent.memory.cue_count))
}

// Priority 2: keep the attended subject while focused; otherwise prefer a visibly
// identified creature, then the nearest subject, then the lower handle.
@(private)
observe_choose_focused :: proc(agent: ^Agent, ctx: Decision_Context, vision: obs.Vision_Sample) -> (chosen: int, kept: bool) {
    chosen = -1
    sightings := vision.focused
    if agent.attention.subject != 0 {
        for sighting, index in sightings[:vision.focused_count] { if sighting.subject == agent.attention.subject { return index, true } }
    }
    for sighting, index in sightings[:vision.focused_count] {
        if chosen < 0 { chosen = index; continue }
        current := sightings[chosen]
        if sighting.kind == .Creature && current.kind != .Creature { chosen = index; continue }
        if sighting.kind != current.kind { continue }
        a, b := distance_between(ctx.position, sighting.position), distance_between(ctx.position, current.position)
        if a < b || (a == b && sighting.subject < current.subject) { chosen = index }
    }
    return chosen, false
}

@(private)
observe_attend_focused :: proc(agent: ^Agent, ctx: Decision_Context, trace: ^Trace_Buffer, parent: int) -> Decision_Reason {
    vision := ctx.senses.vision
    chosen, kept := observe_choose_focused(agent, ctx, vision)
    sightings := vision.focused
    for sighting, index in sightings[:vision.focused_count] {
        trace_add(trace, parent, .Branch, .Selected if index == chosen else .Rejected, "Candidate focused subject", "distance / kind",
            f64(distance_between(ctx.position, sighting.position)), f64(sighting.kind), sighting.position, sighting.observation_id, u32(sighting.subject))
    }
    sighting := sightings[chosen]
    label := "Select attention: keep attended subject" if kept else ("Select attention: prefer visibly identified creature" if sighting.kind == .Creature else "Select attention: nearest observed subject")
    select := trace_add(trace, parent, .Branch, .Selected, label, "observation_id", f64(sighting.observation_id), 0, {}, sighting.observation_id, u32(sighting.subject))
    agent.attention.evidence, agent.attention.subject = .Focused, sighting.subject
    agent.attention.observation_id, agent.attention.evidence_tick = sighting.observation_id, vision.sample_tick
    agent.attention.scan_armed = false
    aligned := observe_aim_at_position(agent, ctx, sighting.position, "Already aligned: hold and observe", "Face the observed position", trace, select)
    agent.attention.state = .Observe if aligned else .Orient
    return .Observe if aligned else .Orient
}

// Priority 3: nearest band first, then the smaller turn, then clockwise.
@(private)
observe_choose_cue :: proc(ctx: Decision_Context, vision: obs.Vision_Sample) -> int {
    chosen, chosen_steps := -1, 0
    cues := vision.cues
    for cue, index in cues[:vision.cue_count] {
        steps := obs.facing_step(ctx.facing, obs.cue_absolute_facing(vision.pose.facing, cue.sector))
        better := chosen < 0
        if !better {
            current := cues[chosen]
            if int(cue.band) != int(current.band) { better = int(cue.band) < int(current.band) }
            else if abs(steps) != abs(chosen_steps) { better = abs(steps) < abs(chosen_steps) }
            else if steps != chosen_steps { better = steps > chosen_steps }
        }
        if better { chosen, chosen_steps = index, steps }
    }
    return chosen
}

@(private)
observe_attend_cue :: proc(agent: ^Agent, ctx: Decision_Context, trace: ^Trace_Buffer, parent: int) -> Decision_Reason {
    vision := ctx.senses.vision
    chosen := observe_choose_cue(ctx, vision)
    cues := vision.cues
    for cue, index in cues[:vision.cue_count] {
        steps := obs.facing_step(ctx.facing, obs.cue_absolute_facing(vision.pose.facing, cue.sector))
        trace_add(trace, parent, .Branch, .Selected if index == chosen else .Rejected, "Candidate peripheral cue", "turn_steps / band", f64(steps), f64(cue.band), {}, cue.observation_id)
    }
    cue := cues[chosen]
    select := trace_add(trace, parent, .Branch, .Selected, "Select attention: nearest band, smallest turn, clockwise tie", "sector / reference_facing", f64(cue.sector), f64(vision.pose.facing), {}, cue.observation_id)
    agent.attention.evidence, agent.attention.subject = .Cue, 0
    agent.attention.observation_id, agent.attention.evidence_tick = cue.observation_id, vision.sample_tick
    agent.attention.scan_armed = false
    agent.attention.state = .Orient
    observe_aim(agent, ctx, obs.cue_absolute_facing(vision.pose.facing, cue.sector), "Aligned with the cue bearing: hold for the next sample", "Face the cue's quantized bearing", trace, select)
    return .Orient
}

// Priority 4: the attended subject's memory, else the newest sighting, else the newest cue.
@(private)
observe_reacquire :: proc(agent: ^Agent, ctx: Decision_Context, trace: ^Trace_Buffer, parent: int) -> Decision_Reason {
    memory := &agent.memory
    index := -1
    if agent.attention.subject != 0 { index = memory_find_focused(memory, agent.attention.subject) }
    if index < 0 { index = memory_newest_focused(memory, ctx.tick) }
    cue_index := -1
    if index < 0 { cue_index = memory_newest_cue(memory, ctx.tick) }
    for entry, i in memory.focused[:memory.focused_count] {
        trace_add(trace, parent, .Branch, .Selected if i == index else .Rejected, "Remembered focused subject", "age_ticks / expires_tick",
            f64(memory_age(entry.observed_tick, ctx.tick)), f64(entry.expires_tick), entry.position, entry.observation_id, u32(entry.subject))
    }
    for entry, i in memory.cues[:memory.cue_count] {
        trace_add(trace, parent, .Branch, .Selected if i == cue_index else .Rejected, "Remembered peripheral cue", "age_ticks / expires_tick",
            f64(memory_age(entry.observed_tick, ctx.tick)), f64(entry.expires_tick), {}, entry.observation_id)
    }
    agent.attention.state = .Reacquire
    agent.attention.scan_armed = false
    if index >= 0 {
        entry := memory.focused[index]
        select := trace_add(trace, parent, .Branch, .Selected, "Reacquire: aim at the last observed position", "observed_tick / age_ticks", f64(entry.observed_tick), f64(memory_age(entry.observed_tick, ctx.tick)), entry.position, entry.observation_id, u32(entry.subject))
        agent.attention.evidence, agent.attention.subject = .Focused_Memory, entry.subject
        agent.attention.observation_id, agent.attention.evidence_tick = entry.observation_id, entry.observed_tick
        observe_aim_at_position(agent, ctx, entry.position, "Reacquire: aligned with the remembered position; hold", "Reacquire: face the remembered position", trace, select)
    } else {
        entry := memory.cues[cue_index]
        select := trace_add(trace, parent, .Branch, .Selected, "Reacquire: aim at the remembered coarse bearing", "observed_tick / age_ticks", f64(entry.observed_tick), f64(memory_age(entry.observed_tick, ctx.tick)), {}, entry.observation_id)
        agent.attention.evidence, agent.attention.subject = .Cue_Memory, 0
        agent.attention.observation_id, agent.attention.evidence_tick = entry.observation_id, entry.observed_tick
        observe_aim(agent, ctx, obs.cue_absolute_facing(entry.reference_facing, entry.sector), "Reacquire: aligned with the remembered bearing; hold", "Reacquire: face the remembered bearing", trace, select)
    }
    return .Reacquire
}

// Priority 5: deliberate scan. Deadlines are set once, never refreshed per tick.
@(private)
observe_scan :: proc(agent: ^Agent, ctx: Decision_Context, config: Observe_Config, trace: ^Trace_Buffer, parent: int) -> Decision_Reason {
    attention := &agent.attention
    if attention.state != .Scan || !attention.scan_armed {
        attention^ = {state = .Scan, scan_armed = true, scan_deadline = ctx.tick + config.scan_interval_ticks, desired_facing = ctx.facing}
        agent.intent = {}
        trace_add(trace, parent, .Branch, .Selected, "No evidence: start a scan interval and hold", "tick / scan_deadline", f64(ctx.tick), f64(attention.scan_deadline))
        return .Scan
    }
    due := tick_due(ctx.tick, attention.scan_deadline)
    scan := trace_condition(trace, parent, "Scan deadline reached?", due, "tick / scan_deadline", f64(ctx.tick), f64(attention.scan_deadline))
    if !due {
        agent.intent = {}
        trace_add(trace, scan, .Branch, .Selected, "Hold until the scan deadline")
        return .Scan
    }
    attention.scan_deadline = ctx.tick + config.scan_interval_ticks
    attention.desired_facing = obs.facing_rotate(ctx.facing, config.scan_step)
    agent.intent = {kind = .Face, facing = attention.desired_facing}
    trace_add(trace, scan, .Branch, .Selected, "Rotate one step clockwise", "desired_facing / next_deadline", f64(attention.desired_facing), f64(attention.scan_deadline), obs.facing_direction(attention.desired_facing))
    return .Scan
}

observe_decide :: proc(agent: ^Agent, ctx: Decision_Context, config: Observe_Config, trace: ^Trace_Buffer = nil, parent: int = 0) -> Decision_Reason {
    vision := ctx.senses.vision
    observe_note_sample(vision, ctx.tick, trace, parent)
    observe_update_memory(agent, ctx, config, trace, parent)
    scent_update_memory(agent, ctx, trace, parent)
    unlocked := trace_condition(trace, parent, "Action unlocked?", ctx.can_act)
    if !ctx.can_act {
        agent.intent = {}
        agent.attention = {}
        trace_add(trace, unlocked, .Branch, .Selected, "Summon lock: clear attention and hold")
        trace_add(trace, parent, .Branch, .Skipped, "Attention branches skipped while locked")
        return .Locked
    }
    focused := trace_condition(trace, parent, "Focused subject available?", vision.focused_count > 0, "focused_count", f64(vision.focused_count), 0, {}, vision.sample_id)
    if vision.focused_count > 0 {
        reason := observe_attend_focused(agent, ctx, trace, focused)
        trace_add(trace, parent, .Branch, .Skipped, "Peripheral, memory and scan branches skipped: focused evidence selected", "count", 3)
        return reason
    }
    cue_branch := trace_condition(trace, parent, "Peripheral cue available?", vision.cue_count > 0, "cue_count", f64(vision.cue_count), 0, {}, vision.sample_id)
    if vision.cue_count > 0 {
        reason := observe_attend_cue(agent, ctx, trace, cue_branch)
        trace_add(trace, parent, .Branch, .Skipped, "Memory and scan branches skipped: peripheral cue selected", "count", 2)
        return reason
    }
    remembered := agent.memory.focused_count > 0 || agent.memory.cue_count > 0
    memory_branch := trace_condition(trace, parent, "Remembered evidence available?", remembered, "focused_memories / cue_memories", f64(agent.memory.focused_count), f64(agent.memory.cue_count))
    if remembered {
        reason := observe_reacquire(agent, ctx, trace, memory_branch)
        trace_add(trace, parent, .Branch, .Skipped, "Scan branch skipped: memory selected", "count", 1)
        return reason
    }
    return observe_scan(agent, ctx, config, trace, parent)
}

// Tactic-specific feedback. A lock clears attention; other results need nothing.
observe_record_result :: proc(agent: ^Agent, result: Action_Result) {
    if result.kind == .Locked { agent.intent = {}; agent.attention = {} }
}
