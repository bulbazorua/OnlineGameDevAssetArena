// Minimal private working memory: previously received visual evidence with its
// original time, precision and expiry. It never acquires a new hidden fact.
package ai

import obs "../observations"

MEMORY_CAPACITY :: 3

Focused_Memory :: struct {
    subject: obs.Subject_Handle,
    kind: obs.Subject_Kind,
    appearance_id: u16,
    position: Vector, // Last observed position; it never moves after the sighting.
    facing: Facing,
    locomotion: obs.Locomotion,
    observed_tick, expires_tick, sample_id, observation_id: u32,
}

// A remembered coarse cue keeps its sector, the facing it was relative to and
// its band. It has no coordinates and no identity to promote later.
Cue_Memory :: struct {
    sector: u8,
    band: obs.Range_Band,
    reference_facing: Facing,
    observed_tick, expires_tick, sample_id, observation_id: u32,
}

Visual_Memory :: struct {
    focused: [MEMORY_CAPACITY]Focused_Memory,
    focused_count: int,
    cues: [MEMORY_CAPACITY]Cue_Memory,
    cue_count: int,
    last_sample_id, ingested_samples: u32,
}

Memory_Config :: struct { focused_retention_ticks, peripheral_retention_ticks: u32 }

Memory_Change :: struct {
    ingested: bool,
    focused_added, focused_updated, cues_added, cues_updated, evicted: int,
}

memory_config_valid :: proc(c: Memory_Config) -> bool {
    return c.focused_retention_ticks >= 1 && c.focused_retention_ticks <= 3600 && c.peripheral_retention_ticks >= 1 && c.peripheral_retention_ticks <= 3600
}

memory_find_focused :: proc(memory: ^Visual_Memory, subject: obs.Subject_Handle) -> int {
    for entry, index in memory.focused[:memory.focused_count] { if entry.subject == subject { return index } }
    return -1
}

@(private)
memory_find_cue :: proc(memory: ^Visual_Memory, absolute: Facing, band: obs.Range_Band) -> int {
    for entry, index in memory.cues[:memory.cue_count] {
        if obs.cue_absolute_facing(entry.reference_facing, entry.sector) == absolute && entry.band == band { return index }
    }
    return -1
}

// Age relative to a decision tick, wrap-safe.
memory_age :: proc(observed_tick, now: u32) -> u32 { return now - observed_tick }

// Index of the entry with the oldest original evidence; ties keep the lowest index.
memory_oldest_focused :: proc(memory: ^Visual_Memory, now: u32) -> int {
    oldest, age := -1, u32(0)
    for entry, index in memory.focused[:memory.focused_count] {
        if oldest < 0 || memory_age(entry.observed_tick, now) > age { oldest, age = index, memory_age(entry.observed_tick, now) }
    }
    return oldest
}

memory_oldest_cue :: proc(memory: ^Visual_Memory, now: u32) -> int {
    oldest, age := -1, u32(0)
    for entry, index in memory.cues[:memory.cue_count] {
        if oldest < 0 || memory_age(entry.observed_tick, now) > age { oldest, age = index, memory_age(entry.observed_tick, now) }
    }
    return oldest
}

memory_newest_focused :: proc(memory: ^Visual_Memory, now: u32) -> int {
    newest, age := -1, u32(0)
    for entry, index in memory.focused[:memory.focused_count] {
        if newest < 0 || memory_age(entry.observed_tick, now) < age { newest, age = index, memory_age(entry.observed_tick, now) }
    }
    return newest
}

memory_newest_cue :: proc(memory: ^Visual_Memory, now: u32) -> int {
    newest, age := -1, u32(0)
    for entry, index in memory.cues[:memory.cue_count] {
        if newest < 0 || memory_age(entry.observed_tick, now) < age { newest, age = index, memory_age(entry.observed_tick, now) }
    }
    return newest
}

@(private)
memory_remove_focused :: proc(memory: ^Visual_Memory, index: int) {
    for i in index..<memory.focused_count - 1 { memory.focused[i] = memory.focused[i + 1] }
    memory.focused_count -= 1
    memory.focused[memory.focused_count] = {}
}

@(private)
memory_remove_cue :: proc(memory: ^Visual_Memory, index: int) {
    for i in index..<memory.cue_count - 1 { memory.cues[i] = memory.cues[i + 1] }
    memory.cue_count -= 1
    memory.cues[memory.cue_count] = {}
}

// Ingest one sample exactly once. Re-reading a retained sample, a sample that is
// not new, or a non-sampled status changes nothing and prolongs nothing.
memory_ingest :: proc(memory: ^Visual_Memory, input: obs.Sense_Input, config: Memory_Config, trace: ^Trace_Buffer = nil, parent: int = 0) -> (change: Memory_Change) {
    sample := input.vision
    if !input.vision_is_new || sample.status != .Sampled || (memory.ingested_samples > 0 && sample.sample_id == memory.last_sample_id) { return }
    change.ingested = true
    memory.last_sample_id = sample.sample_id
    memory.ingested_samples += 1
    for sighting in sample.focused[:sample.focused_count] {
        entry := Focused_Memory{subject = sighting.subject, kind = sighting.kind, appearance_id = sighting.appearance_id, position = sighting.position,
            facing = sighting.facing, locomotion = sighting.locomotion, observed_tick = sample.sample_tick,
            expires_tick = sample.sample_tick + config.focused_retention_ticks, sample_id = sample.sample_id, observation_id = sighting.observation_id}
        index := memory_find_focused(memory, sighting.subject)
        if index >= 0 {
            memory.focused[index] = entry
            change.focused_updated += 1
            trace_add(trace, parent, .State, .Info, "Update remembered focused subject", "observed_tick / expires_tick", f64(entry.observed_tick), f64(entry.expires_tick), entry.position, entry.observation_id, u32(entry.subject))
            continue
        }
        if memory.focused_count == MEMORY_CAPACITY {
            memory_remove_focused(memory, memory_oldest_focused(memory, sample.sample_tick))
            change.evicted += 1
        }
        memory.focused[memory.focused_count] = entry
        memory.focused_count += 1
        change.focused_added += 1
        trace_add(trace, parent, .State, .Info, "Remember new focused subject", "observed_tick / expires_tick", f64(entry.observed_tick), f64(entry.expires_tick), entry.position, entry.observation_id, u32(entry.subject))
    }
    for cue in sample.cues[:sample.cue_count] {
        entry := Cue_Memory{sector = cue.sector, band = cue.band, reference_facing = sample.pose.facing, observed_tick = sample.sample_tick,
            expires_tick = sample.sample_tick + config.peripheral_retention_ticks, sample_id = sample.sample_id, observation_id = cue.observation_id}
        index := memory_find_cue(memory, obs.cue_absolute_facing(entry.reference_facing, entry.sector), entry.band)
        if index >= 0 {
            memory.cues[index] = entry
            change.cues_updated += 1
            trace_add(trace, parent, .State, .Info, "Refresh remembered peripheral cue", "sector / band", f64(cue.sector), f64(cue.band), {}, cue.observation_id)
            continue
        }
        if memory.cue_count == MEMORY_CAPACITY {
            memory_remove_cue(memory, memory_oldest_cue(memory, sample.sample_tick))
            change.evicted += 1
        }
        memory.cues[memory.cue_count] = entry
        memory.cue_count += 1
        change.cues_added += 1
        trace_add(trace, parent, .State, .Info, "Remember new peripheral cue", "sector / band", f64(cue.sector), f64(cue.band), {}, cue.observation_id)
    }
    return
}

// Drop expired evidence. Expiry is measured from the original sample tick.
memory_expire :: proc(memory: ^Visual_Memory, now: u32) -> (expired: int) {
    for index := memory.focused_count - 1; index >= 0; index -= 1 {
        if tick_due(now, memory.focused[index].expires_tick) { memory_remove_focused(memory, index); expired += 1 }
    }
    for index := memory.cue_count - 1; index >= 0; index -= 1 {
        if tick_due(now, memory.cues[index].expires_tick) { memory_remove_cue(memory, index); expired += 1 }
    }
    return
}
