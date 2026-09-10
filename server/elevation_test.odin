package main

import "core:testing"
import "core:fmt"

@(test)
land_arenas_are_large_connected_and_have_accessible_high_ground :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "client/content/data"))
    defer content_destroy(&content)
    for &arena in content.arenas {
        testing.expect(t, arena.width == 60 && arena.height == 28 && arena.tile_size == 32)
        visited := make([]bool, len(arena.cells))
        defer delete(visited)
        queue: [dynamic][2]int
        defer delete(queue)
        append(&queue, arena.spawns[0])
        visited[arena.spawns[0].y * arena.width + arena.spawns[0].x] = true
        for index := 0; index < len(queue); index += 1 {
            current := queue[index]
            for offset in ([4][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
                next := current + offset
                if !arena_spawn_is_clear(&arena, &content, next, 12) { continue }
                if !arena_step_is_allowed(&arena, &content, arena_cell_center(&arena, current), arena_cell_center(&arena, next)) { continue }
                flat := next.y * arena.width + next.x
                if !visited[flat] { visited[flat] = true; append(&queue, next) }
            }
        }
        walkable, water, grass, high := 0, 0, 0, 0
        for id, index in arena.cells {
            terrain := content_terrain(&content, id)
            if terrain.walkable {
                walkable += 1
                if arena.elevations[index] > 0 { high += 1 }
            }
            if terrain.key == "water" { water += 1 }
            if terrain.key == "grass" || terrain.key == "tall_grass" { grass += 1 }
        }
        testing.expect(t, water * 10 < len(arena.cells))
        testing.expect(t, walkable * 100 >= len(arena.cells) * 65 && grass * 2 > walkable)
        testing.expect(t, high > 25 && len(queue) == walkable, arena.key)
    }
}

@(test)
elevation_changes_require_stairs_in_both_directions :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_load(&content, "tests/fixtures/content"))
    defer content_destroy(&content)
    arena := content_arena(&content, 1)
    arena.elevations[6] = 1 // Adjacent walkable cell (2,1).
    testing.expect(t, !arena_step_is_allowed(arena, &content, {48,48}, {80,48}))
    testing.expect(t, character_move({63,48}, 2, 12, arena, &content) == [2]f32{63,48})
    // Reuse one fixture terrain as a stair; the owned key is restored afterward.
    terrain := content_terrain(&content, arena.cells[6])
    previous := terrain.key
    terrain.key = "stairs"
    testing.expect(t, arena_step_is_allowed(arena, &content, {48,48}, {80,48}))
    testing.expect(t, arena_step_is_allowed(arena, &content, {80,48}, {48,48}))
    testing.expect(t, character_move({63,48}, 2, 12, arena, &content) == [2]f32{66,48})
    arena.elevations[6] = 2
    testing.expect(t, !arena_step_is_allowed(arena, &content, {48,48}, {80,48}))
    terrain.key = previous
}

@(test)
elevation_rows_reject_invalid_shape_and_values :: proc(t: ^testing.T) {
    for rows in ([]string{`null`, `["0000"]`, `["0000","000","0000"]`, `["0000","0040","0000"]`, `["0000","00x0","0000"]`, `["0000",12,"0000"]`}) {
        content: Game_Content
        testing.expect(t, content_load(&content, "tests/fixtures/content"))
        // Loading a second uniquely identified candidate also exercises cleanup.
        candidate := fmt.aprintf(`{"schema_version":2,"arenas":[{"id":2,"key":"height_test","display_name":"Height test","width":4,"height":3,"tile_size":32,"rows":["####","#..#","####"],"elevation_rows":%s,"spawns":[[1,1],[2,1]]}]}`, rows)
        testing.expect(t, !content_parse_extra(&content, transmute([]u8)candidate, .Arenas))
        delete(candidate)
        content_destroy(&content)
    }
}
