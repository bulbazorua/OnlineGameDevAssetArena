package main

import "simulation"
import ai "ai"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:time"

SEARCH_DEBUG_BYTES :: 32 * 1024
// Schema 2 adds the scent evidence the searcher is acting on.
SEARCH_DEBUG_SCHEMA :: 2
Search_Debug_Record :: struct {
    owner_id: int,
    entity_id, round_id, tick: u32,
    map_id: u16,
    search: ai.Search_Runtime,
    intent: ai.Intent,
    result: ai.Action_Result,
    position_after: ai.Vector,
}
Search_Debug_Snapshot :: struct {
    schema_version: int,
    run_id, fingerprint: string,
    published_us: i64,
    world: Sense_Debug_World,
    records: []Search_Debug_Record,
}

ai_debug_publish_search :: proc(debug: ^AI_Debug) {
    records: [simulation.MAX_PLAYERS]Search_Debug_Record
    count := 0
    for owner in 0..<simulation.MAX_PLAYERS {
        if !debug.sense_world.active || debug.totals[owner] == 0 { continue }
        record := &debug.history[owner][(debug.totals[owner] - 1) % AI_DEBUG_HISTORY]
        if record.after.controller != .Search || record.input.round_id != debug.sense_world.round_id || record.map_id != debug.sense_world.map_id ||
            record.input.entity_id != debug.sense_world.entities[owner] { continue }
        records[count] = {owner + 1, record.input.entity_id, record.input.round_id, record.input.tick, record.map_id,
            record.after.search, record.after.intent, record.result, record.position_after}
        count += 1
    }
    snapshot := Search_Debug_Snapshot{SEARCH_DEBUG_SCHEMA, debug.run_id, debug.fingerprint, i64(time.tick_since(debug.origin) / time.Microsecond), debug.sense_world, records[:count]}
    data, error := json.marshal(snapshot, {use_enum_names = true})
    if error != nil { ai_debug_error(debug, "Cannot serialize search display"); return }
    defer delete(data)
    if len(data) > SEARCH_DEBUG_BYTES { ai_debug_error(debug, "Search display exceeded the size limit"); return }
    path := fmt.aprintf("%s/search.json", debug.directory)
    defer delete(path)
    temporary := fmt.aprintf("%s.tmp", path)
    defer delete(temporary)
    if os.write_entire_file(temporary, data) != nil || os.rename(temporary, path) != nil { ai_debug_error(debug, "Cannot publish search display") }
}

// The reset itself belongs to the simulation; the host only reports what it produced.
dev_log_search_reset :: proc(session: ^simulation.Session) {
    p1, p2 := session.characters[0].position, session.characters[1].position
    delta := p1 - p2
    distance := math.sqrt(delta.x * delta.x + delta.y * delta.y)
    fmt.printfln("[dev] Search reset: round=%d, creature positions=%v / %v, separation=%.1f; fresh memories on next simulation tick.", session.round_id, p1, p2, distance)
}
