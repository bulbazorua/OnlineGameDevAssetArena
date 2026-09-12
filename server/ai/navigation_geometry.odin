package ai

import obs "../observations"
import "core:math"

// These tests sweep the whole round body, including rounded corners.
// A tangent touch is allowed, just as it is in the movement resolver.
@(private)
navigation_box_contact :: proc(origin, direction, minimum, maximum: Vector, limit: f32) -> f32 {
    enter, leave := f32(0), limit
    for axis in 0..<2 {
        if abs(direction[axis]) < 0.000001 {
            if origin[axis] <= minimum[axis] || origin[axis] >= maximum[axis] { return limit }
            continue
        }
        a := (minimum[axis] - origin[axis]) / direction[axis]
        b := (maximum[axis] - origin[axis]) / direction[axis]
        if a > b { a, b = b, a }
        enter, leave = max(enter, a), min(leave, b)
        if enter >= leave { return limit }
    }
    return enter if leave > 0 else limit
}

@(private)
navigation_circle_contact :: proc(origin, direction, center: Vector, radius, limit: f32) -> f32 {
    offset := origin - center
    along := search_alignment(offset, direction)
    discriminant := along * along - (search_alignment(offset, offset) - radius * radius)
    if discriminant <= 0 { return limit }
    root := math.sqrt(discriminant)
    if -along + root <= 0 { return limit }
    return min(limit, max(0, -along - root))
}

@(private)
navigation_cell_contact :: proc(origin, direction, minimum: Vector, tile, radius, limit: f32) -> f32 {
    maximum := minimum + Vector{tile, tile}
    hit := navigation_box_contact(origin, direction, minimum - Vector{radius, 0}, maximum + Vector{radius, 0}, limit)
    hit = min(hit, navigation_box_contact(origin, direction, minimum - Vector{0, radius}, maximum + Vector{0, radius}, limit))
    for corner in ([4]Vector{minimum, {maximum.x, minimum.y}, maximum, {minimum.x, maximum.y}}) {
        hit = min(hit, navigation_circle_contact(origin, direction, corner, radius, limit))
    }
    return hit
}

// The resolver moves X, then Y. Check that small corner-shaped step too.
@(private)
navigation_axis_step_clear :: proc(origin, direction, corner: Vector, tile, radius, step: f32) -> bool {
    delta := direction * step
    if abs(delta.x) > 0.000001 {
        along := Vector{1 if delta.x > 0 else -1, 0}
        if navigation_cell_contact(origin, along, corner, tile, radius, abs(delta.x)) < abs(delta.x) - 0.000001 { return false }
    }
    if abs(delta.y) > 0.000001 {
        along := Vector{0, 1 if delta.y > 0 else -1}
        if navigation_cell_contact(origin + Vector{delta.x, 0}, along, corner, tile, radius, abs(delta.y)) < abs(delta.y) - 0.000001 { return false }
    }
    return true
}

@(private)
navigation_step_clearance :: proc(nav: ^Navigation_Runtime, ctx: Decision_Context, direction: Vector, limit: f32) -> f32 {
    tile := nav.memory.tile_size
    previous := navigation_known_cell(nav, search_region(ctx.position, tile), ctx.tick)
    steps := max(1, int(math.ceil(limit / (tile * 0.25))))
    for index in 1..=steps {
        distance := limit * f32(index) / f32(steps)
        next := navigation_known_cell(nav, search_region(ctx.position + direction * distance, tile), ctx.tick)
        if obs.terrain_state(previous) != .Unknown && obs.terrain_state(next) != .Unknown {
            change := abs(int(obs.terrain_elevation(previous)) - int(obs.terrain_elevation(next)))
            if change > 0 && !(change == 1 && (obs.terrain_has_stairs(previous) || obs.terrain_has_stairs(next))) {
                return max(0, distance - limit / f32(steps))
            }
        }
        previous = next
    }
    return limit
}

@(private)
navigation_passage :: proc(nav: ^Navigation_Runtime, ctx: Decision_Context, direction: Vector, limit, comfort: f32) -> (choice: Passage) {
    choice.direction, choice.clearance, choice.unknown_at = direction, limit, limit
    if !nav.memory.valid {
        choice.uncertain, choice.unknown_at = true, 0
        return
    }
    tile := nav.memory.tile_size
    radius := ctx.motion.footprint_radius
    end := ctx.position + direction * limit
    minimum := search_region(Vector{min(ctx.position.x, end.x), min(ctx.position.y, end.y)} - Vector{radius, radius}, tile)
    maximum := search_region(Vector{max(ctx.position.x, end.x), max(ctx.position.y, end.y)} + Vector{radius, radius}, tile)
    for y in minimum.y..=maximum.y {
        for x in minimum.x..=maximum.x {
            cell := navigation_known_cell(nav, {x, y}, ctx.tick)
            state := obs.terrain_state(cell)
            if state == .Clear { continue }
            corner := Vector{f32(x), f32(y)} * tile
            hit := navigation_cell_contact(ctx.position, direction, corner, tile, radius, limit)
            if state == .Unknown {
                if hit < limit {
                    choice.uncertain = true
                    choice.unknown_at = min(choice.unknown_at, hit)
                }
                continue
            }
            choice.clearance = min(choice.clearance, hit)
            if !navigation_axis_step_clear(ctx.position, direction, corner, tile, radius, min(limit, ctx.motion.maximum_speed * ctx.motion.tick_seconds)) { choice.clearance = 0 }
            comfortable := navigation_cell_contact(ctx.position, direction, corner, tile, radius + comfort, limit)
            choice.pressure = max(choice.pressure, (limit - comfortable) / max(limit, 0.001))
        }
    }
    if choice.clearance < limit - 0.001 { choice.rejection = .Solid }
    step := navigation_step_clearance(nav, ctx, direction, limit)
    if step < choice.clearance - 0.001 { choice.clearance, choice.rejection = step, .Step }
    return
}
