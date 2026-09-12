package perception

import obs "../observations"
import "core:math"
import "core:testing"
import "core:fmt"
import "core:time"

@(private)
reference_terrain_point_visible :: proc(query: ^Vision_Query, point, forward: obs.Vector, cos_field: f32, surface: bool) -> bool {
    eye := query.observer.pose.position
    delta := point - eye
    distance := math.sqrt(delta.x * delta.x + delta.y * delta.y)
    if distance > query.profile.range + BOUNDARY_TOLERANCE { return false }
    if distance < 0.001 { return true }
    if (delta.x * forward.x + delta.y * forward.y) / distance < cos_field - BOUNDARY_TOLERANCE { return false }
    target := point
    // Stop just in front of a wall face; the wall itself must not hide its face.
    if surface { target -= delta * (min(f32(0.02), distance * 0.5) / distance) }
    return line_of_sight(query.grid, eye, target)
}

@(private)
reference_terrain_surface_visible :: proc(query: ^Vision_Query, minimum, maximum, forward: obs.Vector, cos_field: f32) -> bool {
    eye := query.observer.pose.position
    nearest := obs.Vector{clamp(eye.x, minimum.x, maximum.x), clamp(eye.y, minimum.y, maximum.y)}
    if reference_terrain_point_visible(query, nearest, forward, cos_field, true) { return true }
    middle := (minimum + maximum) * 0.5
    points := [8]obs.Vector{
        minimum, {maximum.x, minimum.y}, maximum, {minimum.x, maximum.y},
        {middle.x, minimum.y}, {maximum.x, middle.y}, {middle.x, maximum.y}, {minimum.x, middle.y},
    }
    for point in points {
        if reference_terrain_point_visible(query, point, forward, cos_field, true) { return true }
    }
    return false
}

// Visit tiles, not spaced camera rays, so a one-tile post gets its own test.
// Only a visible ground patch or obstacle face may disclose that tile's rule.
@(private)
reference_vision_terrain :: proc(input: Vision_Query) -> (sample: obs.Terrain_Sample) {
    query := input
    if !grid_valid(query.grid) || len(query.terrain) != query.grid.width * query.grid.height { return }
    eye := query.observer.pose.position
    if !grid_contains_point(query.grid, eye) || grid_cell_opaque(query.grid, grid_cell_of(query.grid, eye)) { return }
    sample.valid, sample.tile_size = true, query.grid.tile_size
    sample.origin = grid_cell_of(query.grid, eye) - [2]int{obs.LOCAL_TERRAIN_SIDE / 2, obs.LOCAL_TERRAIN_SIDE / 2}
    forward := obs.facing_direction(query.observer.pose.facing)
    cos_field := f32(math.cos(f64(query.profile.overall_fov_degrees) * 0.5 * math.PI / 180))
    for y in 0..<obs.LOCAL_TERRAIN_SIDE {
        for x in 0..<obs.LOCAL_TERRAIN_SIDE {
            cell := sample.origin + [2]int{x, y}
            minimum := obs.Vector{f32(cell.x), f32(cell.y)} * sample.tile_size
            maximum := minimum + obs.Vector{sample.tile_size, sample.tile_size}
            outside := cell.x < 0 || cell.y < 0 || cell.x >= query.grid.width || cell.y >= query.grid.height
            value := obs.terrain_cell(.Solid) if outside else query.terrain[cell.y * query.grid.width + cell.x]
            surface := outside || grid_cell_opaque(query.grid, cell) || obs.terrain_state(value) == .Solid
            visible := false
            if surface {
                visible = reference_terrain_surface_visible(&query, minimum, maximum, forward, cos_field)
            } else {
                nearest := obs.Vector{clamp(eye.x, minimum.x, maximum.x), clamp(eye.y, minimum.y, maximum.y)}
                visible = reference_terrain_point_visible(&query, nearest, forward, cos_field, false) ||
                    reference_terrain_point_visible(&query, (minimum + maximum) * 0.5, forward, cos_field, false)
            }
            if visible { sample.cells[y * obs.LOCAL_TERRAIN_SIDE + x] = value }
        }
    }
    return
}

// Keep the sampler above frozen: optimizations must deliver the same geometry.
@(private = "file")
optimization_terrain_query :: proc(opaque: []bool, cells: []u8) -> Vision_Query {
    return {observer = {entity_id = 3, round_id = 1, pose = {{104, 104}, .East}},
        profile = {true, 160, 60, 160, 6},
        grid = {width = 13, height = 13, tile_size = 16, opaque = opaque}, terrain = cells, terrain_revision = 1}
}

@(test)
terrain_optimization_preserves_uncached_samples_and_invalidates_owned_caches :: proc(t: ^testing.T) {
    opaque: [169]bool
    cells: [169]u8
    for &cell, index in cells {
        cell = obs.terrain_cell(.Clear)
        if index % 11 == 0 { cell = obs.terrain_cell(.Solid); opaque[index] = true }
    }
    for y in 3..=9 {
        for x in 3..=9 {
            if opaque[y * 13 + x] { continue }
            for facing in obs.Facing {
                query := optimization_terrain_query(opaque[:], cells[:])
                query.observer.pose = {{(f32(x) + 0.25) * 16, (f32(y) + 0.75) * 16}, facing}
                expected := reference_vision_terrain(query)
                first, _ := vision_sample(query, 1, 1, 1)
                testing.expect(t, first.terrain == expected, "a broad-phase shortcut changed visible terrain")
                cache: Terrain_Cache
                cached, _ := vision_sample(query, 1, 1, 1, &cache)
                retained, _ := vision_sample(query, 2, 7, 7, &cache)
                testing.expect(t, cached == first && retained.terrain == expected && cache.builds == 1 && cache.hits == 1)
            }
        }
    }
    opaque = {}
    for &cell in cells { cell = obs.terrain_cell(.Clear) }
    query := optimization_terrain_query(opaque[:], cells[:])
    cache: Terrain_Cache
    first, _ := vision_sample(query, 1, 1, 1, &cache)
    query.candidate_count = 1
    query.candidates[0] = {entity_id = 9, kind = .Creature, position = {128, 104}}
    moving_subject, _ := vision_sample(query, 2, 7, 7, &cache)
    testing.expect(t, cache.hits == 1 && moving_subject.focused_count == 1 && moving_subject.terrain == first.terrain)
    query.observer.pose.position.x += 1
    vision_sample(query, 3, 13, 13, &cache)
    testing.expect(t, cache.builds == 2)
    query.observer.pose.facing = .North
    vision_sample(query, 4, 19, 19, &cache)
    testing.expect(t, cache.builds == 3)
    query.profile.range = 128
    vision_sample(query, 5, 25, 25, &cache)
    testing.expect(t, cache.builds == 4)
    query.observer.pose.facing = .East
    cells[6 * 13 + 8] = obs.terrain_cell(.Solid)
    opaque[6 * 13 + 8] = true
    query.terrain_revision += 1
    changed, _ := vision_sample(query, 6, 31, 31, &cache)
    testing.expect(t, changed.terrain == reference_vision_terrain(query) && cache.builds == 5)
    other: Terrain_Cache
    query.observer.pose.facing = .West
    vision_sample(query, 7, 37, 37, &other)
    testing.expect(t, other.builds == 1 && cache.builds == 5 && cache.pose.facing == .East)
}

@(test)
visibility_short_circuit_matches_the_nearest_hit_query :: proc(t: ^testing.T) {
    opaque: [169]bool
    for &cell, index in opaque { cell = index % 7 == 0 || index % 13 == 12 }
    grid := Opacity_Grid{width = 13, height = 13, tile_size = 16, opaque = opaque[:]}
    for index in 0..<2000 {
        a := obs.Vector{f32((index * 17) % 211) - 1, f32((index * 31) % 211) - 1}
        b := obs.Vector{f32((index * 43) % 211) - 1, f32((index * 13) % 211) - 1}
        expected, _ := sight_probe(grid, a, b)
        testing.expect(t, line_of_sight(grid, a, b) == expected)
    }
}

@(test)
terrain_stationary_cache_cost_is_measured_without_skipping_samples :: proc(t: ^testing.T) {
    opaque: [169]bool
    cells: [169]u8
    for &cell, index in cells {
        cell = obs.terrain_cell(.Clear)
        if index % 13 == 9 { opaque[index] = true; cell = obs.terrain_cell(.Solid) }
    }
    query := optimization_terrain_query(opaque[:], cells[:])
    cache: Terrain_Cache
    started := time.tick_now()
    for tick in u32(1)..=1200 {
        sample, _ := vision_sample(query, tick, tick * 6, tick * 6, &cache)
        testing.expect(t, sample.sample_id == tick && sample.sample_tick == tick * 6)
    }
    elapsed := time.tick_since(started)
    fmt.printfln("[terrain cache] 1200 real eye samples: %v; builds=%d, hits=%d", elapsed, cache.builds, cache.hits)
    testing.expect(t, cache.builds == 1 && cache.hits == 1199)
}

@(test)
terrain_broad_phase_preserves_small_ranges_and_field_edges :: proc(t: ^testing.T) {
    opaque: [169]bool
    cells: [169]u8
    for &cell, index in cells {
        cell = obs.terrain_cell(.Solid) if index % 5 == 0 else obs.terrain_cell(.Clear)
        opaque[index] = index % 5 == 0
    }
    for field in ([5]f32{46, 60, 90, 160, 180}) {
        for range in ([4]f32{16, 48, 160, 2048}) {
            for facing in obs.Facing {
                for position in ([4]obs.Vector{{104, 104}, {96.00001, 95.99999}, {16, 16}, {192, 192}}) {
                    query := optimization_terrain_query(opaque[:], cells[:])
                    query.profile.focused_fov_degrees, query.profile.overall_fov_degrees = 45, field
                    query.profile.range = range
                    query.observer.pose = {position, facing}
                    sample, _ := vision_sample(query, 1, 1, 1)
                    testing.expect(t, sample.terrain == reference_vision_terrain(query), "range or field-edge shortcut hid a visible cell")
                }
            }
        }
    }
}
