package perception

import obs "../observations"
import "core:testing"

@(private = "file")
terrain_test_query :: proc(opaque: []bool, terrain: []u8) -> Vision_Query {
    return {observer = {entity_id = 3, round_id = 1, pose = {{80, 104}, .East}},
        profile = {true, 160, 60, 160, 6},
        grid = {width = 13, height = 13, tile_size = 16, opaque = opaque}, terrain = terrain}
}

@(private = "file")
terrain_test_cell :: proc(sample: obs.Terrain_Sample, x, y: int) -> u8 {
    local := [2]int{x, y} - sample.origin
    if local.x < 0 || local.y < 0 || local.x >= obs.LOCAL_TERRAIN_SIDE || local.y >= obs.LOCAL_TERRAIN_SIDE { return 0 }
    return sample.cells[local.y * obs.LOCAL_TERRAIN_SIDE + local.x]
}

@(test)
terrain_eye_sees_post_surfaces_but_not_the_ground_hidden_behind_them :: proc(t: ^testing.T) {
    opaque: [169]bool
    terrain: [169]u8
    for &cell in terrain { cell = obs.terrain_cell(.Clear) }
    for y in 0..<13 {
        opaque[y * 13 + 7] = true
        terrain[y * 13 + 7] = obs.terrain_cell(.Solid)
    }
    query := terrain_test_query(opaque[:], terrain[:])
    sample, _ := vision_sample(query, 1, 0, 0)
    testing.expect(t, sample.terrain.valid)
    testing.expect(t, obs.terrain_state(terrain_test_cell(sample.terrain, 7, 6)) == .Solid, "the visible wall face was lost")
    testing.expect(t, obs.terrain_state(terrain_test_cell(sample.terrain, 9, 6)) == .Unknown, "hidden terrain leaked through the wall")
    testing.expect(t, obs.terrain_state(terrain_test_cell(sample.terrain, 3, 6)) == .Unknown, "terrain behind the eye was revealed")
    terrain[6 * 13 + 9] = obs.terrain_cell(.Solid, 3, true)
    hidden_changed, _ := vision_sample(query, 1, 0, 0)
    testing.expect(t, sample == hidden_changed, "unseen ground changed the delivered sample")
    query.profile.enabled = false
    disabled, _ := vision_sample(query, 2, 6, 6)
    testing.expect(t, !disabled.terrain.valid)
}

@(test)
terrain_eye_checks_each_small_post_and_keeps_sight_separate_from_walkability :: proc(t: ^testing.T) {
    opaque: [169]bool
    terrain: [169]u8
    for &cell in terrain { cell = obs.terrain_cell(.Clear) }
    query := terrain_test_query(opaque[:], terrain[:])
    for y in 2..=10 {
        opaque = {}
        for &cell in terrain { cell = obs.terrain_cell(.Clear) }
        opaque[y * 13 + 8] = true
        terrain[y * 13 + 8] = obs.terrain_cell(.Solid)
        sample, _ := vision_sample(query, 1, 0, 0)
        testing.expectf(t, obs.terrain_state(terrain_test_cell(sample.terrain, 8, y)) == .Solid, "missed the one-tile post at row %d", y)
    }
    opaque = {}
    terrain[6 * 13 + 8] = obs.terrain_cell(.Solid)
    water, _ := vision_sample(query, 2, 6, 6)
    testing.expect(t, obs.terrain_state(terrain_test_cell(water.terrain, 8, 6)) == .Solid, "see-through does not mean walkable")
    opaque[6 * 13 + 8] = true
    terrain[6 * 13 + 8] = obs.terrain_cell(.Clear, 1, true)
    foliage, _ := vision_sample(query, 3, 12, 12)
    seen := terrain_test_cell(foliage.terrain, 8, 6)
    testing.expect(t, obs.terrain_state(seen) == .Clear && obs.terrain_elevation(seen) == 1 && obs.terrain_has_stairs(seen))
}
