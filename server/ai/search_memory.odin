package ai

import "core:math"

search_memory_strength :: proc(now, visited, retention: u32) -> f32 {
    age := now - visited
    if age >= retention { return 0 }
    return 1 - f32(age) / f32(retention)
}

search_region :: proc(position: Vector, size: f32) -> [2]int {
    return {int(math.floor(position.x / size)), int(math.floor(position.y / size))}
}

search_remember_visit :: proc(search: ^Search_Runtime, position: Vector, tick: u32) {
    count := 0
    for entry in search.visits[:search.visit_count] {
        if search_memory_strength(tick, entry.visited_tick, search.profile.history_ticks) <= 0 { continue }
        search.visits[count] = entry
        count += 1
    }
    for index in count..<SEARCH_MEMORY_CAPACITY { search.visits[index] = {} }
    search.visit_count = count
    region := search_region(position, search.profile.region_size)
    index, oldest := -1, 0
    for entry, i in search.visits[:count] {
        if search_region(entry.position, search.profile.region_size) == region { index = i; break }
        if tick - entry.visited_tick > tick - search.visits[oldest].visited_tick { oldest = i }
    }
    if index < 0 {
        if count < search.profile.memory_capacity { index = count; search.visit_count += 1 }
        else { index = oldest }
    }
    search.visits[index] = {position, tick, search.target_visible}
}

search_recent_penalty :: proc(search: ^Search_Runtime, position: Vector, tick: u32) -> f32 {
    region := search_region(position, search.profile.region_size)
    penalty: f32
    for visit in search.visits[:search.visit_count] {
        if visit.opponent_seen || search_region(visit.position, search.profile.region_size) != region { continue }
        penalty = max(penalty, search_memory_strength(tick, visit.visited_tick, search.profile.history_ticks))
    }
    return penalty
}

search_expire_blocks :: proc(search: ^Search_Runtime, position: Vector, tick: u32) {
    moved_away := distance_between(position, search.blocked_origin) > search.profile.region_size / 2
    for index in 0..<8 {
        if moved_away || tick_due(tick, search.blocked_until[index]) {
            search.blocked[index], search.blocked_until[index] = false, 0
        }
    }
}
