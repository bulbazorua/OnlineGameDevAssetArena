package content

import "core:testing"
import "core:fmt"

@(test)
land_arenas_are_large_connected_and_have_accessible_high_ground :: proc(t: ^testing.T) {
    catalog: Game_Content
    testing.expect(t, load(&catalog, "client/content/data"))
    defer destroy(&catalog)
    for &arena in catalog.arenas {
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
                if !arena_spawn_is_clear(&arena, &catalog, next, 12) { continue }
                if !arena_step_is_allowed(&arena, &catalog, arena_cell_center(&arena, current), arena_cell_center(&arena, next)) { continue }
                flat := next.y * arena.width + next.x
                if !visited[flat] { visited[flat] = true; append(&queue, next) }
            }
        }
        walkable, water, grass, high := 0, 0, 0, 0
        for id, index in arena.cells {
            terrain := find_terrain(&catalog, id)
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
elevation_rows_reject_invalid_shape_and_values :: proc(t: ^testing.T) {
    for rows in ([]string{`null`, `["0000"]`, `["0000","000","0000"]`, `["0000","0040","0000"]`, `["0000","00x0","0000"]`, `["0000",12,"0000"]`}) {
        catalog: Game_Content
        testing.expect(t, load(&catalog, "tests/fixtures/content"))
        // Loading a second uniquely identified candidate also exercises cleanup.
        candidate := fmt.aprintf(`{"schema_version":2,"arenas":[{"id":2,"key":"height_test","display_name":"Height test","width":4,"height":3,"tile_size":32,"rows":["####","#..#","####"],"elevation_rows":%s,"spawns":[[1,1],[2,1]]}]}`, rows)
        testing.expect(t, !parse_extra(&catalog, transmute([]u8)candidate, .Arenas))
        delete(candidate)
        destroy(&catalog)
    }
}
