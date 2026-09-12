package ai

import obs "../observations"

@(private)
search_pursuing_target :: proc(search: ^Search_Runtime) -> bool {
    return search.state == .Pursue || search.state == .Last_Known_Position
}

@(private)
search_pursuit_direction :: proc(search: ^Search_Runtime, position: Vector) -> Vector {
    distance := distance_between(position, search.target_position)
    if distance <= 0.000001 { return {} }
    return (search.target_position - position) / distance
}

@(private)
search_choose_pursuit_heading :: proc(search: ^Search_Runtime, ctx: Decision_Context, trace: ^Trace_Buffer, parent: int) {
    direction := search_pursuit_direction(search, ctx.position)
    heading, valid := obs.facing_toward({}, direction)
    search.heading = heading if valid else ctx.facing
    search.scored_tick, search.scored_position, search.relocating = ctx.tick, ctx.position, false
    search.leg_active, search.leg_deadline = true, ctx.tick + 6
    for index in 0..<8 {
        score := 5 * search_alignment(obs.facing_direction(Facing(index)), direction)
        search.choices[index] = {evidence = score, total = score}
    }
    label := "Pursue the observed opponent; local movement chooses a safe passage"
    if search.state == .Last_Known_Position { label = "Continue to the last sighting; do not guess where the opponent moved" }
    trace_add(trace, parent, .State, .Selected, label, "target / evidence tick",
        f64(search.target), f64(search.target_tick), direction, search.observation_id, u32(search.target))
}
