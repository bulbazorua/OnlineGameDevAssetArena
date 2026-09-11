package main

import "simulation"
import obs "observations"
import "perception"
import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:time"

SCENT_DEBUG_SCHEMA :: 1
// Two classes, two layers, up to 16,384 cells each, base64 encoded: about 88 KiB.
SCENT_DEBUG_BYTES :: 96 * 1024

// A quantized copy of the host field for the developer heatmap. Filled on the
// simulation thread after a field step; read by the writer under the mutex.
Scent_Debug_Capture :: struct {
    valid: bool,
    round_id, tick: u32,
    map_id: u16,
    width, height: int,
    tile_size: f32,
    levels: [obs.Scent_Class][perception.MAX_GRID_CELLS]u8, // 0..255 of the saturation cap.
    ages: [obs.Scent_Class][perception.MAX_GRID_CELLS]u8,   // Whole seconds since the newest deposit, capped at 255.
}

Scent_Debug_Field :: struct {
    valid: bool,
    round_id, tick: u32,
    map_id: u16,
    width, height: int,
    tile_size: f32,
    step_ticks: int,
    classes: []string,
    levels: []string,
    ages: []string,
}

Scent_Debug_Snapshot :: struct {
    schema_version: int,
    run_id, fingerprint: string,
    published_us: i64,
    world: Sense_Debug_World,
    field: Scent_Debug_Field,
}

// Copy the field into the capture slot when it changed. A memcpy-sized lock,
// no JSON, no file work on the simulation thread; nothing is read back.
ai_debug_capture_scent :: proc(debug: ^AI_Debug, battle: ^simulation.Battle_Runtime, session: ^simulation.Session) {
    if debug == nil { return }
    field := &battle.scent.field
    active := session.phase == .In_Arena && battle.bound && perception.scent_field_valid(field)
    sync.mutex_lock(&debug.scent_mutex)
    defer sync.mutex_unlock(&debug.scent_mutex)
    capture := &debug.scent_capture
    if !active {
        if capture.valid { capture.valid = false }
        return
    }
    unchanged := capture.valid && capture.round_id == session.round_id && capture.map_id == session.map_id && debug.scent_captured_steps == field.steps
    if unchanged { return }
    debug.scent_captured_steps = field.steps
    capture.valid, capture.round_id, capture.map_id, capture.tick = true, session.round_id, session.map_id, session.server_tick
    capture.width, capture.height, capture.tile_size = field.width, field.height, field.tile_size
    for class in obs.Scent_Class {
        for index in 0..<field.width * field.height {
            capture.levels[class][index] = u8(clamp(field.levels[class][index] / perception.SCENT_CAP * 255 + 0.5, 0, 255))
            capture.ages[class][index] = u8(min(255, u32(field.ages[class][index]) * perception.SCENT_STEP_TICKS / simulation.SIMULATION_HZ))
        }
    }
}

// Writer thread: publish the latest capture as scent.json for the arena heatmap.
ai_debug_publish_scent :: proc(debug: ^AI_Debug) {
    capture := new(Scent_Debug_Capture)
    defer free(capture)
    sync.mutex_lock(&debug.scent_mutex)
    capture^ = debug.scent_capture
    sync.mutex_unlock(&debug.scent_mutex)
    classes := [obs.SCENT_CLASS_COUNT]string{"Human", "Orc"}
    levels, ages: [obs.SCENT_CLASS_COUNT]string
    defer for index in 0..<obs.SCENT_CLASS_COUNT { delete(levels[index]); delete(ages[index]) }
    field := Scent_Debug_Field{valid = capture.valid, step_ticks = perception.SCENT_STEP_TICKS, classes = classes[:]}
    if capture.valid {
        cells := capture.width * capture.height
        for class, index in obs.Scent_Class {
            levels[index] = base64.encode(capture.levels[class][:cells])
            ages[index] = base64.encode(capture.ages[class][:cells])
        }
        field.round_id, field.tick, field.map_id = capture.round_id, capture.tick, capture.map_id
        field.width, field.height, field.tile_size = capture.width, capture.height, capture.tile_size
        field.levels, field.ages = levels[:], ages[:]
    }
    snapshot := Scent_Debug_Snapshot{SCENT_DEBUG_SCHEMA, debug.run_id, debug.fingerprint, i64(time.tick_since(debug.origin) / time.Microsecond), debug.sense_world, field}
    data, error := json.marshal(snapshot, {use_enum_names = true})
    if error != nil { ai_debug_error(debug, "Cannot serialize scent field"); return }
    defer delete(data)
    if len(data) > SCENT_DEBUG_BYTES { ai_debug_error(debug, "Scent field exceeded the size limit"); return }
    path := fmt.aprintf("%s/scent.json", debug.directory)
    defer delete(path)
    temporary := fmt.aprintf("%s.tmp", path)
    defer delete(temporary)
    if os.write_entire_file(temporary, data) != nil || os.rename(temporary, path) != nil { ai_debug_error(debug, "Cannot publish scent field") }
}
