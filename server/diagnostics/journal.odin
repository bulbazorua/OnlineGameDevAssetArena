package diagnostics

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:time"

// The per-owner history snapshot the AI debugger window reads (ai-<owner>.json).
Snapshot :: struct {
    schema_version: int,
    run_id, fingerprint: string,
    owner_id: int,
    published_us: i64,
    dropped_records, overwritten_records, oversized_records: u64,
    writer_error: string,
    publish_us: i64,
    log_limit_bytes, retained_segments, record_limit_bytes: int,
    records: []Record_View,
    replay_status: string,
    replay_frames: u64,
    replay_bytes: int,
}

// Writer thread: shift ai-N.jsonl to .1, .1 to .2 and so on, dropping the oldest.
@(private = "file")
journal_rotate :: proc(debug: ^Diagnostics, path: string) {
    for n := OLD_LOGS; n >= 1; n -= 1 {
        destination := fmt.aprintf("%s.%d", path, n)
        source := path if n == 1 else fmt.aprintf("%s.%d", path, n - 1)
        if os.exists(destination) { os.remove(destination) }
        if os.exists(source) && os.rename(source, destination) != nil { report_error(debug, "Cannot rotate trace log") }
        delete(destination)
        if n > 1 { delete(source) }
    }
}

// Writer thread: append one record line to its owner's journal, rotating at the byte
// limit. An oversized record is counted and skipped, never written.
@(private)
journal_write :: proc(debug: ^Diagnostics, record: ^Record) {
    i := record.owner_id - 1
    view := record_view(debug, record)
    data, error := json.marshal(view, {use_enum_names = true})
    if error != nil { report_error(debug, "Cannot serialize trace"); return }
    defer delete(data)
    if len(data) > RECORD_LIMIT {
        debug.oversized[i] += 1
        report_error(debug, "Dropped an oversized trace record")
        return
    }
    path := fmt.aprintf("%s/ai-%d.jsonl", debug.directory, i + 1)
    defer delete(path)
    if debug.bytes[i] > 0 && debug.bytes[i] + len(data) + 1 > debug.log_limit {
        if debug.files[i] != nil { os.close(debug.files[i]); debug.files[i] = nil }
        journal_rotate(debug, path)
        debug.bytes[i] = 0
    }
    if debug.files[i] == nil {
        file, open_error := os.open(path, {.Write, .Create, .Append})
        if open_error != nil { report_error(debug, "Cannot open trace journal"); return }
        debug.files[i] = file
    }
    written, write_error := os.write(debug.files[i], data)
    newline, newline_error := os.write(debug.files[i], []u8{'\n'})
    if write_error != nil || newline_error != nil || written != len(data) || newline != 1 {
        report_error(debug, "Incomplete trace journal write")
    }
    debug.bytes[i] += int(written + newline)
}

// One creature's recent-history snapshot: the expensive part of the writer's work.
@(private)
publish_owner :: proc(debug: ^Diagnostics, owner: int, dropped: u64) {
    total := debug.totals[owner]
    count := int(min(total, u64(HISTORY)))
    views := debug.publish_views[:count]
    for j in 0..<count {
        index := int((total - u64(count) + u64(j)) % HISTORY)
        views[j] = record_view(debug, &debug.history[owner][index])
    }
    snapshot := Snapshot{TRACE_SCHEMA, debug.run_id, debug.fingerprint, owner + 1,
        i64(time.tick_since(debug.origin) / time.Microsecond), dropped, total - u64(count), debug.oversized[owner],
        debug.last_error, debug.publish_us, debug.log_limit, OLD_LOGS + 1, RECORD_LIMIT, views[:count],
        debug.replay.status, debug.replay.frames, debug.replay.bytes}
    data, error := json.marshal(snapshot, {use_enum_names = true})
    if error != nil { report_error(debug, "Cannot serialize debugger snapshot"); return }
    defer delete(data)
    path := fmt.aprintf("%s/ai-%d.json", debug.directory, owner + 1)
    defer delete(path)
    temporary := fmt.aprintf("%s.tmp", path)
    defer delete(temporary)
    if os.write_entire_file(temporary, data) != nil || os.rename(temporary, path) != nil {
        report_error(debug, "Cannot publish debugger snapshot")
    }
}
