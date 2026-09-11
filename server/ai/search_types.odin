package ai

import obs "../observations"

SEARCH_MEMORY_CAPACITY :: 16
Search_State :: enum { Extensive_Search, Intensive_Search, Investigate, Last_Known_Position, Pursue }
Search_Transition :: enum { No_Evidence, Focused_Opponent, Directional_Cue, Target_Lost, Reached_Last_Position, Evidence_Expired, Cue_Expired, Investigation_Abandoned, Scent_Trail, Scent_Presence, Scent_Faded }

Search_Profile :: struct {
    memory_capacity: int,
    history_ticks, evidence_ticks, blocked_ticks: u32,
    extensive_leg_ticks, intensive_leg_ticks, relocation_ticks: u32,
    region_size, arrival_radius, pursuit_distance: f32,
    local_radius, maximum_local_radius: f32,
    persistence, exploration, cue_weight, history_weight: f32,
    self_trail_ticks: u32, // Own visits younger than this explain away same-class scent behind you.
    scent_weight: f32,     // Steering pull of a scent bearing, below a visual cue's.
}

search_defaults :: proc() -> Search_Profile {
    return {16, 3600, 480, 180, 96, 36, 300, 64, 24, 40, 48, 144, 1.4, 1.2, 3, 2.5, 1200, 3}
}

search_profile_valid :: proc(p: Search_Profile) -> bool {
    if p.memory_capacity < 1 || p.memory_capacity > SEARCH_MEMORY_CAPACITY { return false }
    for ticks in ([6]u32{p.history_ticks, p.evidence_ticks, p.blocked_ticks, p.extensive_leg_ticks, p.intensive_leg_ticks, p.relocation_ticks}) {
        if ticks < 1 || ticks > 36000 { return false }
    }
    for number in ([10]f32{p.region_size, p.arrival_radius, p.pursuit_distance, p.local_radius, p.maximum_local_radius, p.persistence, p.exploration, p.cue_weight, p.history_weight, 1}) {
        if !(number > 0 && number <= 4096) { return false }
    }
    if p.self_trail_ticks < 1 || p.self_trail_ticks > 36000 || !(p.scent_weight > 0 && p.scent_weight <= 4096) { return false }
    return p.maximum_local_radius >= p.local_radius && p.relocation_ticks > p.extensive_leg_ticks
}

// The smell the searcher is currently acting on, after explaining away its own trail.
Scent_Evidence :: struct {
    valid: bool,
    class: obs.Scent_Class,
    strength: obs.Scent_Strength,
    freshness: obs.Scent_Freshness,
    bearing_valid: bool,
    bearing: Facing,
    observation_id, observed_tick: u32,
    discounted_zones: int, // Zones ignored because they point at the searcher's own recent visits.
}

Search_Visit :: struct {
    position: Vector,
    visited_tick: u32,
    opponent_seen: bool,
}

Search_Choice :: struct {
    persistence, exploration, evidence, locality, recent_penalty, blocked_penalty, total: f32,
}

Search_Runtime :: struct {
    profile: Search_Profile,
    state: Search_State,
    transition: Search_Transition,
    started, leg_active, relocating: bool,
    random_state: u32,
    heading: Facing,
    leg_deadline, scored_tick, state_tick: u32,
    scored_position, position: Vector,
    choices: [8]Search_Choice,
    visits: [SEARCH_MEMORY_CAPACITY]Search_Visit,
    visit_count: int,
    blocked_until: [8]u32,
    blocked: [8]bool,
    blocked_origin: Vector,
    blocked_count, relocation_count, abandoned_count: u32,
    evidence: Evidence_Kind,
    evidence_tick, observation_id: u32,
    center: Vector,
    center_valid: bool,
    radius, confidence: f32,
    cue_direction: Facing,
    cue_origin: Vector,
    cue_tick: u32,
    cue_valid: bool,
    cue_from_scent: bool, // The current bearing came from the nose, not the eyes.
    weak_episode_active, cue_cooldown: bool,
    weak_episode_tick, ignore_cues_until: u32,
    target: obs.Subject_Handle,
    target_position: Vector,
    target_tick: u32,
    target_visible: bool,
    acquired_tick, acquisition_count: u32,
    scent: Scent_Evidence,
    scent_episodes: u32,
}

search_random :: proc(search: ^Search_Runtime) -> f32 {
    value := search.random_state
    if value == 0 { value = 0x9e3779b9 }
    value ~= value << 13
    value ~= value >> 17
    value ~= value << 5
    search.random_state = value
    return f32(value >> 8) / 16777216
}

search_seed :: proc(seed, entity, round: u32) -> u32 {
    value := seed ~ (entity * 0x9e3779b9) ~ (round * 0x85ebca6b)
    return value if value != 0 else 1
}
