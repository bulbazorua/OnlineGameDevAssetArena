package perception

import obs "../observations"
import "core:math"

@(private)
terrain_box_may_be_visible :: proc(eye, minimum, maximum: obs.Vector, edges: [2]obs.Vector, range: f32) -> bool {
    nearest := obs.Vector{clamp(eye.x, minimum.x, maximum.x), clamp(eye.y, minimum.y, maximum.y)}
    delta := nearest - eye
    padded_range := range + max(f32(0.02), range * 0.00001)
    if delta.x * delta.x + delta.y * delta.y > padded_range * padded_range { return false }
    center := (minimum + maximum) * 0.5 - eye
    half_size := (maximum - minimum) * 0.5
    // Leave a little room at the edges; the exact point tests decide what is seen.
    slack := range * BOUNDARY_TOLERANCE * 4 + 0.02
    for edge in edges {
        furthest := edge.x * center.x + edge.y * center.y + abs(edge.x) * half_size.x + abs(edge.y) * half_size.y
        if furthest < -slack { return false }
    }
    return true
}

@(private)
terrain_point_visible :: proc(query: ^Vision_Query, point, forward: obs.Vector, cos_field: f32, surface: bool) -> bool {
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
terrain_surface_visible :: proc(query: ^Vision_Query, minimum, maximum, forward: obs.Vector, cos_field: f32) -> bool {
    eye := query.observer.pose.position
    nearest := obs.Vector{clamp(eye.x, minimum.x, maximum.x), clamp(eye.y, minimum.y, maximum.y)}
    if terrain_point_visible(query, nearest, forward, cos_field, true) { return true }
    middle := (minimum + maximum) * 0.5
    points := [8]obs.Vector{
        minimum, {maximum.x, minimum.y}, maximum, {minimum.x, maximum.y},
        {middle.x, minimum.y}, {maximum.x, middle.y}, {middle.x, maximum.y}, {minimum.x, middle.y},
    }
    for point in points {
        if terrain_point_visible(query, point, forward, cos_field, true) { return true }
    }
    return false
}

// Visit tiles, not spaced camera rays, so a one-tile post gets its own test.
// Only a visible ground patch or obstacle face may disclose that tile's rule.
@(private)
vision_terrain :: proc(input: Vision_Query) -> (sample: obs.Terrain_Sample) {
    query := input
    if !grid_valid(query.grid) || len(query.terrain) != query.grid.width * query.grid.height { return }
    eye := query.observer.pose.position
    if !grid_contains_point(query.grid, eye) || grid_cell_opaque(query.grid, grid_cell_of(query.grid, eye)) { return }
    sample.valid, sample.tile_size = true, query.grid.tile_size
    sample.origin = grid_cell_of(query.grid, eye) - [2]int{obs.LOCAL_TERRAIN_SIDE / 2, obs.LOCAL_TERRAIN_SIDE / 2}
    forward := obs.facing_direction(query.observer.pose.facing)
    cos_field := f32(math.cos(f64(query.profile.overall_fov_degrees) * 0.5 * math.PI / 180))
    sin_field := math.sqrt(max(f32(0), 1 - cos_field * cos_field))
    sideways := obs.Vector{-forward.y, forward.x}
    edges := [2]obs.Vector{forward * sin_field + sideways * cos_field, forward * sin_field - sideways * cos_field}
    for y in 0..<obs.LOCAL_TERRAIN_SIDE {
        for x in 0..<obs.LOCAL_TERRAIN_SIDE {
            cell := sample.origin + [2]int{x, y}
            minimum := obs.Vector{f32(cell.x), f32(cell.y)} * sample.tile_size
            maximum := minimum + obs.Vector{sample.tile_size, sample.tile_size}
            if !terrain_box_may_be_visible(eye, minimum, maximum, edges, query.profile.range) { continue }
            outside := cell.x < 0 || cell.y < 0 || cell.x >= query.grid.width || cell.y >= query.grid.height
            value := obs.terrain_cell(.Solid) if outside else query.terrain[cell.y * query.grid.width + cell.x]
            surface := outside || grid_cell_opaque(query.grid, cell) || obs.terrain_state(value) == .Solid
            visible := false
            if surface {
                visible = terrain_surface_visible(&query, minimum, maximum, forward, cos_field)
            } else {
                nearest := obs.Vector{clamp(eye.x, minimum.x, maximum.x), clamp(eye.y, minimum.y, maximum.y)}
                visible = terrain_point_visible(&query, nearest, forward, cos_field, false) ||
                    terrain_point_visible(&query, (minimum + maximum) * 0.5, forward, cos_field, false)
            }
            if visible { sample.cells[y * obs.LOCAL_TERRAIN_SIDE + x] = value }
        }
    }
    return
}
