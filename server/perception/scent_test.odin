package perception

import obs "../observations"
import "core:testing"
import "core:time"
import "core:fmt"

@(private = "file")
scent_test_field :: proc(field: ^Scent_Field, width, height: int, solid: [][2]int = {}, water: [][2]int = {}) {
    media := make([]Scent_Medium, width * height)
    defer delete(media)
    for cell in solid { media[cell.y * width + cell.x] = .Solid }
    for cell in water { media[cell.y * width + cell.x] = .Water }
    scent_field_init(field, width, height, 32, media)
}

@(private = "file")
scent_test_query :: proc(field: ^Scent_Field, nose: obs.Vector, range: f32 = 160, freshness := true) -> Olfaction_Query {
    return {observer = {entity_id = 1, round_id = 1, pose = {nose, .North}},
        profile = {enabled = true, range = range, sample_interval = 12, estimates_freshness = freshness}, field = field}
}

@(test)
deposits_persist_after_the_source_leaves_and_fade_to_empty :: proc(t: ^testing.T) {
    field := new(Scent_Field)
    defer free(field)
    scent_test_field(field, 12, 8)
    // Walk east across four tiles at 64 units per second, then stop emitting.
    position := obs.Vector{48, 112}
    for _ in 0..<120 {
        next := position + {64.0 / 60, 0}
        scent_field_deposit_segment(field, .Human, position, next, SCENT_EMISSION_PER_TICK)
        position = next
    }
    // A fully crossed tile takes half a second of emission: 0.75 of the cap.
    testing.expect(t, position.x > 170 && abs(scent_field_level(field, .Human, {2, 3}) - 0.75) < 0.01, "a fully crossed tile should hold a strong trace")
    testing.expect(t, scent_field_level(field, .Human, {4, 3}) > 0.3 && scent_field_level(field, .Orc, {2, 3}) == 0, "classes stay separate")
    testing.expect(t, scent_field_age_ticks(field, .Human, {2, 3}) == 0 && field.bounds.active)
    before := scent_field_level(field, .Human, {2, 3})
    for _ in 0..<150 { scent_field_advance(field) } // 15 seconds of simulation time
    after := scent_field_level(field, .Human, {2, 3})
    // Pure decay would leave 59%; a line trail also bleeds sideways, so roughly a quarter remains.
    testing.expectf(t, after > before * 0.15 && after < before * 0.4, "decay plus lateral spread expected, got %v -> %v", before, after)
    testing.expect(t, scent_field_age_ticks(field, .Human, {2, 3}) == 150 * SCENT_STEP_TICKS, "age counts field steps since the deposit")
    halo := scent_field_level(field, .Human, {2, 2})
    testing.expectf(t, halo > 0 && halo < after * 0.6, "scent spreads a faint halo to open neighbours: trail %v, halo %v", after, halo)
    testing.expect(t, scent_field_age_ticks(field, .Human, {2, 2}) > 0 && scent_field_age_ticks(field, .Human, {2, 2}) <= 150 * SCENT_STEP_TICKS, "halo scent is as old as the trail it came from")
    for _ in 0..<1500 { scent_field_advance(field) }
    testing.expect(t, !field.bounds.active && scent_field_total(field, .Human) == 0, "a finished trail is empty again, not a forever-tiny number")
    testing.expect(t, scent_field_age_ticks(field, .Human, {2, 3}) == 0)
}

@(test)
propagation_follows_the_authored_media_rules :: proc(t: ^testing.T) {
    field := new(Scent_Field)
    defer free(field)
    // Row 3 has a solid wall at x=5 and a two-cell pool of water at x=8..9.
    scent_test_field(field, 12, 8, solid = {{5, 3}}, water = {{8, 3}, {9, 3}})
    scent_field_deposit(field, .Orc, {5, 3}, 1)
    testing.expect(t, scent_field_level(field, .Orc, {5, 3}) == 0 && !field.bounds.active, "solid cells never hold scent")
    scent_field_deposit(field, .Orc, {-1, 3}, 1)
    open_control := new(Scent_Field)
    defer free(open_control)
    scent_test_field(open_control, 12, 8)
    // Emitters stand still beside the wall and beside the pool for ten seconds.
    for _ in 0..<100 {
        for target in ([]^Scent_Field{field, open_control}) {
            scent_field_deposit(target, .Orc, {4, 3}, SCENT_CAP)
            scent_field_deposit(target, .Orc, {7, 3}, SCENT_CAP)
            scent_field_advance(target)
        }
    }
    testing.expect(t, scent_field_level(field, .Orc, {5, 3}) == 0 && scent_field_level(open_control, .Orc, {5, 3}) > 0, "a wall stops spread where open ground lets it through")
    testing.expect(t, scent_field_level(field, .Orc, {4, 2}) > 0 && scent_field_level(field, .Orc, {4, 4}) > 0, "scent goes around the wall through open neighbours")
    testing.expect(t, scent_field_level(field, .Orc, {8, 3}) > 0, "scent enters water")
    testing.expect(t, scent_field_level(field, .Orc, {8, 3}) < scent_field_level(open_control, .Orc, {8, 3}) * 0.5, "water loses scent much faster than open ground")
    testing.expect(t, scent_field_level(field, .Orc, {10, 3}) == 0, "a two-cell pool is wide enough to stop the trace")
    // Map edge: scent deposited in a corner stays inside; nothing leaks out.
    corner := new(Scent_Field)
    defer free(corner)
    scent_test_field(corner, 6, 6)
    scent_field_deposit(corner, .Human, {0, 0}, 1)
    center := new(Scent_Field)
    defer free(center)
    scent_test_field(center, 6, 6)
    scent_field_deposit(center, .Human, {3, 3}, 1)
    for _ in 0..<10 {
        scent_field_advance(corner)
        scent_field_advance(center)
    }
    testing.expect(t, scent_field_level(corner, .Human, {0, 0}) > scent_field_level(center, .Human, {3, 3}), "a corner cell keeps more because two sides are closed")
    // Only sub-negligible halo cells differ between the two placements; the edge itself leaks nothing.
    testing.expect(t, abs(scent_field_total(corner, .Human) - scent_field_total(center, .Human)) < 0.01, "the map edge neither leaks nor adds scent")
    testing.expect(t, scent_field_level(center, .Human, {2, 3}) > 0 && scent_field_level(corner, .Human, {1, 0}) > 0, "both fields grew a halo")
}

@(test)
teleports_blocked_steps_and_caps_keep_the_trail_honest :: proc(t: ^testing.T) {
    field := new(Scent_Field)
    defer free(field)
    scent_test_field(field, 12, 8)
    scent_field_deposit_segment(field, .Human, {48, 48}, {300, 200}, 1)
    testing.expect(t, !field.bounds.active, "a teleport-sized jump paints nothing")
    // A fast mover still paints every newly crossed tile; the start cell was painted last tick.
    scent_field_deposit_segment(field, .Human, {16, 48}, {80, 48}, 1)
    testing.expect(t, scent_field_level(field, .Human, {0, 1}) == 0 && scent_field_level(field, .Human, {1, 1}) > 0 && scent_field_level(field, .Human, {2, 1}) > 0)
    testing.expect(t, abs(scent_field_total(field, .Human) - 1) < 1e-5, "the tick's emission is shared across the crossed cells")
    // Standing still saturates the cell but never exceeds the cap.
    for _ in 0..<600 { scent_field_deposit_segment(field, .Human, {48, 112}, {48, 112}, SCENT_EMISSION_PER_TICK) }
    testing.expect(t, scent_field_level(field, .Human, {1, 3}) == SCENT_CAP && scent_field_level(field, .Human, {2, 3}) == 0)
    // A blocked step deposits where the emitter actually is, not where it tried to go.
    scent_field_deposit_segment(field, .Orc, {48, 240}, {48, 240}, SCENT_EMISSION_PER_TICK)
    testing.expect(t, scent_field_level(field, .Orc, {1, 7}) > 0 && scent_field_level(field, .Orc, {2, 7}) == 0)
}

@(test)
nose_reports_anonymous_zones_bearing_freshness_and_range :: proc(t: ^testing.T) {
    field := new(Scent_Field)
    defer free(field)
    scent_test_field(field, 20, 12)
    // A north-south human trail three tiles east of the nose, plus one orc cell far away.
    for y in 2..=9 { scent_field_deposit(field, .Human, {8, y}, 1) }
    scent_field_deposit(field, .Orc, {17, 6}, 0.9)
    nose := obs.Vector{5 * 32 + 16, 6 * 32 + 16}
    sample, audit := olfaction_sample(scent_test_query(field, nose), 3, 300, 300)
    testing.expect(t, sample.status == .Sampled && sample.reading_count == 1 && sample.readings[0].class == .Human, "only the trail inside range is smelled")
    human := sample.readings[0]
    testing.expect(t, human.observation_id == SCENT_OBSERVATION_BASE + 3 * 8 + 1 && human.strength == .Strong)
    testing.expect(t, human.bearing_valid && human.bearing == .East, "the trail is east of the nose")
    testing.expect(t, human.freshness == .Very_Recent && human.zones[obs.scent_zone_index(2, true)] != .None)
    testing.expect(t, human.zones[obs.scent_zone_index(6, false)] == .None && human.zones[obs.scent_zone_index(6, true)] == .None, "nothing west")
    testing.expect(t, audit.cells_sampled > 0 && audit.cells_blind >= 1 && audit.peak[.Human] == 1 && audit.peak[.Orc] == 0)
    // The orc cell is 384 units away: outside a human nose, inside an orc nose.
    orc_sample, _ := olfaction_sample(scent_test_query(field, nose, 400), 4, 300, 300)
    testing.expect(t, orc_sample.reading_count == 2 && orc_sample.readings[1].class == .Orc && orc_sample.readings[1].bearing == .East)
    testing.expect(t, orc_sample.readings[1].observation_id == SCENT_OBSERVATION_BASE + 4 * 8 + 2)
    // Age moves the freshness band without changing the class or the bearing.
    for _ in 0..<40 { scent_field_advance(field) }
    aged, _ := olfaction_sample(scent_test_query(field, nose), 5, 540, 540)
    testing.expect(t, aged.reading_count == 1 && aged.readings[0].freshness == .Recent && aged.readings[0].bearing == .East)
    unknown, _ := olfaction_sample(scent_test_query(field, nose, freshness = false), 6, 540, 540)
    testing.expect(t, unknown.readings[0].freshness == .Unknown && unknown.readings[0].strength == aged.readings[0].strength, "a receptor without freshness says unknown, not old")
    // Scent all around the nose is presence without a usable direction.
    ring := new(Scent_Field)
    defer free(ring)
    scent_test_field(ring, 20, 12)
    for y in 3..=9 { for x in 2..=8 { if x == 2 || x == 8 || y == 3 || y == 9 { scent_field_deposit(ring, .Human, {x, y}, 0.5) } } }
    surrounded, ring_audit := olfaction_sample(scent_test_query(ring, nose), 7, 600, 600)
    testing.expect(t, surrounded.reading_count == 1 && !surrounded.readings[0].bearing_valid && surrounded.readings[0].strength != .None, "a ring of scent gives presence with no bearing")
    testing.expect(t, ring_audit.coherence[.Human] < SCENT_BEARING_COHERENCE)
    // Own cell is blind: a fresh deposit under the nose alone yields nothing.
    own := new(Scent_Field)
    defer free(own)
    scent_test_field(own, 20, 12)
    scent_field_deposit(own, .Human, {5, 6}, 1)
    blind, _ := olfaction_sample(scent_test_query(own, nose), 8, 600, 600)
    testing.expect(t, blind.reading_count == 0, "the body's own cell is not sampled")
    // Disabled and invalid profiles are explicit, never an empty sample.
    disabled, _ := olfaction_sample({observer = {entity_id = 1, round_id = 1, pose = {nose, .North}}, profile = {enabled = false, range = 160, sample_interval = 12}, field = field}, 9, 600, 600)
    testing.expect(t, disabled.status == .Disabled && disabled.reading_count == 0)
    testing.expect(t, !olfaction_profile_valid({true, 0, 12, true}) && !olfaction_profile_valid({true, 1025, 12, true}) && !olfaction_profile_valid({true, 160, 0, true}) && olfaction_profile_valid({true, 1024, 60, false}))
}

@(test)
worst_supported_scent_envelope_stays_bounded :: proc(t: ^testing.T) {
    field := new(Scent_Field)
    defer free(field)
    media := make([]Scent_Medium, MAX_GRID_CELLS)
    defer delete(media)
    for &medium, index in media { if index % 7 == 0 { medium = .Solid } }
    scent_field_init(field, MAX_GRID_SIDE, MAX_GRID_SIDE, 16, media)
    // Scent everywhere: the widest possible update box and the widest possible nose.
    for y in 0..<MAX_GRID_SIDE { for x in 0..<MAX_GRID_SIDE { scent_field_deposit(field, .Human, {x, y}, 0.5); scent_field_deposit(field, .Orc, {x, y}, 0.5) } }
    started := time.tick_now()
    for _ in 0..<10 { scent_field_advance(field) }
    step := time.tick_since(started) / 10
    query := scent_test_query(field, {1024, 1024}, MAX_OLFACTION_RANGE_GAMEPLAY_UNITS * WORLD_UNITS_PER_GAMEPLAY_UNIT)
    started = time.tick_now()
    sample, audit := olfaction_sample(query, 1, 1, 1)
    sampled := time.tick_since(started)
    testing.expect(t, sample.reading_count == 2 && audit.cells_sampled > 10000 && field.bounds.active)
    testing.expect(t, size_of(Scent_Field) < 320 * 1024, "fixed field storage must stay small enough to copy freely")
    fmt.printf("[scent] worst supported envelope: 128x128 field step %v, one 1024-unit nose sample %v over %d cells, %d bytes per field\n", step, sampled, audit.cells_sampled, size_of(Scent_Field))
}
