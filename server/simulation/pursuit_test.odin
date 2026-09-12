package simulation

import ai "../ai"
import obs "../observations"
import "../content"
import "core:fmt"
import "core:math"
import "core:testing"

@(private = "file")
pursuit_test_scenario :: proc(t: ^testing.T, catalog: ^content.Game_Content, post: bool) -> Simulation {
    testing.expect(t, content.load(catalog, "client/content/data"))
    arena := &catalog.arenas[0]
    floor, wall := u16(0), u16(0)
    for terrain in catalog.terrains {
        if terrain.walkable && !terrain.blocks_vision { floor = terrain.id }
        if !terrain.walkable && terrain.blocks_vision { wall = terrain.id }
    }
    testing.expect(t, floor != 0 && wall != 0 && arena.width > 20 && arena.height > 12)
    for &cell in arena.cells { cell = floor }
    for &height in arena.elevations { height = 0 }
    if post { arena.cells[10 * arena.width + 11] = wall }
    content.arena_refresh_rules(arena, catalog)
    sim := battle_test_scenario(catalog, arena.id, 5, 42)
    sim.observe_only = false
    sim.session.summon_elapsed_ticks = SUMMON_DURATION_TICKS
    tile := f32(arena.tile_size)
    sim.session.characters[0].position, sim.session.characters[0].facing = {9.5 * tile, 10.5 * tile}, .East
    sim.session.characters[1].position, sim.session.characters[1].facing = {15.5 * tile, 7.5 * tile}, .West
    battle_sync(&sim.battle, &sim.session, catalog, 42, .Search)
    sim.battle.agents[1].controller = .Observe
    return sim
}

@(test)
pursuit_uses_real_eyes_and_movement_to_follow_and_pass_a_visible_post :: proc(t: ^testing.T) {
    for post in ([2]bool{false, true}) {
        catalog: content.Game_Content
        sim := pursuit_test_scenario(t, &catalog, post)
        arena := content.find_arena(&catalog, sim.session.map_id)
        radius := content.find_character(&catalog, 5).footprint_radius
        target_start := sim.session.characters[1].position
        acquired, blocked, detours := u32(0), 0, 0
        for tick in 0..<1200 {
            if !post {
                sim.session.characters[1].position = target_start + [2]f32{min(f32(tick) * 0.16, 64), min(f32(tick) * 0.08, 32)}
            }
            advance(&sim, &catalog)
            agent := sim.battle.agents[0]
            if agent.search.acquisition_count > 0 && acquired == 0 { acquired = sim.session.server_tick }
            if agent.last.result.kind == .Terrain_Blocked { blocked += 1 }
            if agent.navigation.committed { detours += 1 }
            if agent.navigation.preferred.kind == .Move && agent.navigation.preferred.approach.active {
                toward := agent.search.target_position - agent.navigation.position
                distance := math.sqrt(toward.x * toward.x + toward.y * toward.y)
                if distance > 0.001 {
                    heading := agent.navigation.preferred.direction
                    testing.expect(t, (heading.x * toward.x + heading.y * toward.y) / distance > 0.9999,
                        "the pursuit goal changed while passing an obstacle")
                }
            }
            testing.expect(t, content.arena_position_is_clear(arena, &catalog, sim.session.characters[0].position, radius))
        }
        gap := sim.session.characters[1].position - sim.session.characters[0].position
        distance := math.sqrt(gap.x * gap.x + gap.y * gap.y)
        fmt.printfln("[pursuit] post=%v: acquired=%d, final gap=%.2f, blocked=%d, detour ticks=%d",
            post, acquired, distance, blocked, detours)
        testing.expectf(t, acquired > 0 && acquired < 60, "the real eye did not acquire its visible target: %d", acquired)
        testing.expectf(t, distance <= sim.battle.agents[0].search.profile.pursuit_distance + 2,
            "pursuit abandoned the target: gap %.2f", distance)
        testing.expect(t, sim.battle.agents[0].search.target == obs.Subject_Handle(sim.session.characters[1].entity_id))
        testing.expect(t, blocked == 0, "pursuit repeatedly contacted known terrain")
        if post { testing.expect(t, detours > 0, "the body-sized post did not exercise avoidance") }
        content.destroy(&catalog)
    }
}
