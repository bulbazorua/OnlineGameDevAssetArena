package diagnostics

import "../simulation"
import ai "../ai"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:time"

@(private) SEARCH_BYTES :: 32 * 1024
// Schema 2 adds the scent evidence the searcher is acting on.
SEARCH_SCHEMA :: 2
Search_Record :: struct {
    owner_id: int,
    entity_id, round_id, tick: u32,
    map_id: u16,
    search: ai.Search_Runtime,
    intent: ai.Intent,
    result: ai.Action_Result,
    position_after: ai.Vector,
}
Search_Snapshot :: struct {
    schema_version: int,
    run_id, fingerprint: string,
    published_us: i64,
    world: Sense_World,
    records: []Search_Record,
}

// Writer thread: publish the latest lifecycle-matched search state of each searching
// creature (search.json). Nothing here enriches a belief from the host world.
@(private)
publish_search :: proc(debug: ^Diagnostics) {
    records: [simulation.MAX_PLAYERS]Search_Record
    count := 0
    for owner in 0..<simulation.MAX_PLAYERS {
        if !debug.sense_world.active || debug.totals[owner] == 0 { continue }
        record := &debug.history[owner][(debug.totals[owner] - 1) % HISTORY]
        if record.after.controller != .Search || record.input.round_id != debug.sense_world.round_id || record.map_id != debug.sense_world.map_id ||
            record.input.entity_id != debug.sense_world.entities[owner] { continue }
        records[count] = {owner + 1, record.input.entity_id, record.input.round_id, record.input.tick, record.map_id,
            record.after.search, record.after.intent, record.result, record.position_after}
        count += 1
    }
    snapshot := Search_Snapshot{SEARCH_SCHEMA, debug.run_id, debug.fingerprint, i64(time.tick_since(debug.origin) / time.Microsecond), debug.sense_world, records[:count]}
    data, error := json.marshal(snapshot, {use_enum_names = true})
    if error != nil { report_error(debug, "Cannot serialize search display"); return }
    defer delete(data)
    if len(data) > SEARCH_BYTES { report_error(debug, "Search display exceeded the size limit"); return }
    path := fmt.aprintf("%s/search.json", debug.directory)
    defer delete(path)
    temporary := fmt.aprintf("%s.tmp", path)
    defer delete(temporary)
    if os.write_entire_file(temporary, data) != nil || os.rename(temporary, path) != nil { report_error(debug, "Cannot publish search display") }
}
