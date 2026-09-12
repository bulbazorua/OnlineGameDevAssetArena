package perception

import obs "../observations"
import "core:math"
import "core:testing"
import "core:fmt"

// Frozen direct-math sampler: faster sampling must preserve readings and coverage.
@(private = "file")
reference_olfaction_profile_valid :: proc(p: obs.Olfaction_Profile) -> bool {
    if math.is_nan(p.range) || math.is_inf(p.range) { return false }
    return p.range > 0 && p.range <= MAX_OLFACTION_RANGE_GAMEPLAY_UNITS * WORLD_UNITS_PER_GAMEPLAY_UNIT &&
        p.sample_interval >= 1 && p.sample_interval <= 60
}

@(private = "file")
reference_scent_strength_of :: proc(level: f32) -> obs.Scent_Strength {
    switch {
    case level >= SCENT_STRONG_LEVEL: return .Strong
    case level >= SCENT_MEDIUM_LEVEL: return .Medium
    case level >= SCENT_WEAK_LEVEL: return .Weak
    }
    return .None
}

@(private = "file")
reference_scent_freshness_of :: proc(age_ticks: u32) -> obs.Scent_Freshness {
    switch {
    case age_ticks < SCENT_VERY_RECENT_TICKS: return .Very_Recent
    case age_ticks < SCENT_RECENT_TICKS: return .Recent
    }
    return .Old
}

// A zone is measured when at least one cell in it was; it is only fully measured
// when nothing in it was solid or off the map.
@(private = "file")
reference_scent_coverage_of :: proc(sampled, excluded: int) -> obs.Scent_Coverage {
    switch {
    case sampled == 0: return .Unsampled
    case excluded == 0: return .Sampled
    }
    return .Partial
}

// Compass sector of a world offset: 0 is north, then clockwise in 45-degree steps.
@(private = "file")
reference_scent_sector_of :: proc(offset: obs.Vector) -> int {
    angle := math.atan2(offset.x, -offset.y)
    return (int(math.round(angle / (math.PI / 4))) + 8) % 8
}

// Unit direction pointing at the middle of one zone's sector.
@(private = "file")
reference_scent_zone_direction :: proc(zone: int) -> obs.Vector {
    return obs.facing_direction(obs.Facing(obs.scent_zone_sector(zone)))
}

// Where one cell sits relative to the nose: inside reach or not, in the body's
// blind disc or not, which zone, and how much its scent counts at that distance.
@(private = "file")
reference_Scent_Cell_Reach :: struct {
    inside, blind: bool,
    zone: int,
    falloff: f32,
}

@(private = "file")
reference_scent_cell_reach :: proc(field: ^Scent_Field, nose: obs.Vector, range: f32, cell: [2]int) -> (reach: reference_Scent_Cell_Reach) {
    center := obs.Vector{(f32(cell.x) + 0.5) * field.tile_size, (f32(cell.y) + 0.5) * field.tile_size}
    offset := center - nose
    distance := math.sqrt(offset.x * offset.x + offset.y * offset.y)
    if distance > range { return }
    reach.inside = true
    reach.blind = distance <= SCENT_BLIND_RADIUS_TILES * field.tile_size
    reach.zone = obs.scent_zone_index(reference_scent_sector_of(offset), distance > range * 0.5)
    reach.falloff = 1 - SCENT_RANGE_FALLOFF * distance / range
    return
}

// Raw per-class zone maxima and per-zone measurement counts gathered from the
// field; reduced to bands and coverage afterwards.
@(private = "file")
reference_Scent_Gather :: struct {
    zones: [obs.Scent_Class][obs.SCENT_ZONES]f32,
    newest_age, newest_detectable_age: [obs.Scent_Class]u32,
    present: [obs.Scent_Class]bool,
    sampled, excluded: [obs.SCENT_ZONES]int,
}

// Fold one measured cell into the gather. Only a cell the nose could detect on
// its own is allowed to say how fresh the scent is.
@(private = "file")
reference_scent_gather_cell :: proc(field: ^Scent_Field, gather: ^reference_Scent_Gather, audit: ^Olfaction_Audit, cell: [2]int, reach: reference_Scent_Cell_Reach) {
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
reference_scent_gather_cells :: proc(query: Olfaction_Query, audit: ^Olfaction_Audit) -> (gather: reference_Scent_Gather) {
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
            reach := reference_scent_cell_reach(field, nose, range, cell)
            if !reach.inside { continue }
            if reach.blind { audit.cells_blind += 1; continue }
            if scent_field_medium(field, cell) == .Solid {
                audit.cells_excluded += 1
                gather.excluded[reach.zone] += 1
                continue
            }
            audit.cells_sampled += 1
            gather.sampled[reach.zone] += 1
            reference_scent_gather_cell(field, &gather, audit, cell, reach)
        }
    }
    return
}

// Reduce one class's zones to the permitted reading: bands, a bearing only when
// the zones agree, and a freshness band from detectable cells when supported.
@(private = "file")
reference_scent_reading_from_zones :: proc(class: obs.Scent_Class, zones: [obs.SCENT_ZONES]f32, newest_detectable_age: u32, profile: obs.Olfaction_Profile, coherence_out: ^f32) -> (reading: obs.Scent_Reading, present: bool) {
    reading.class = class
    strongest: f32
    pull: obs.Vector
    weight: f32
    for value, zone in zones {
        reading.zones[zone] = reference_scent_strength_of(value)
        if reading.zones[zone] == .None { continue }
        strongest = max(strongest, value)
        share := value * (SCENT_FAR_ZONE_WEIGHT if obs.scent_zone_is_far(zone) else 1)
        pull += reference_scent_zone_direction(zone) * share
        weight += share
    }
    reading.strength = reference_scent_strength_of(strongest)
    if reading.strength == .None { return reading, false }
    magnitude := math.sqrt(pull.x * pull.x + pull.y * pull.y)
    coherence := magnitude / weight if weight > 0 else 0
    coherence_out^ = coherence
    if coherence >= SCENT_BEARING_COHERENCE {
        reading.bearing, reading.bearing_valid = obs.facing_toward({}, pull)
    }
    reading.freshness = reference_scent_freshness_of(newest_detectable_age) if profile.estimates_freshness else .Unknown
    return reading, true
}

// Sample the field around the observer. Own body cells are skipped, solid cells
// hold nothing, every zone reports its coverage, and every class present becomes
// one anonymous reading.
@(private = "file")
reference_olfaction_sample :: proc(query: Olfaction_Query, sample_id, sample_tick, delivered_tick: u32) -> (sample: obs.Scent_Sample, audit: Olfaction_Audit) {
    sample.sample_id, audit.sample_id = sample_id, sample_id
    sample.observer, sample.round_id = query.observer.entity_id, query.observer.round_id
    sample.sample_tick, sample.delivered_tick = sample_tick, delivered_tick
    sample.position, sample.profile = query.observer.pose.position, query.profile
    if !query.profile.enabled || !reference_olfaction_profile_valid(query.profile) || query.field == nil || !scent_field_valid(query.field) || !obs.vector_finite(sample.position) {
        sample.status = .Disabled
        return
    }
    sample.status = .Sampled
    gather := reference_scent_gather_cells(query, &audit)
    for zone in 0..<obs.SCENT_ZONES { sample.coverage[zone] = reference_scent_coverage_of(gather.sampled[zone], gather.excluded[zone]) }
    for class in obs.Scent_Class {
        if !gather.present[class] { continue }
        audit.newest_age_ticks[class] = gather.newest_age[class]
        audit.newest_detectable_age_ticks[class] = gather.newest_detectable_age[class]
        reading, present := reference_scent_reading_from_zones(class, gather.zones[class], gather.newest_detectable_age[class], query.profile, &audit.coherence[class])
        if !present || sample.reading_count == len(sample.readings) { continue }
        reading.observation_id = SCENT_OBSERVATION_BASE + sample_id * 8 + u32(sample.reading_count) + 1
        sample.readings[sample.reading_count] = reading
        sample.reading_count += 1
    }
    return
}

@(test)
olfaction_fast_sectors_match_direct_angles_including_boundaries :: proc(t: ^testing.T) {
    mismatches, checked := 0, 0
    offsets := [6]obs.Vector{{0, 0}, {0.5, 0.5}, {0.125, -0.625}, {0.999, 0.001}, {-0.5, 0.25}, {7.999, -8.00001}}
    for shift in offsets {
        for y in -64..=64 {
            for x in -64..=64 {
                point := obs.Vector{f32(x), f32(y)} + shift
                if scent_sector_of(point) != reference_scent_sector_of(point) { mismatches += 1 }
                checked += 1
            }
        }
    }
    for boundary in 0..<8 {
        for offset in ([5]f64{-0.0001, -0.000001, 0, 0.000001, 0.0001}) {
            angle := (22.5 + 45 * f64(boundary) + offset) * math.PI / 180
            for scale in ([3]f32{1, 32, 1024}) {
                point := obs.Vector{f32(math.sin(angle)), f32(-math.cos(angle))} * scale
                if scent_sector_of(point) != reference_scent_sector_of(point) { mismatches += 1 }
                checked += 1
            }
        }
    }
    fmt.printfln("[olfaction parity] %d bearing comparisons, %d mismatches", checked, mismatches)
    testing.expect(t, mismatches == 0)
}

@(test)
olfaction_optimized_samples_are_identical_to_the_previous_sampler :: proc(t: ^testing.T) {
    field := new(Scent_Field)
    defer free(field)
    media: [24 * 24]Scent_Medium
    for &medium, index in media { medium = .Solid if index % 11 == 0 else (.Water if index % 5 == 0 else .Open) }
    scent_field_init(field, 24, 24, 16, media[:])
    for y in 0..<24 {
        for x in 0..<24 {
            scent_field_deposit(field, .Human, {x, y}, f32((x * 17 + y * 7) % 101) / 100)
            scent_field_deposit(field, .Orc, {x, y}, f32((x * 3 + y * 31) % 101) / 100)
            field.ages[.Human][y * 24 + x] = u16(x * 29 + y * 13)
            field.ages[.Orc][y * 24 + x] = u16(x * 7 + y * 41)
        }
    }
    positions := [8]obs.Vector{{0, 0}, {8, 8}, {192, 192}, {192.125, 191.875}, {383, 383}, {400, 192}, {-8, 128}, {80, 240}}
    for position in positions {
        for range in ([6]f32{8, 16, 32, 160, 256, 1024}) {
            for freshness in ([2]bool{false, true}) {
                query := Olfaction_Query{observer = {entity_id = 3, round_id = 7, pose = {position, .North}},
                    profile = {true, range, 12, freshness}, field = field}
                expected, expected_audit := reference_olfaction_sample(query, 91, 1000, 1000)
                actual, actual_audit := olfaction_sample(query, 91, 1000, 1000)
                testing.expectf(t, actual == expected && actual_audit == expected_audit, "olfaction parity at %v, range %v, freshness %v", position, range, freshness)
            }
        }
    }
}
