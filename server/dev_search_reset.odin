package main

import "core:fmt"
import "core:math"

Dev_Search_Spawn :: struct { creature, trainer: [2]f32 }
DEV_SEARCH_NEIGHBORS :: [4][2]int{{1, 0}, {0, 1}, {-1, 0}, {0, -1}}

dev_search_reset :: proc(session: ^Session, content: ^Game_Content, enabled: bool) -> (bool, Command_Reject_Reason) {
    when !ODIN_DEBUG { return false, .Dev_Only }
    if !enabled { return false, .Dev_Only }
    if session.phase != .In_Arena || session.summon_elapsed_ticks < SUMMON_DURATION_TICKS { return false, .Wrong_Phase }
    placements, valid := dev_search_reset_placements(session, content)
    if !valid { return false, .Search_Reset_Unavailable }
    session.round_id += 1
    session.revision += 1
    session_enter_arena(session, content)
    for placement, index in placements {
        session.characters[index].position = placement.creature
        session.trainers[index].position = placement.trainer
    }
    distance := math.sqrt(dev_search_distance_squared(placements[0].creature, placements[1].creature))
    fmt.printfln("[dev] Search reset: round=%d, creature positions=%v / %v, separation=%.1f; fresh memories on next simulation tick.", session.round_id, placements[0].creature, placements[1].creature, distance)
    return true, .None
}

dev_search_distance_squared :: proc(a, b: [2]f32) -> f32 {
    delta := a - b
    return delta.x * delta.x + delta.y * delta.y
}

// Spawn checks belong to the host; no map or route is sent to a brain.
dev_search_reset_placements :: proc(session: ^Session, content: ^Game_Content) -> (result: [2]Dev_Search_Spawn, valid: bool) {
    arena := content_arena(content, session.map_id)
    if arena == nil { return }
    radius, vision_range := TRAINER_RADIUS, f32(0)
    for player in session.players {
        definition := content_character(content, player.character_id)
        if definition == nil { return }
        radius = max(radius, definition.footprint_radius)
        if definition.vision.enabled { vision_range = max(vision_range, definition.vision.range) }
    }
    reachable := dev_search_reset_reachable(arena, content, radius)
    defer delete(reachable)
    candidates := make([dynamic]Dev_Search_Spawn)
    defer delete(candidates)
    for reached, index in reachable {
        if !reached { continue }
        cell := [2]int{index % arena.width, index / arena.width}
        if candidate, fits := dev_search_reset_spawn(arena, content, reachable, cell, radius); fits { append(&candidates, candidate) }
    }
    if len(candidates) < 2 { return }
    origin := arena_cell_center(arena, arena.spawns[0])
    result[1] = dev_search_reset_farthest(candidates[:], origin)
    result[0] = dev_search_reset_farthest(candidates[:], result[1].creature)
    if dev_search_distance_squared(result[1].creature, origin) < dev_search_distance_squared(result[0].creature, origin) { result[0], result[1] = result[1], result[0] }
    separation := max(vision_range * 1.5, f32(arena.tile_size * 4)) + radius * 2
    if dev_search_distance_squared(result[0].creature, result[1].creature) < separation * separation { return }
    for placement, index in result {
        other := result[1 - index]
        safe_distance := vision_range + radius + f32(arena.tile_size * 2)
        if dev_search_distance_squared(placement.creature, other.trainer) <= safe_distance * safe_distance { return }
        if dev_search_distance_squared(placement.trainer, other.trainer) <= 4 * TRAINER_RADIUS * TRAINER_RADIUS { return }
    }
    return result, true
}

dev_search_reset_farthest :: proc(candidates: []Dev_Search_Spawn, origin: [2]f32) -> Dev_Search_Spawn {
    best := candidates[0]
    for candidate in candidates[1:] {
        if dev_search_distance_squared(candidate.creature, origin) > dev_search_distance_squared(best.creature, origin) { best = candidate }
    }
    return best
}

dev_search_reset_spawn :: proc(arena: ^Arena_Definition, content: ^Game_Content, reachable: []bool, cell: [2]int, radius: f32) -> (Dev_Search_Spawn, bool) {
    position := arena_cell_center(arena, cell)
    distance := int(math.ceil((radius + TRAINER_RADIUS + 8) / f32(arena.tile_size)))
    for offset in ([4][2]int{{0, 1}, {0, -1}, {-1, 0}, {1, 0}}) {
        neighbor := cell + offset * distance
        if neighbor.x < 0 || neighbor.y < 0 || neighbor.x >= arena.width || neighbor.y >= arena.height { continue }
        if !reachable[neighbor.y * arena.width + neighbor.x] || !arena_spawn_is_clear(arena, content, neighbor, TRAINER_RADIUS) { continue }
        trainer := arena_cell_center(arena, neighbor)
        if arena_elevation_at(arena, cell) != arena_elevation_at(arena, neighbor) { continue }
        return {position, trainer}, true
    }
    return {}, false
}

// Only use connected ground, so a reset cannot strand opponents on separate islands.
dev_search_reset_reachable :: proc(arena: ^Arena_Definition, content: ^Game_Content, radius: f32) -> []bool {
    reached := make([]bool, arena.width * arena.height)
    queue := make([dynamic][2]int)
    defer delete(queue)
    first := arena.spawns[0]
    if !arena_spawn_is_clear(arena, content, first, radius) { return reached }
    reached[first.y * arena.width + first.x] = true
    append(&queue, first)
    for index := 0; index < len(queue); index += 1 {
        cell := queue[index]
        from := arena_cell_center(arena, cell)
        for offset in DEV_SEARCH_NEIGHBORS {
            neighbor := cell + offset
            if neighbor.x < 0 || neighbor.y < 0 || neighbor.x >= arena.width || neighbor.y >= arena.height { continue }
            next := neighbor.y * arena.width + neighbor.x
            if reached[next] || !arena_spawn_is_clear(arena, content, neighbor, radius) { continue }
            to := arena_cell_center(arena, neighbor)
            if !arena_position_is_clear(arena, content, (from + to) * 0.5, radius) || !arena_step_is_allowed(arena, content, from, to) { continue }
            reached[next] = true
            append(&queue, neighbor)
        }
    }
    return reached
}
