package main

import "simulation"
import obs "observations"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:time"

// Schema 3 added the nose sample, its own delivery clock and the owner's emitter;
// schema 4 adds the nose's zone coverage inside that sample.
SENSE_DEBUG_SCHEMA :: 4
SENSE_DEBUG_BYTES :: 32 * 1024

Sense_Debug_World :: struct {
    active: bool,
    round_id: u32,
    map_id: u16,
    entities: [simulation.MAX_PLAYERS]u32,
}

Sense_Debug_Record :: struct {
    owner_id: int,
    entity_id, round_id, tick: u32,
    definition_id, map_id: u16,
    delivered_us: i64,
    vision: obs.Vision_Sample,
    sight_fan: []obs.Vector,
    scent_delivered_us: i64,
    olfaction: obs.Scent_Sample,
    own_emitter: obs.Scent_Emitter,
}

Sense_Debug_Snapshot :: struct {
    schema_version: int,
    run_id, fingerprint: string,
    published_us: i64,
    origin_unix_us: i64,
    world: Sense_Debug_World,
    records: []Sense_Debug_Record,
}

sense_debug_record :: proc(record: ^AI_Debug_Record, delivered_us, scent_delivered_us: i64) -> Sense_Debug_Record {
    return {
        owner_id = record.owner_id,
        entity_id = record.input.entity_id,
        round_id = record.input.round_id,
        tick = record.input.tick,
        definition_id = record.definition_id,
        map_id = record.map_id,
        delivered_us = delivered_us,
        vision = record.input.senses.vision,
        sight_fan = record.fan[:record.fan_count],
        scent_delivered_us = scent_delivered_us,
        olfaction = record.input.senses.olfaction,
        own_emitter = record.input.own_emitter,
    }
}

sense_debug_collect :: proc(debug: ^AI_Debug, records: ^[simulation.MAX_PLAYERS]Sense_Debug_Record) -> int {
    count := 0
    for owner in 0..<simulation.MAX_PLAYERS {
        if !debug.sense_world.active || debug.totals[owner] == 0 { continue }
        latest := &debug.history[owner][(debug.totals[owner] - 1) % AI_DEBUG_HISTORY]
        if latest.input.round_id != debug.sense_world.round_id || latest.map_id != debug.sense_world.map_id ||
           latest.input.entity_id != debug.sense_world.entities[owner] { continue }
        delivered_us, scent_delivered_us: i64 = -1, -1
        if latest.input.senses.vision.status == .Sampled { delivered_us = debug.delivery[owner].vision.delivered_us }
        if latest.input.senses.olfaction.status == .Sampled { scent_delivered_us = debug.delivery[owner].olfaction.delivered_us }
        records[count] = sense_debug_record(latest, delivered_us, scent_delivered_us)
        count += 1
    }
    return count
}

// The log writer shares only the latest readings, without copying brain history.
ai_debug_publish_senses :: proc(debug: ^AI_Debug) {
    records: [simulation.MAX_PLAYERS]Sense_Debug_Record
    count := sense_debug_collect(debug, &records)
    snapshot := Sense_Debug_Snapshot{
        SENSE_DEBUG_SCHEMA, debug.run_id, debug.fingerprint,
        i64(time.tick_since(debug.origin) / time.Microsecond), debug.origin_unix_us,
        debug.sense_world, records[:count],
    }
    data, error := json.marshal(snapshot, {use_enum_names = true})
    if error != nil { ai_debug_error(debug, "Cannot serialize live senses"); return }
    defer delete(data)
    if len(data) > SENSE_DEBUG_BYTES { ai_debug_error(debug, "Live senses exceeded the size limit"); return }
    path := fmt.aprintf("%s/senses.json", debug.directory)
    defer delete(path)
    temporary := fmt.aprintf("%s.tmp", path)
    defer delete(temporary)
    if os.write_entire_file(temporary, data) != nil || os.rename(temporary, path) != nil {
        ai_debug_error(debug, "Cannot publish live senses")
    }
}
