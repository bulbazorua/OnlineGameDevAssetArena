// The nose: a privileged read of the shared scent field around one observer,
// reduced to anonymous class readings. It sees the true field and the true pose;
// its output boundary is the observations package.
package perception

import obs "../observations"
import "core:math"

// Cells closer than this many tiles are the observer's own body: not sampled.
SCENT_BLIND_RADIUS_TILES :: f32(0.75)
// Scent farther from the nose counts for less; the far edge keeps 40%.
SCENT_RANGE_FALLOFF :: f32(0.6)
SCENT_WEAK_LEVEL :: f32(0.03)
SCENT_MEDIUM_LEVEL :: f32(0.15)
SCENT_STRONG_LEVEL :: f32(0.45)
// A bearing is reported only when the sampled zones mostly point one way.
SCENT_BEARING_COHERENCE :: f32(0.35)
SCENT_FAR_ZONE_WEIGHT :: f32(0.7)
SCENT_VERY_RECENT_TICKS :: u32(180)
SCENT_RECENT_TICKS :: u32(900)
// Scent observation IDs live in the upper half so they never collide with vision IDs.
SCENT_OBSERVATION_BASE :: u32(0x8000_0000)

Olfaction_Query :: struct {
    observer: Observer,
    profile: obs.Olfaction_Profile,
    field: ^Scent_Field,
}

// Host-only developer evidence about one nose sample. Never a brain input.
Olfaction_Audit :: struct {
    sample_id: u32,
    cells_sampled, cells_blind: int,
    cells_excluded: int, // Inside reach but solid or beyond the map: never measurable.
    peak: [obs.Scent_Class]f32,
    newest_age_ticks: [obs.Scent_Class]u32,            // Newest trace of any level, host truth only.
    newest_detectable_age_ticks: [obs.Scent_Class]u32, // What the delivered freshness was built from.
    coherence: [obs.Scent_Class]f32,
}

olfaction_profile_valid :: proc(p: obs.Olfaction_Profile) -> bool {
    if math.is_nan(p.range) || math.is_inf(p.range) { return false }
    return p.range > 0 && p.range <= MAX_OLFACTION_RANGE_GAMEPLAY_UNITS * WORLD_UNITS_PER_GAMEPLAY_UNIT &&
        p.sample_interval >= 1 && p.sample_interval <= 60
}

scent_strength_of :: proc(level: f32) -> obs.Scent_Strength {
    switch {
    case level >= SCENT_STRONG_LEVEL: return .Strong
    case level >= SCENT_MEDIUM_LEVEL: return .Medium
    case level >= SCENT_WEAK_LEVEL: return .Weak
    }
    return .None
}

scent_freshness_of :: proc(age_ticks: u32) -> obs.Scent_Freshness {
    switch {
    case age_ticks < SCENT_VERY_RECENT_TICKS: return .Very_Recent
    case age_ticks < SCENT_RECENT_TICKS: return .Recent
    }
    return .Old
}

// A zone is measured when at least one cell in it was; it is only fully measured
// when nothing in it was solid or off the map.
scent_coverage_of :: proc(sampled, excluded: int) -> obs.Scent_Coverage {
    switch {
    case sampled == 0: return .Unsampled
    case excluded == 0: return .Sampled
    }
    return .Partial
}

// Compass sector of a world offset: 0 is north, then clockwise in 45° steps.
scent_sector_of :: proc(offset: obs.Vector) -> int {
    angle := math.atan2(offset.x, -offset.y)
    return (int(math.round(angle / (math.PI / 4))) + 8) % 8
}

// Unit direction pointing at the middle of one zone's sector.
scent_zone_direction :: proc(zone: int) -> obs.Vector {
    return obs.facing_direction(obs.Facing(obs.scent_zone_sector(zone)))
}

// Where one cell sits relative to the nose: inside reach or not, in the body's
// blind disc or not, which zone, and how much its scent counts at that distance.
@(private = "file")
Scent_Cell_Reach :: struct {
    inside, blind: bool,
    zone: int,
    falloff: f32,
}

@(private = "file")
scent_cell_reach :: proc(field: ^Scent_Field, nose: obs.Vector, range: f32, cell: [2]int) -> (reach: Scent_Cell_Reach) {
    center := obs.Vector{(f32(cell.x) + 0.5) * field.tile_size, (f32(cell.y) + 0.5) * field.tile_size}
    offset := center - nose
    distance := math.sqrt(offset.x * offset.x + offset.y * offset.y)
    if distance > range { return }
    reach.inside = true
    reach.blind = distance <= SCENT_BLIND_RADIUS_TILES * field.tile_size
    reach.zone = obs.scent_zone_index(scent_sector_of(offset), distance > range * 0.5)
    reach.falloff = 1 - SCENT_RANGE_FALLOFF * distance / range
    return
}

// Raw per-class zone maxima and per-zone measurement counts gathered from the
// field; reduced to bands and coverage afterwards.
@(private = "file")
Scent_Gather :: struct {
    zones: [obs.Scent_Class][obs.SCENT_ZONES]f32,
    newest_age, newest_detectable_age: [obs.Scent_Class]u32,
    present: [obs.Scent_Class]bool,
    sampled, excluded: [obs.SCENT_ZONES]int,
}

// Fold one measured cell into the gather. Only a cell the nose could detect on
// its own is allowed to say how fresh the scent is.
@(private = "file")
scent_gather_cell :: proc(field: ^Scent_Field, gather: ^Scent_Gather, audit: ^Olfaction_Audit, cell: [2]int, reach: Scent_Cell_Reach) {
    index := cell.y * field.width + cell.x
    for class in obs.Scent_Class {
        level := field.levels[class][index]
        if level <= 0 { continue }
        gather.present[class] = true
        scaled := level * reach.falloff
        gather.zones[class][reach.zone] = max(gather.zones[class][reach.zone], scaled)
        age := scent_field_age_ticks(field, class, cell)
        gather.newest_age[class] = min(gather.newest_age[class], age)
        if scaled >= SCENT_WEAK_LEVEL { gather.newest_detectable_age[class] = min(gather.newest_detectable_age[class], age) }
        audit.peak[class] = max(audit.peak[class], level)
    }
}

// Walk the whole reach box, including ground beyond the map, so every zone
// learns whether it was measured, partly measured or not measured at all.
@(private = "file")
scent_gather_cells :: proc(query: Olfaction_Query, audit: ^Olfaction_Audit) -> (gather: Scent_Gather) {
    field := query.field
    nose := query.observer.pose.position
    range := query.profile.range
    for &age in gather.newest_age { age = max(u32) }
    for &age in gather.newest_detectable_age { age = max(u32) }
    low := scent_field_cell_of(field, nose - {range, range})
    high := scent_field_cell_of(field, nose + {range, range})
    for y in low.y..=high.y {
        for x in low.x..=high.x {
            cell := [2]int{x, y}
            reach := scent_cell_reach(field, nose, range, cell)
            if !reach.inside { continue }
            if reach.blind { audit.cells_blind += 1; continue }
            if scent_field_medium(field, cell) == .Solid {
                audit.cells_excluded += 1
                gather.excluded[reach.zone] += 1
                continue
            }
            audit.cells_sampled += 1
            gather.sampled[reach.zone] += 1
            scent_gather_cell(field, &gather, audit, cell, reach)
        }
    }
    return
}

// Reduce one class's zones to the permitted reading: bands, a bearing only when
// the zones agree, and a freshness band from detectable cells when supported.
@(private = "file")
scent_reading_from_zones :: proc(class: obs.Scent_Class, zones: [obs.SCENT_ZONES]f32, newest_detectable_age: u32, profile: obs.Olfaction_Profile, coherence_out: ^f32) -> (reading: obs.Scent_Reading, present: bool) {
    reading.class = class
    strongest: f32
    pull: obs.Vector
    weight: f32
    for value, zone in zones {
        reading.zones[zone] = scent_strength_of(value)
        if reading.zones[zone] == .None { continue }
        strongest = max(strongest, value)
        share := value * (SCENT_FAR_ZONE_WEIGHT if obs.scent_zone_is_far(zone) else 1)
        pull += scent_zone_direction(zone) * share
        weight += share
    }
    reading.strength = scent_strength_of(strongest)
    if reading.strength == .None { return reading, false }
    magnitude := math.sqrt(pull.x * pull.x + pull.y * pull.y)
    coherence := magnitude / weight if weight > 0 else 0
    coherence_out^ = coherence
    if coherence >= SCENT_BEARING_COHERENCE {
        reading.bearing, reading.bearing_valid = obs.facing_toward({}, pull)
    }
    reading.freshness = scent_freshness_of(newest_detectable_age) if profile.estimates_freshness else .Unknown
    return reading, true
}

// Sample the field around the observer. Own body cells are skipped, solid cells
// hold nothing, every zone reports its coverage, and every class present becomes
// one anonymous reading.
olfaction_sample :: proc(query: Olfaction_Query, sample_id, sample_tick, delivered_tick: u32) -> (sample: obs.Scent_Sample, audit: Olfaction_Audit) {
    sample.sample_id, audit.sample_id = sample_id, sample_id
    sample.observer, sample.round_id = query.observer.entity_id, query.observer.round_id
    sample.sample_tick, sample.delivered_tick = sample_tick, delivered_tick
    sample.position, sample.profile = query.observer.pose.position, query.profile
    if !query.profile.enabled || !olfaction_profile_valid(query.profile) || query.field == nil || !scent_field_valid(query.field) || !obs.vector_finite(sample.position) {
        sample.status = .Disabled
        return
    }
    sample.status = .Sampled
    gather := scent_gather_cells(query, &audit)
    for zone in 0..<obs.SCENT_ZONES { sample.coverage[zone] = scent_coverage_of(gather.sampled[zone], gather.excluded[zone]) }
    for class in obs.Scent_Class {
        if !gather.present[class] { continue }
        audit.newest_age_ticks[class] = gather.newest_age[class]
        audit.newest_detectable_age_ticks[class] = gather.newest_detectable_age[class]
        reading, present := scent_reading_from_zones(class, gather.zones[class], gather.newest_detectable_age[class], query.profile, &audit.coherence[class])
        if !present || sample.reading_count == len(sample.readings) { continue }
        reading.observation_id = SCENT_OBSERVATION_BASE + sample_id * 8 + u32(sample.reading_count) + 1
        sample.readings[sample.reading_count] = reading
        sample.reading_count += 1
    }
    return
}
