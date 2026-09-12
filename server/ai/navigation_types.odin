package ai

import obs "../observations"

Move_Approach :: struct {
    active: bool,
    position: Vector,
    arrival_distance, clearance: f32,
}

Motion_Constraints :: struct {
    maximum_speed, footprint_radius, tick_seconds: f32,
}

Navigation_Mode :: enum { Inactive, Advance, Turn, Inspect, Recover, Arrived }
Pass_Side :: enum i8 { Left = -1, None = 0, Right = 1 }
Passage_Rejection :: enum { None, Solid, Step }

Navigation_Profile :: struct {
    acceleration, braking, lookahead_seconds, minimum_lookahead: f32,
    clearance, unknown_speed: f32,
    bout_ticks, memory_ticks, blocked_ticks, progress_ticks: u32,
}

navigation_defaults :: proc() -> Navigation_Profile {
    return {acceleration = 128, braking = 256, lookahead_seconds = 0.8, minimum_lookahead = 32,
        clearance = 4, unknown_speed = 16, bout_ticks = 24, memory_ticks = 180,
        blocked_ticks = 18, progress_ticks = 240}
}

Navigation_Memory :: struct {
    valid: bool,
    origin: [2]int,
    tile_size: f32,
    sample_id: u32,
    cells: [obs.LOCAL_TERRAIN_CELLS]u8,
    seen_tick: [obs.LOCAL_TERRAIN_CELLS]u32,
}

Passage :: struct {
    direction: Vector,
    clearance, unknown_at, pressure, score: f32,
    rejection: Passage_Rejection,
    uncertain: bool,
}

Navigation_Runtime :: struct {
    profile: Navigation_Profile,
    memory: Navigation_Memory,
    preferred: Intent,
    choices: [8]Passage,
    mode: Navigation_Mode,
    heading, preferred_facing: Facing,
    passing_side: Pass_Side,
    commitment_until: u32,
    committed, active, requested_move, progress_started, recovery_pending: bool,
    speed, urgency, intended_distance, actual_distance, dt: f32,
    velocity, actual_displacement, progress_origin, position: Vector,
    progress_tick, failed_ticks, recovery_count: u32,
}
