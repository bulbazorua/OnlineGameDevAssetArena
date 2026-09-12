package diagnostics

import ai "../ai"
import obs "../observations"
import "../perception"

// One creature's decision as the host saw it: the copied request and answer, the
// confirmed result and the host-only audits. Queued by value; the writer adds the fan.
@(private)
Record :: struct {
    sequence: u64,
    owner_id: int,
    definition_id, map_id: u16,
    facing: u8,
    input: ai.Decision_Context,
    config: ai.Observe_Config,
    before, after: ai.Agent,
    decision_reason: ai.Decision_Reason,
    result: ai.Action_Result,
    position_after: [2]f32,
    facing_after: u8,
    audit: perception.Vision_Audit, // Host-only developer evidence; never a brain input.
    scent_audit: perception.Olfaction_Audit,
    worker_id: int,
    queued_us, started_us, finished_us: i64,
    trace: ai.Trace_Buffer,
    // Writer-filled display geometry, cached per sample. Never touched on the
    // simulation or creature threads.
    fan: [perception.FAN_RAYS]obs.Vector,
    fan_count: int,
}
Vision_Audit_View :: struct {
    sample_id: u32,
    origin_opaque: bool,
    candidates: []perception.Candidate_Audit,
    sight_tests, merged_cues: int,
}
// Portable view: slices refer only to writer-owned storage during serialization.
Record_View :: struct {
    schema_version: int,
    run_id, fingerprint: string,
    sequence: u64,
    owner_id: int,
    definition_id, map_id: u16,
    facing: u8,
    input: ai.Decision_Context,
    config: ai.Observe_Config,
    before, after: ai.Agent,
    decision_reason: ai.Decision_Reason,
    result: ai.Action_Result,
    position_after: [2]f32,
    facing_after: u8,
    worker_id: int,
    queued_us, started_us, finished_us: i64,
    nodes: []ai.Trace_Node,
    truncated_nodes: int,
    host_audit: Vision_Audit_View,
    host_scent_audit: perception.Olfaction_Audit,
    sight_fan: []obs.Vector,
}
@(private)
Grid_Copy :: struct { map_id: u16, grid: perception.Opacity_Grid }
@(private)
Fan_Cache :: struct {
    valid: bool,
    round_id, observer, sample_id: u32,
    count: int,
    points: [perception.FAN_RAYS]obs.Vector,
}
// When one receptor's sample first reached a brain. Each sense keeps its own
// clock, so a fresh smell never makes an older eye sample look newly delivered.
@(private)
Sense_Delivery :: struct {
    valid: bool,
    round_id, observer, sample_id: u32,
    delivered_us: i64,
}
@(private)
Delivery_Clocks :: struct { vision, olfaction: Sense_Delivery }

// Writer-side display fan for the consumed sample, cached by round/observer/sample
// so retained samples do not repeat the ray queries on every decision.
@(private)
attach_fan :: proc(debug: ^Diagnostics, record: ^Record) {
    record.fan_count = 0
    sample := record.input.senses.vision
    if sample.status != .Sampled { return }
    cache := &debug.fans[record.owner_id - 1]
    if cache.valid && cache.round_id == sample.round_id && cache.observer == sample.observer && cache.sample_id == sample.sample_id {
        record.fan, record.fan_count = cache.points, cache.count
        return
    }
    for entry in debug.grids {
        if entry.map_id != record.map_id { continue }
        record.fan_count = perception.vision_fan(entry.grid, sample.pose, sample.profile, &record.fan)
        break
    }
    cache^ = {valid = true, round_id = sample.round_id, observer = sample.observer, sample_id = sample.sample_id,
        count = record.fan_count, points = record.fan}
}

// Remember the first delivery of a new sample. A repeated decision with the same
// sample keeps the original time; a sample whose first record was lost is unknown.
@(private = "file")
delivery_note :: proc(clock: ^Sense_Delivery, round_id, observer, sample_id: u32, is_new: bool, queued_us: i64) {
    if clock.valid && clock.round_id == round_id && clock.observer == observer && clock.sample_id == sample_id { return }
    clock^ = {valid = true, round_id = round_id, observer = observer, sample_id = sample_id, delivered_us = queued_us if is_new else -1}
}

@(private)
note_delivery :: proc(debug: ^Diagnostics, record: ^Record) {
    clocks := &debug.delivery[record.owner_id - 1]
    eye := record.input.senses.vision
    if eye.status == .Sampled { delivery_note(&clocks.vision, eye.round_id, eye.observer, eye.sample_id, record.input.senses.vision_is_new, record.queued_us) }
    nose := record.input.senses.olfaction
    if nose.status == .Sampled { delivery_note(&clocks.olfaction, nose.round_id, nose.observer, nose.sample_id, record.input.senses.olfaction_is_new, record.queued_us) }
}

@(private)
record_view :: proc(debug: ^Diagnostics, record: ^Record) -> Record_View {
    r := record
    audit := Vision_Audit_View{r.audit.sample_id, r.audit.origin_opaque, r.audit.candidates[:r.audit.candidate_count], r.audit.sight_tests, r.audit.merged_cues}
    return {TRACE_SCHEMA, debug.run_id, debug.fingerprint, r.sequence, r.owner_id, r.definition_id, r.map_id,
        r.facing, r.input, r.config, r.before, r.after, r.decision_reason, r.result, r.position_after, r.facing_after, r.worker_id,
        r.queued_us, r.started_us, r.finished_us, r.trace.nodes[:r.trace.count], r.trace.truncated, audit, r.scent_audit, r.fan[:r.fan_count]}
}
