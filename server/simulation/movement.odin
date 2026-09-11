package simulation

import "core:math"
import "../content"

CHARACTER_SPEED :: f32(120)

@(private)
character_move :: proc(position: [2]f32, mask: u8, radius: f32, arena: ^content.Arena_Definition, catalog: ^content.Game_Content, speed: f32 = CHARACTER_SPEED) -> [2]f32 {
    direction := [2]f32{f32((mask >> 1) & 1) - f32(mask & 1), f32((mask >> 3) & 1) - f32((mask >> 2) & 1)}
    length := math.sqrt(direction.x * direction.x + direction.y * direction.y)
    if length == 0 { return position }
    delta := direction * (speed / SIMULATION_HZ / length)
    result, _ := movement_apply_delta(position, delta, radius, arena, catalog)
    return result
}

// Shared terrain mechanics. Trainers and autonomous characters supply their own speed.
@(private)
movement_apply_delta :: proc(position, delta: [2]f32, radius: f32, arena: ^content.Arena_Definition, catalog: ^content.Game_Content) -> (result: [2]f32, blocked: bool) {
    result = position
    // Axis separation lets characters slide along walls.
    candidate := result + [2]f32{delta.x, 0}
    if content.arena_position_is_clear(arena, catalog, candidate, radius) && content.arena_step_is_allowed(arena, catalog, result, candidate) { result = candidate } else if delta.x != 0 { blocked = true }
    candidate = result + [2]f32{0, delta.y}
    if content.arena_position_is_clear(arena, catalog, candidate, radius) && content.arena_step_is_allowed(arena, catalog, result, candidate) { result = candidate } else if delta.y != 0 { blocked = true }
    return
}
