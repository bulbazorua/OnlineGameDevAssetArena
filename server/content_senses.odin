package main

import obs "observations"
import "perception"
import "core:encoding/json"
import "core:math"
import "core:strings"

// Validated `senses.json` profile. Ranges are converted once from gameplay units.
Sense_Profile :: struct {
    key: string,
    vision: obs.Vision_Profile,
    olfaction: obs.Olfaction_Profile,
    emitter: obs.Scent_Emitter,
}

content_sense_profile :: proc(content: ^Game_Content, key: string) -> ^Sense_Profile {
    for &profile in content.senses { if profile.key == key { return &profile } }
    return nil
}

content_number :: proc(value: json.Value) -> (f64, bool) {
    #partial switch number in value {
    case json.Integer: return f64(number), true
    case json.Float:
        if !math.is_nan(f64(number)) && !math.is_inf(f64(number)) { return f64(number), true }
    }
    return 0, false
}

scent_class_from_key :: proc(key: string) -> (obs.Scent_Class, bool) {
    switch key {
    case "human": return .Human, true
    case "orc": return .Orc, true
    }
    return .Human, false
}

@(private = "file")
content_parse_vision :: proc(vision: json.Object) -> (profile: obs.Vision_Profile, ok: bool) {
    enabled, enabled_ok := vision["enabled"].(json.Boolean)
    range_units, range_ok := content_number(vision["range_units"])
    focused, focused_ok := content_number(vision["focused_fov_degrees"])
    overall, overall_ok := content_number(vision["overall_fov_degrees"])
    interval, interval_ok := content_integer(vision["sample_interval_ticks"])
    if !enabled_ok || !range_ok || !focused_ok || !overall_ok || !interval_ok { return }
    if !(range_units > 0 && range_units <= perception.MAX_RANGE_GAMEPLAY_UNITS) || interval < 1 || interval > 60 { return }
    profile = {enabled = bool(enabled), range = f32(range_units * f64(perception.WORLD_UNITS_PER_GAMEPLAY_UNIT)),
        focused_fov_degrees = f32(focused), overall_fov_degrees = f32(overall), sample_interval = u32(interval)}
    return profile, perception.vision_profile_valid(profile)
}

// A nose: reach, schedule and whether it can tell how old a trace is.
@(private = "file")
content_parse_receptor :: proc(receptor: json.Object) -> (profile: obs.Olfaction_Profile, ok: bool) {
    enabled, enabled_ok := receptor["enabled"].(json.Boolean)
    range_units, range_ok := content_number(receptor["range_units"])
    interval, interval_ok := content_integer(receptor["sample_interval_ticks"])
    freshness, freshness_ok := receptor["estimates_freshness"].(json.Boolean)
    if !enabled_ok || !range_ok || !interval_ok || !freshness_ok { return }
    if !(range_units > 0 && range_units <= perception.MAX_OLFACTION_RANGE_GAMEPLAY_UNITS) || interval < 1 || interval > 60 { return }
    profile = {enabled = bool(enabled), range = f32(range_units * f64(perception.WORLD_UNITS_PER_GAMEPLAY_UNIT)),
        sample_interval = u32(interval), estimates_freshness = bool(freshness)}
    return profile, perception.olfaction_profile_valid(profile)
}

// A body's smell: a disabled emitter still names a valid class and intensity.
content_parse_emitter :: proc(emitter: json.Object) -> (result: obs.Scent_Emitter, ok: bool) {
    enabled, enabled_ok := emitter["enabled"].(json.Boolean)
    class_key, class_ok := emitter["scent_class"].(json.String)
    intensity, intensity_ok := content_number(emitter["intensity"])
    if !enabled_ok || !class_ok || !intensity_ok || !(intensity > 0 && intensity <= 4) { return }
    class, known := scent_class_from_key(string(class_key))
    if !known { return }
    return {enabled = bool(enabled), class = class, intensity = f32(intensity)}, true
}

// Schema 2: unique profiles with bounded vision and olfaction tuning, one trainer
// emitter, and exactly one binding per selectable character. A disabled receptor
// or emitter still validates its numbers. Both readers reject the same catalogs.
content_parse_senses :: proc(content: ^Game_Content, root: json.Object) -> bool {
    profiles, profiles_ok := root["profiles"].(json.Array)
    if !profiles_ok || len(profiles) == 0 || len(profiles) > 256 { return false }
    for entry in profiles {
        fields, fields_ok := entry.(json.Object)
        if !fields_ok { return false }
        key, key_ok := fields["key"].(json.String)
        vision, vision_ok := fields["vision"].(json.Object)
        olfaction, olfaction_ok := fields["olfaction"].(json.Object)
        if !key_ok || !content_key_is_valid(string(key)) || !vision_ok || !olfaction_ok { return false }
        receptor, receptor_ok := olfaction["receptor"].(json.Object)
        emitter, emitter_ok := olfaction["emitter"].(json.Object)
        if !receptor_ok || !emitter_ok { return false }
        vision_profile, vision_valid := content_parse_vision(vision)
        nose, nose_valid := content_parse_receptor(receptor)
        scent, scent_valid := content_parse_emitter(emitter)
        if !vision_valid || !nose_valid || !scent_valid { return false }
        if content_sense_profile(content, string(key)) != nil { return false }
        append(&content.senses, Sense_Profile{strings.clone(string(key)), vision_profile, nose, scent})
    }
    trainer, trainer_ok := root["trainer_emitter"].(json.Object)
    if !trainer_ok { return false }
    trainer_emitter, trainer_valid := content_parse_emitter(trainer)
    if !trainer_valid { return false }
    content.trainer_emitter = trainer_emitter
    bindings, bindings_ok := root["bindings"].(json.Array)
    if !bindings_ok || len(bindings) != len(content.characters) { return false }
    for entry in bindings {
        fields, fields_ok := entry.(json.Object)
        if !fields_ok { return false }
        character_key, character_ok := fields["character"].(json.String)
        profile_key, profile_ok := fields["profile"].(json.String)
        if !character_ok || !profile_ok { return false }
        profile := content_sense_profile(content, string(profile_key))
        if profile == nil { return false }
        bound := false
        for &character in content.characters {
            if character.key != string(character_key) { continue }
            if character.sense_profile != "" { return false } // duplicate binding
            character.sense_profile = profile.key
            character.vision = profile.vision
            character.olfaction = profile.olfaction
            character.emitter = profile.emitter
            bound = true
        }
        if !bound { return false }
    }
    for character in content.characters { if character.sense_profile == "" { return false } }
    return true
}
