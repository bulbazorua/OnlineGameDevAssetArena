package ai

import obs "../observations"
import "core:testing"

@(private = "file")
sampled :: proc(id, tick: u32, facing: obs.Facing = .East) -> obs.Sense_Input {
    input := obs.Sense_Input{vision_is_new = true}
    input.vision = {sample_id = id, observer = 3, round_id = 1, sample_tick = tick, delivered_tick = tick, status = .Sampled, pose = {{100, 100}, facing}}
    return input
}

@(private = "file")
with_focus :: proc(input: ^obs.Sense_Input, subject: u32, position: Vector, kind: obs.Subject_Kind = .Creature) {
    v := &input.vision
    v.focused[v.focused_count] = {observation_id = v.sample_id * 8 + u32(v.focused_count) + 1, subject = obs.Subject_Handle(subject), kind = kind, appearance_id = 6, position = position, facing = .West, locomotion = .Idle}
    v.focused_count += 1
}

@(private = "file")
with_cue :: proc(input: ^obs.Sense_Input, sector: u8, band: obs.Range_Band) {
    v := &input.vision
    v.cues[v.cue_count] = {observation_id = v.sample_id * 8 + u32(v.focused_count + v.cue_count) + 1, sector = sector, band = band}
    v.cue_count += 1
}

@(test)
memory_ingests_each_sample_once_and_keeps_original_times :: proc(t: ^testing.T) {
    config := Memory_Config{180, 30}
    memory: Visual_Memory
    first := sampled(1, 100)
    with_focus(&first, 7, {160, 100})
    with_cue(&first, 1, .Near)
    change := memory_ingest(&memory, first, config)
    testing.expect(t, change.ingested && change.focused_added == 1 && change.cues_added == 1 && memory.focused_count == 1 && memory.cue_count == 1)
    testing.expect(t, memory.focused[0].observed_tick == 100 && memory.focused[0].expires_tick == 280 && memory.cues[0].expires_tick == 130)
    testing.expect(t, memory.focused[0].position == Vector{160, 100} && memory.focused[0].observation_id == 9 && memory.cues[0].reference_facing == .East)
    snapshot := memory
    // Re-reading the same sample, or a stale copy flagged new, is not a new experience.
    stale := first
    stale.vision_is_new = false
    testing.expect(t, !memory_ingest(&memory, stale, config).ingested && memory == snapshot)
    testing.expect(t, !memory_ingest(&memory, first, config).ingested && memory == snapshot, "duplicate sample id was ingested again")
    waiting := sampled(2, 110)
    waiting.vision.status = .Waiting_For_Summon
    testing.expect(t, !memory_ingest(&memory, waiting, config).ingested && memory == snapshot)
    // A new sample that no longer shows the subject leaves its last-known data fixed.
    empty := sampled(2, 106)
    testing.expect(t, memory_ingest(&memory, empty, config).ingested && memory.focused[0] == snapshot.focused[0] && memory.ingested_samples == 2)
    // An unrelated cue never refreshes a focused memory.
    cue_only := sampled(3, 112)
    with_cue(&cue_only, 3, .Far)
    memory_ingest(&memory, cue_only, config)
    testing.expect(t, memory.focused[0] == snapshot.focused[0] && memory.cue_count == 2)
    // The same absolute bearing refreshes the existing cue instead of duplicating it.
    turned := sampled(4, 118, .South_East)
    with_cue(&turned, 0, .Near) // South_East absolute, same as East + sector 1.
    change = memory_ingest(&memory, turned, config)
    testing.expect(t, change.cues_updated == 1 && change.cues_added == 0 && memory.cue_count == 2 && memory.cues[0].observed_tick == 118 && memory.cues[0].reference_facing == .South_East)
    // Legitimate reacquisition updates the last-known position.
    again := sampled(5, 130)
    with_focus(&again, 7, {200, 140})
    change = memory_ingest(&memory, again, config)
    testing.expect(t, change.focused_updated == 1 && memory.focused_count == 1 && memory.focused[0].position == Vector{200, 140} && memory.focused[0].expires_tick == 310)
}

@(test)
memory_expires_evicts_oldest_and_survives_tick_wrap :: proc(t: ^testing.T) {
    config := Memory_Config{180, 30}
    memory: Visual_Memory
    input := sampled(1, 100)
    with_focus(&input, 7, {1, 1})
    with_cue(&input, 2, .Far)
    memory_ingest(&memory, input, config)
    testing.expect(t, memory_expire(&memory, 129) == 0 && memory_expire(&memory, 130) == 1 && memory.cue_count == 0 && memory.focused_count == 1)
    testing.expect(t, memory_expire(&memory, 279) == 0 && memory_expire(&memory, 280) == 1 && memory.focused_count == 0 && memory.focused[0] == Focused_Memory{})
    // Wrap: evidence sampled just before the tick counter wraps expires normally afterward.
    wrapped := sampled(2, 0xffffffff - 10)
    with_focus(&wrapped, 8, {2, 2})
    memory_ingest(&memory, wrapped, config)
    testing.expect(t, memory_age(memory.focused[0].observed_tick, 5) == 16 && memory_expire(&memory, 168) == 0 && memory_expire(&memory, 169) == 1)
    // Capacity: the oldest original evidence leaves first, ties keep the lower index.
    memory = {}
    for subject in u32(1)..=3 {
        s := sampled(subject + 10, 200 + subject)
        with_focus(&s, subject, {f32(subject), 0})
        memory_ingest(&memory, s, config)
    }
    fourth := sampled(20, 210)
    with_focus(&fourth, 4, {4, 0})
    change := memory_ingest(&memory, fourth, config)
    testing.expect(t, change.evicted == 1 && memory.focused_count == 3 && memory_find_focused(&memory, 1) < 0 && memory_find_focused(&memory, 4) == 2)
    testing.expect(t, memory_newest_focused(&memory, 210) == 2 && memory_oldest_focused(&memory, 210) == 0)
    testing.expect(t, memory_config_valid(config) && !memory_config_valid({0, 30}) && !memory_config_valid({180, 3601}))
}
