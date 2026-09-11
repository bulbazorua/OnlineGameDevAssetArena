package perception

import obs "../observations"
import "core:math"
import "core:testing"
import "core:time"
import "core:fmt"

@(private = "file")
make_grid :: proc(rows: []string, tile: f32 = 32) -> Opacity_Grid {
    grid := Opacity_Grid{width = len(rows[0]), height = len(rows), tile_size = tile}
    grid.opaque = make([]bool, grid.width * grid.height)
    for row, y in rows {
        for x in 0..<grid.width { grid.opaque[y * grid.width + x] = row[x] == '#' }
    }
    return grid
}

@(private = "file")
open_grid :: proc(size: int) -> Opacity_Grid {
    grid := Opacity_Grid{width = size, height = size, tile_size = 32}
    grid.opaque = make([]bool, size * size)
    return grid
}

@(private = "file")
starter :: proc() -> obs.Vision_Profile { return {enabled = true, range = 256, focused_fov_degrees = 60, overall_fov_degrees = 160, sample_interval = 6} }

// A ground point at a clockwise angle (degrees) from the observer's forward axis.
@(private = "file")
offset_at :: proc(facing: obs.Facing, degrees: f64, distance: f32) -> obs.Vector {
    forward := obs.facing_direction(facing)
    base := math.atan2(f64(forward.x), f64(-forward.y)) + degrees * math.PI / 180
    return {f32(math.sin(base)) * distance, f32(-math.cos(base)) * distance}
}

@(private = "file")
query_with :: proc(grid: Opacity_Grid, eye: obs.Vector, facing: obs.Facing, positions: []obs.Vector, profile := obs.Vision_Profile{}) -> Vision_Query {
    query := Vision_Query{observer = {entity_id = 1, round_id = 7, pose = {eye, facing}}, profile = profile, grid = grid}
    if !profile.enabled { query.profile = starter() }
    for position, index in positions {
        query.candidates[index] = {entity_id = u32(10 + index), kind = .Trainer if index > 0 else .Creature, appearance_id = u16(5 + index), position = position, facing = .South, locomotion = .Walk}
        query.candidate_count += 1
    }
    return query
}

@(test)
field_geometry_covers_all_facings_and_exact_boundaries :: proc(t: ^testing.T) {
    grid := open_grid(40)
    defer delete(grid.opaque)
    eye := obs.Vector{640, 640}
    for facing in obs.Facing {
        cases := [][3]f64{ // degrees, distance, expected verdict index
            {0, 256, 6}, {0, 256.5, 3}, {29.99, 200, 6}, {30, 200, 6}, {30.2, 200, 7}, {-30.2, 200, 7},
            {45, 100, 7}, {-45, 250, 7}, {79.9, 200, 7}, {80, 200, 7}, {80.3, 200, 4}, {-80.3, 200, 4}, {180, 50, 4}, {0, 0.5, 6},
        }
        for entry in cases {
            query := query_with(grid, eye, facing, {eye + offset_at(facing, entry[0], f32(entry[1]))})
            sample, audit := vision_sample(query, 3, 120, 120)
            expected := Candidate_Verdict(int(entry[2]))
            testing.expectf(t, audit.candidates[0].verdict == expected, "facing %v angle %v distance %v: %v", facing, entry[0], entry[1], audit.candidates[0].verdict)
            testing.expect(t, sample.status == .Sampled && sample.pose.facing == facing && sample.sample_tick == 120 && sample.sample_id == 3)
            if expected == .Focused {
                testing.expect(t, sample.focused_count == 1 && sample.cue_count == 0 && sample.focused[0].subject == 10 && sample.focused[0].appearance_id == 5)
                testing.expect(t, sample.focused[0].position == query.candidates[0].position && sample.focused[0].facing == .South && sample.focused[0].locomotion == .Walk)
                testing.expect(t, sample.focused[0].observation_id == 3 * 8 + 1)
            } else if expected == .Peripheral {
                testing.expect(t, sample.focused_count == 0 && sample.cue_count == 1)
                expected_sector := u8((int(math.round(entry[0] / 45)) + 8) % 8)
                testing.expectf(t, sample.cues[0].sector == expected_sector, "sector %d expected %d", sample.cues[0].sector, expected_sector)
                testing.expect(t, sample.cues[0].band == (.Near if entry[1] <= 128 else .Far))
                testing.expect(t, sample.cues[0].observation_id == 3 * 8 + 1)
            } else {
                testing.expect(t, sample.focused_count == 0 && sample.cue_count == 0)
            }
        }
    }
}

@(test)
coincident_self_invalid_and_disabled_inputs_cannot_become_sightings :: proc(t: ^testing.T) {
    grid := make_grid({"........", "........", "..##....", "........", "........"})
    defer delete(grid.opaque)
    eye := obs.Vector{48, 48}
    query := query_with(grid, eye, .East, {eye, {math.nan_f32(), 48}, {math.inf_f32(1), 48}})
    query.candidates[1].entity_id = 1 // observer itself, also invalid position
    sample, audit := vision_sample(query, 1, 10, 10)
    testing.expect(t, audit.candidates[0].verdict == .Focused && sample.focused_count == 1 && sample.focused[0].position == eye)
    testing.expect(t, audit.candidates[1].verdict == .Self && audit.candidates[2].verdict == .Invalid && sample.cue_count == 0)
    // Observer inside an opaque cell: nothing is visible, the audit says why.
    blind := query_with(grid, {80, 80}, .East, {{112, 80}, {200, 80}})
    sample, audit = vision_sample(blind, 2, 11, 11)
    testing.expect(t, audit.origin_opaque && sample.focused_count == 0 && sample.cue_count == 0)
    testing.expect(t, audit.candidates[0].verdict == .Occluded && audit.candidates[1].verdict == .Occluded)
    // Disabled and invalid profiles produce a Disabled sample, not an empty valid one.
    disabled := starter()
    disabled.enabled = false
    query = query_with(grid, eye, .East, {{100, 48}})
    query.profile = disabled
    sample, _ = vision_sample(query, 3, 12, 12)
    testing.expect(t, sample.status == .Disabled && sample.focused_count == 0 && sample.profile == disabled)
    for invalid in ([]obs.Vision_Profile{
        {true, 0, 60, 160, 6}, {true, 256, 44.9, 160, 6}, {true, 256, 160, 160, 6}, {true, 256, 60, 180.5, 6}, {true, 256, 60, 160, 0},
        {true, 256, 60, 160, 61}, {true, math.nan_f32(), 60, 160, 6}, {true, 256, math.inf_f32(1), 160, 6}, {true, 64 * 32 + 1, 60, 160, 6},
    }) {
        testing.expect(t, !vision_profile_valid(invalid))
        query.profile = invalid
        sample, _ = vision_sample(query, 4, 13, 13)
        testing.expect(t, sample.status == .Disabled && sample.focused_count == 0 && sample.cue_count == 0)
    }
    testing.expect(t, vision_profile_valid({true, 256, 45, 180, 1}) && vision_profile_valid({true, 64 * 32, 60, 160, 60}))
}

@(test)
occlusion_follows_documented_supercover_rules :: proc(t: ^testing.T) {
    grid := make_grid({
        "..........",
        "....#.....",
        "..........",
        ".w..#.....",
        "..........",
        ".....#....",
        "......#...",
        "..........",
    })
    defer delete(grid.opaque)
    center :: proc(x, y: int) -> obs.Vector { return {f32(x) * 32 + 16, f32(y) * 32 + 16} }
    testing.expect(t, line_of_sight(grid, center(0, 0), center(9, 0)), "clear lane")
    testing.expect(t, line_of_sight(grid, center(0, 3), center(3, 3)), "water does not block sight")
    testing.expect(t, !line_of_sight(grid, center(0, 3), center(6, 3)), "wall footprint blocks")
    testing.expect(t, !line_of_sight(grid, center(0, 1), center(9, 1)), "single opaque cell blocks")
    testing.expect(t, !line_of_sight(grid, center(4, 1), center(4, 7)), "opaque origin cell blocks")
    testing.expect(t, !line_of_sight(grid, center(0, 5), center(5, 5)), "opaque target cell blocks")
    // Diagonal crack: cells (5,5) and (6,6) touch only at corner (6,6)*32.
    testing.expect(t, !line_of_sight(grid, {192 - 40, 192 + 40}, {192 + 40, 192 - 40}), "corner between two blockers is closed")
    testing.expect(t, !line_of_sight(grid, {160, 224}, {224, 160}), "exact corner touch counts as blocked")
    // Edge-aligned ray beside the opaque cell (4,1): x = 128 exactly.
    testing.expect(t, !line_of_sight(grid, {128, 8}, {128, 88}), "ray along a tile edge tests both sides")
    testing.expect(t, line_of_sight(grid, {160.5, 8}, {160.5, 88}), "ray inside the open neighbor column stays clear")
    // Segment endpoints outside the map or on invalid grids are blocked.
    testing.expect(t, !line_of_sight(grid, center(0, 0), {-1, 16}))
    testing.expect(t, !line_of_sight(grid, center(0, 0), {math.nan_f32(), 16}))
    testing.expect(t, !line_of_sight(Opacity_Grid{}, center(0, 0), center(1, 0)))
    clear, reach := sight_probe(grid, center(0, 1), center(9, 1))
    testing.expect(t, !clear && reach > 0.3 && reach < 0.45, "reach stops at the first opaque cell")
    // Height alone never blocks: the grid has no elevation input at all. The largest
    // accepted map stays clear end to end; nothing invents cover on an empty map.
    huge := Opacity_Grid{width = 128, height = 128, tile_size = 32}
    huge.opaque = make([]bool, 128 * 128)
    defer delete(huge.opaque)
    testing.expect(t, line_of_sight(huge, {16, 16}, {4000, 4000}), "a long diagonal on an empty map is clear")
    testing.expect(t, line_of_sight(huge, {16, 16}, {2000, 16}), "a long axis-aligned segment on an empty map is clear")
    testing.expect(t, line_of_sight(huge, {0, 0}, {4096, 4096}), "the map boundary line itself is inside the map")
    huge.opaque[64 * 128 + 64] = true
    testing.expect(t, !line_of_sight(huge, {16, 16}, {4000, 4000}), "one distant opaque cell still blocks the long diagonal")
    oversized := Opacity_Grid{width = MAX_GRID_SIDE + 1, height = 1, tile_size = 32}
    oversized.opaque = make([]bool, oversized.width)
    defer delete(oversized.opaque)
    testing.expect(t, !grid_valid(oversized) && !line_of_sight(oversized, {16, 16}, {48, 16}), "grids beyond the accepted size are rejected, never scanned")
}

// The review's literal boundary cases: a single opaque cell touched along each side,
// at a corner and at an endpoint, in both directions, with clear neighbors nearby.
@(test)
opaque_cell_edges_corners_and_endpoints_block_regardless_of_direction :: proc(t: ^testing.T) {
    grid := open_grid(10)
    defer delete(grid.opaque)
    grid.opaque[4 * 10 + 4] = true // closed footprint (128,128)..(160,160)
    blocked := [?][2]obs.Vector{
        {{128, 96}, {128, 192}}, {{160, 96}, {160, 192}}, // left and right edges
        {{96, 128}, {192, 128}}, {{96, 160}, {192, 160}}, // top and bottom edges
        {{192, 192}, {160, 160}}, {{96, 96}, {128, 128}}, // endpoints on far and near corners
        {{160, 96}, {160, 128}}, {{128, 160}, {128, 200}}, // endpoints on edge corners
        {{100, 188}, {188, 100}}, {{100, 100}, {188, 188}}, // diagonals through the cell
        {{144, 144}, {300, 144}}, {{150, 150}, {150, 150}}, // origin inside, point inside
        {{0, 0}, {320, 320}}, {{320, 0}, {0, 320}}, // full-map diagonals through the corners
    }
    for segment, index in blocked {
        for reverse in 0..<2 {
            from, to := segment[reverse], segment[1 - reverse]
            testing.expectf(t, !line_of_sight(grid, from, to), "blocked case %d reverse %d leaked", index, reverse)
        }
    }
    clear := [?][2]obs.Vector{
        {{127.9, 96}, {127.9, 192}}, {{160.1, 96}, {160.1, 192}}, // just outside the side edges
        {{96, 127.9}, {192, 127.9}}, {{96, 160.1}, {192, 160.1}}, // just outside the top and bottom edges
        {{192, 192}, {160.1, 160.1}}, {{96, 96}, {127.9, 127.9}}, // stopping short of the corners
        {{1, 320}, {320, 1}}, {{100, 200}, {200, 165}}, // near-diagonals that pass beside the cell
        {{96, 96}, {200, 96}}, {{96, 200}, {96, 96}}, // lanes beside the cell
    }
    for segment, index in clear {
        for reverse in 0..<2 {
            from, to := segment[reverse], segment[1 - reverse]
            testing.expectf(t, line_of_sight(grid, from, to), "clear case %d reverse %d was blocked", index, reverse)
        }
    }
    // Reach is the same fraction whichever axis leads the sweep.
    _, reach_x := sight_probe(grid, {32, 144}, {288, 144})
    _, reach_y := sight_probe(grid, {144, 32}, {144, 288})
    testing.expect(t, reach_x == reach_y && reach_x > 0.37 && reach_x < 0.38, "reach stops at the cell's near edge")
}

// Sweep results must agree with an exhaustive scan of every cell for random segments.
@(test)
lane_sweep_matches_exhaustive_cell_scan :: proc(t: ^testing.T) {
    grid := open_grid(24)
    defer delete(grid.opaque)
    state: u64 = 0x9e3779b97f4a7c15
    next :: proc(state: ^u64) -> u64 { state^ = state^ * 6364136223846793005 + 1442695040888963407; return state^ >> 33 }
    for i in 0..<len(grid.opaque) { grid.opaque[i] = next(&state) % 7 == 0 }
    exhaustive :: proc(grid: Opacity_Grid, from, to: obs.Vector) -> (clear: bool, reach: f64) {
        tile := f64(grid.tile_size)
        ax, ay := f64(from.x) / tile, f64(from.y) / tile
        dx, dy := f64(to.x) / tile - ax, f64(to.y) / tile - ay
        clear, reach = true, 1
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                if !grid.opaque[y * grid.width + x] { continue }
                entry, touches := segment_reaches_cell(ax, ay, dx, dy, f64(x), f64(y))
                if touches { clear = false; reach = min(reach, entry) }
            }
        }
        return
    }
    extent := f32(grid.width) * grid.tile_size
    for i in 0..<4000 {
        // Mix free coordinates with ones snapped to grid lines and cell centers.
        coordinate :: proc(state: ^u64, extent: f32) -> f32 {
            raw := f32(next(state) % 10000) / 10000 * extent
            switch next(state) % 3 {
            case 0: return raw
            case 1: return f32(math.floor(f64(raw / 32))) * 32
            }
            return f32(math.floor(f64(raw / 32))) * 32 + 16
        }
        from := obs.Vector{coordinate(&state, extent), coordinate(&state, extent)}
        to := obs.Vector{coordinate(&state, extent), coordinate(&state, extent)}
        want_clear, want_reach := exhaustive(grid, from, to)
        got_clear, got_reach := sight_probe(grid, from, to)
        testing.expectf(t, got_clear == want_clear && abs(f64(got_reach) - want_reach) < 1e-6,
            "segment %d %v -> %v: sweep clear=%v reach=%v, exhaustive clear=%v reach=%v", i, from, to, got_clear, got_reach, want_clear, want_reach)
    }
}

// The accepted envelope: the largest map, the smallest tile and the longest range.
@(test)
accepted_envelope_is_visible_bounded_and_measured :: proc(t: ^testing.T) {
    grid := Opacity_Grid{width = MAX_GRID_SIDE, height = MAX_GRID_SIDE, tile_size = 16}
    grid.opaque = make([]bool, grid.width * grid.height)
    defer delete(grid.opaque)
    state: u64 = 12345
    for i in 0..<len(grid.opaque) {
        state = state * 6364136223846793005 + 1442695040888963407
        grid.opaque[i] = (state >> 33) % 5 == 0 // one cell in five blocks sight
    }
    profile := starter()
    profile.range = MAX_RANGE_GAMEPLAY_UNITS * WORLD_UNITS_PER_GAMEPLAY_UNIT
    testing.expect(t, vision_profile_valid(profile))
    eye := obs.Vector{8, 8}
    far := obs.Vector{1448, 1448} // about 2,036 units away, inside the 2,048 range
    // Empty lane along the diagonal: the subject must be seen at the far end.
    for i in 0..<MAX_GRID_SIDE { grid.opaque[i * grid.width + i] = false }
    for y in 0..<MAX_GRID_SIDE { for x in 0..<MAX_GRID_SIDE { if abs(x - y) == 1 { grid.opaque[y * grid.width + x] = false } } }
    query := query_with(grid, eye, .South_East, {far, {1000, 1000}, {far.x, 8}}, profile)
    sample, audit := vision_sample(query, 1, 1, 1)
    testing.expectf(t, audit.candidates[0].verdict == .Focused && audit.candidates[1].verdict == .Focused, "long clear rays: %v %v", audit.candidates[0].verdict, audit.candidates[1].verdict)
    testing.expect(t, sample.focused_count == 2 && sample.focused[0].position == far)
    testing.expect(t, audit.candidates[2].verdict == .Outside_Field || audit.candidates[2].verdict == .Occluded)
    fan: [FAN_RAYS]obs.Vector
    testing.expect(t, vision_fan(grid, {eye, .South_East}, profile, &fan) == FAN_RAYS)
    for point in fan { testing.expect(t, grid_contains_point(grid, point)) }
    // Worst supported single sample and fan, measured on the scattered-cover grid.
    started := time.tick_now()
    for i in 0..<1000 { sample, audit = vision_sample(query, u32(i), u32(i), u32(i)) }
    per_sample := time.tick_since(started) / 1000
    started = time.tick_now()
    for _ in 0..<20 { vision_fan(grid, {eye, .South_East}, profile, &fan) }
    per_fan := time.tick_since(started) / 20
    testing.expect(t, per_sample < 2 * time.Millisecond && per_fan < 50 * time.Millisecond, "worst supported workload is not small")
    fmt.printf("[perception] worst supported envelope: 128x128 map, 16-unit tiles, 2048-unit range: %v per 3-candidate sample, %v per 65-ray fan\n", per_sample, per_fan)
}

@(test)
peripheral_precision_is_coarse_deduplicated_and_position_invariant :: proc(t: ^testing.T) {
    grid := open_grid(40)
    defer delete(grid.opaque)
    eye := obs.Vector{640, 640}
    // Two subjects in the same sector and band become one anonymous cue.
    query := query_with(grid, eye, .North, {eye + offset_at(.North, 50, 100), eye + offset_at(.North, 40, 60), eye + offset_at(.North, -60, 200)})
    sample, audit := vision_sample(query, 9, 300, 300)
    testing.expect(t, sample.focused_count == 0 && sample.cue_count == 2 && audit.merged_cues == 1)
    testing.expect(t, sample.cues[0].sector == 1 && sample.cues[0].band == .Near && sample.cues[1].sector == 7 && sample.cues[1].band == .Far)
    testing.expect(t, sample.cues[0].observation_id == 9 * 8 + 1 && sample.cues[1].observation_id == 9 * 8 + 2)
    // Different exact positions with equal quantized evidence deliver identical samples.
    a := query_with(grid, eye, .North, {eye + offset_at(.North, 35, 70)})
    b := query_with(grid, eye, .North, {eye + offset_at(.North, 66, 127)})
    sa, _ := vision_sample(a, 4, 40, 40)
    sb, _ := vision_sample(b, 4, 40, 40)
    testing.expect(t, sa == sb && sa.cue_count == 1 && sa.cues[0].sector == 1 && sa.cues[0].band == .Near)
    // Band boundary: exactly R/2 is Near, just beyond is Far.
    near := query_with(grid, eye, .East, {eye + offset_at(.East, 45, 128)})
    far := query_with(grid, eye, .East, {eye + offset_at(.East, 45, 128.5)})
    sn, _ := vision_sample(near, 1, 1, 1)
    sf, _ := vision_sample(far, 1, 1, 1)
    testing.expect(t, sn.cues[0].band == .Near && sf.cues[0].band == .Far)
    // Losing focus removes current detail; the later sample carries only a cue.
    first := query_with(grid, eye, .East, {eye + offset_at(.East, 10, 100)})
    later := query_with(grid, eye, .East, {eye + offset_at(.East, 50, 100)})
    s1, _ := vision_sample(first, 1, 100, 100)
    s2, _ := vision_sample(later, 2, 106, 106)
    testing.expect(t, s1.focused_count == 1 && s2.focused_count == 0 && s2.cue_count == 1 && s2.focused[0] == obs.Focused_Sighting{})
    // Focused sightings keep candidate order; capacity holds three subjects.
    trio := query_with(grid, eye, .South, {eye + offset_at(.South, 5, 50), eye + offset_at(.South, -5, 90), eye + offset_at(.South, 0, 250)})
    s3, a3 := vision_sample(trio, 5, 500, 500)
    testing.expect(t, s3.focused_count == 3 && s3.focused[1].subject == 11 && s3.focused[2].kind == .Trainer && a3.sight_tests == 3)
}

@(test)
display_fan_is_bounded_clipped_and_off_the_brain_path :: proc(t: ^testing.T) {
    grid := make_grid({
        "............",
        "............",
        "............",
        "......###...",
        "............",
        "............",
        "............",
    })
    defer delete(grid.opaque)
    pose := obs.Pose{{80, 112}, .East}
    profile := starter()
    fan: [FAN_RAYS]obs.Vector
    count := vision_fan(grid, pose, profile, &fan)
    testing.expect(t, count == FAN_RAYS)
    shortened := 0
    for point in fan[:count] {
        d := point - pose.position
        distance := math.sqrt(d.x * d.x + d.y * d.y)
        testing.expect(t, distance <= profile.range + 0.01 && grid_contains_point(grid, point))
        if distance < profile.range - 1 { shortened += 1 }
    }
    testing.expect(t, shortened > 0 && shortened < count, "wall and map edge clip some rays, not all")
    testing.expect(t, vision_fan(grid, {{-5, 5}, .East}, profile, &fan) == 0)
    invalid := profile
    invalid.overall_fov_degrees = 400
    testing.expect(t, vision_fan(grid, pose, invalid, &fan) == 0)
}

@(test)
facing_helpers_are_deterministic_with_fixed_ties :: proc(t: ^testing.T) {
    testing.expect(t, obs.facing_step(.North, .South) == 4 && obs.facing_step(.South, .North) == 4)
    testing.expect(t, obs.facing_step(.North, .North_West) == -1 && obs.facing_step(.West, .East) == 4 && obs.facing_step(.East, .North_East) == -1)
    testing.expect(t, obs.facing_rotate(.North_West, 1) == .North && obs.facing_rotate(.North, -1) == .North_West)
    facing, ok := obs.facing_toward({0, 0}, {10, 10})
    testing.expect(t, ok && facing == .South_East)
    facing, ok = obs.facing_toward({0, 0}, {0, -3})
    testing.expect(t, ok && facing == .North)
    _, ok = obs.facing_toward({5, 5}, {5, 5})
    testing.expect(t, !ok)
    _, ok = obs.facing_toward({5, 5}, {math.nan_f32(), 5})
    testing.expect(t, !ok)
    testing.expect(t, obs.cue_absolute_facing(.East, 1) == .South_East && obs.cue_absolute_facing(.North, 7) == .North_West)
}
