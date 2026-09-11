// Private olfactory memory: the latest reading per scent class with its original
// time, precision and expiry. It never learns whose scent it is, and it never
// turns a coarse bearing into a position.
package ai

import obs "../observations"

Scent_Memory_Entry :: struct {
    class: obs.Scent_Class,
    strength: obs.Scent_Strength,
    freshness: obs.Scent_Freshness,
    bearing_valid: bool,
    bearing: Facing,
    zones: [obs.SCENT_ZONES]obs.Scent_Strength,
    origin: Vector, // Where the nose was when it sampled: own position, not a source.
    range: f32,     // The nose's reach at that sample, so zones can be placed later.
    observed_tick, expires_tick, sample_id, observation_id: u32,
}

Scent_Memory :: struct {
    entries: [obs.MAX_SCENT_READINGS]Scent_Memory_Entry,
    count: int,
    last_sample_id, last_sample_tick, ingested_samples: u32,
    last_sample_empty: bool,
}

// A retained smell stays useful for three seconds after its sample.
SCENT_RETENTION_TICKS :: u32(180)

scent_memory_find :: proc(memory: ^Scent_Memory, class: obs.Scent_Class) -> int {
    for entry, index in memory.entries[:memory.count] { if entry.class == class { return index } }
    return -1
}

@(private)
scent_memory_remove :: proc(memory: ^Scent_Memory, index: int) {
    for i in index..<memory.count - 1 { memory.entries[i] = memory.entries[i + 1] }
    memory.count -= 1
    memory.entries[memory.count] = {}
}

// Ingest one nose sample exactly once. A fresh empty sample clears nothing by
// itself: retained entries age out on their own clock, but it is remembered as
// the latest sample so current detection reads as empty.
scent_memory_ingest :: proc(memory: ^Scent_Memory, input: obs.Sense_Input, retention: u32, trace: ^Trace_Buffer = nil, parent: int = 0) -> (ingested: bool) {
    sample := input.olfaction
    if !input.olfaction_is_new || sample.status != .Sampled || (memory.ingested_samples > 0 && sample.sample_id == memory.last_sample_id) { return false }
    memory.last_sample_id, memory.last_sample_tick = sample.sample_id, sample.sample_tick
    memory.ingested_samples += 1
    memory.last_sample_empty = sample.reading_count == 0
    for reading in sample.readings[:sample.reading_count] {
        entry := Scent_Memory_Entry{class = reading.class, strength = reading.strength, freshness = reading.freshness,
            bearing_valid = reading.bearing_valid, bearing = reading.bearing, zones = reading.zones, origin = sample.position,
            range = sample.profile.range,
            observed_tick = sample.sample_tick, expires_tick = sample.sample_tick + retention, sample_id = sample.sample_id,
            observation_id = reading.observation_id}
        index := scent_memory_find(memory, reading.class)
        if index < 0 {
            index = memory.count
            memory.count += 1
        }
        memory.entries[index] = entry
        trace_add(trace, parent, .State, .Info, "Remember scent class reading", "strength / bearing_valid", f64(reading.strength), 1 if reading.bearing_valid else 0,
            obs.facing_direction(reading.bearing) if reading.bearing_valid else {}, reading.observation_id)
    }
    return true
}

scent_memory_expire :: proc(memory: ^Scent_Memory, now: u32) -> (expired: int) {
    for index := memory.count - 1; index >= 0; index -= 1 {
        if tick_due(now, memory.entries[index].expires_tick) { scent_memory_remove(memory, index); expired += 1 }
    }
    return
}

// True when the entry came from the newest nose sample and that sample is still
// young: at most two sampling intervals old. Anything else is retained memory.
scent_memory_is_current :: proc(memory: ^Scent_Memory, entry: Scent_Memory_Entry, now, sample_interval: u32) -> bool {
    return memory.ingested_samples > 0 && entry.sample_id == memory.last_sample_id && now - entry.observed_tick <= max(1, sample_interval * 2)
}

// Note the nose sample and fold it into memory. Shared by every controller so
// olfaction follows the same once-only, original-time rules as vision.
scent_update_memory :: proc(agent: ^Agent, ctx: Decision_Context, trace: ^Trace_Buffer, parent: int) {
    sample := ctx.senses.olfaction
    switch sample.status {
    case .Sampled:
        trace_add(trace, parent, .Input, .Info, "Nose sample received", "sample_tick / readings", f64(sample.sample_tick), f64(sample.reading_count), {}, sample.sample_id)
    case .Waiting_For_Summon: trace_add(trace, parent, .Input, .Unavailable, "Nose sample: waiting for summon", "decision_tick", f64(ctx.tick))
    case .Disabled: trace_add(trace, parent, .Input, .Unavailable, "Nose sample: olfaction disabled by profile", "decision_tick", f64(ctx.tick))
    case .Unsupported: trace_add(trace, parent, .Input, .Unavailable, "Nose sample: unsupported sense", "decision_tick", f64(ctx.tick))
    }
    ingested := scent_memory_ingest(&agent.scent, ctx.senses, SCENT_RETENTION_TICKS, trace, parent)
    expired := scent_memory_expire(&agent.scent, ctx.tick)
    trace_add(trace, parent, .State, .Info, "Age private scent memory", "ingested / retained", 1 if ingested else 0, f64(agent.scent.count), {}, sample.sample_id)
}
