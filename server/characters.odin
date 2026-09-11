package main

import obs "observations"

// Shared gameplay definition. Appearance stays in the Godot client. The sense
// profile is game-authored catalog data (source `game_catalog`), not art export.
Character_Definition :: struct {
    id: u16,
    key: string,
    display_name: string,
    footprint_radius: f32,
    sense_profile: string,
    vision: obs.Vision_Profile,
    olfaction: obs.Olfaction_Profile,
    emitter: obs.Scent_Emitter,
}
