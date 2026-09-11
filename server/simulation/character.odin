package simulation

import obs "../observations"

SIMULATION_HZ :: 60
INPUT_TIMEOUT_TICKS :: 15

// Explicit wire values. Animation names stay presentation bindings, not behavior IDs.
Character_Locomotion :: enum u8 { Idle = 0, Walk = 1, Run = 2 }
Character_Facing :: enum u8 { North = 0, North_East = 1, East = 2, South_East = 3, South = 4, South_West = 5, West = 6, North_West = 7 }

Character :: struct {
    entity_id: u32,
    definition_id: u16,
    owner_id: u8,
    position: [2]f32,
    pending_input_sequence: u32,
    applied_input_sequence: u32,
    input_mask: u8, // Left=1, Right=2, Up=4, Down=8; trainers can also hold Run=16.
    input_age_ticks: u16,
    locomotion: Character_Locomotion,
    facing: Character_Facing,
    state_start_tick: u32,
    target_alert: bool,
    target_acquired_tick: u32,
}

@(private)
character_facing_to_observation :: proc(facing: Character_Facing) -> obs.Facing { return obs.Facing(u8(facing)) }
