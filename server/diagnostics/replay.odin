package diagnostics

import "../simulation"
import "core:encoding/json"
import "core:fmt"
import "core:os"

// Owned storage for one encoded session packet. The host codec's packet must fit here;
// the host test checks that against the real encoder.
WORLD_PACKET_BYTES :: 164
@(private) REPLAY_LIMIT_BYTES :: 128 * 1024 * 1024
// Envelope 5 carries schema-5 traces (nose coverage); historical readers keep their own schemas.
REPLAY_SCHEMA :: 5
// A frame line must stay below the reader's 128 KiB cap; oversized frames keep
// the world packet and drop their traces, which the end record counts.
@(private) REPLAY_LINE_LIMIT :: 120 * 1024
// One tick's public world as the host published it, copied into the queue by value.
@(private)
World_Capture :: struct {
    sequence: u64,
    tick, round_id: u32,
    packet: [WORLD_PACKET_BYTES]u8,
    packet_size: int,
    senses: Sense_World,
}
@(private)
Replay_Writer :: struct {
    file: ^os.File,
    bytes, limit, line_limit: int,
    frames, last_sequence, oversized_frames: u64,
    status: string,
}
Replay_Header :: struct {
    kind: string,
    schema_version, protocol_version, simulation_hz: int,
    run_id, fingerprint: string,
    seed: u32,
    trace_schema: int,
}
Replay_Frame :: struct {
    kind: string,
    sequence: u64,
    tick: u32,
    packet_hex: string,
    ai: []Record_View,
}
Replay_End :: struct {
    kind, status: string,
    frames, last_sequence, captured_frames, dropped_messages, oversized_frames: u64,
}

@(private)
hex :: proc(bytes: []u8) -> string {
    output := make([]u8, len(bytes) * 2)
    digits := "0123456789abcdef"
    for b, i in bytes { output[2*i], output[2*i+1] = digits[b >> 4], digits[b & 15] }
    return string(output)
}

// Main thread: queue this tick's public world. `packet` is the host's already encoded
// session packet, valid for its whole length; the bytes are copied before returning.
capture_world :: proc(debug: ^Diagnostics, session: ^simulation.Session, packet: []u8) {
    if debug == nil { return }
    debug.world_sequence += 1
    capture := World_Capture{sequence = debug.world_sequence, tick = session.server_tick, round_id = session.round_id}
    capture.packet_size = copy(capture.packet[:], packet)
    capture.senses = {active = session.phase == .In_Arena && session.character_count == simulation.MAX_PLAYERS,
        round_id = session.round_id, map_id = session.map_id}
    for character, owner in session.characters { capture.senses.entities[owner] = character.entity_id }
    push(debug, Job{is_world = true, world = capture})
}

@(private = "file")
replay_write_line :: proc(debug: ^Diagnostics, data: []u8) -> bool {
    written, error := os.write(debug.replay.file, data)
    newline, newline_error := os.write(debug.replay.file, []u8{'\n'})
    debug.replay.bytes += int(written + newline)
    if error != nil || newline_error != nil || written != len(data) || newline != 1 {
        debug.replay.status = "write_error"
        report_error(debug, "Incomplete QA recording write")
        return false
    }
    return true
}

// Writer thread: open the recording on the first frame, then write this frame with the
// traces of the same tick. Oversized frames keep the packet and drop the traces.
@(private)
replay_write_frame :: proc(debug: ^Diagnostics, capture: ^World_Capture) {
    r := &debug.replay
    if r.status != "" && r.status != "recording" { return }
    if r.file == nil {
        path := fmt.aprintf("%s/match.replay.jsonl", debug.directory)
        defer delete(path)
        file, error := os.open(path, {.Write, .Create, .Trunc})
        if error != nil { r.status = "open_error"; report_error(debug, "Cannot open QA recording"); return }
        r.file = file
        header := Replay_Header{"header", REPLAY_SCHEMA, debug.protocol_version, simulation.SIMULATION_HZ, debug.run_id, debug.fingerprint, debug.seed, TRACE_SCHEMA}
        data, encode_error := json.marshal(header)
        defer delete(data)
        if encode_error != nil { r.status = "encode_error"; return }
        if !replay_write_line(debug, data) { return }
        r.status = "recording"
    }
    views: [simulation.MAX_PLAYERS]Record_View
    count := 0
    for owner in 0..<simulation.MAX_PLAYERS {
        if debug.totals[owner] == 0 { continue }
        trace := &debug.history[owner][(debug.totals[owner] - 1) % HISTORY]
        if trace.input.tick == capture.tick && trace.input.round_id == capture.round_id {
            views[count] = record_view(debug, trace)
            count += 1
        }
    }
    packet_hex := hex(capture.packet[:capture.packet_size])
    defer delete(packet_hex)
    frame := Replay_Frame{"frame", capture.sequence, capture.tick, packet_hex, views[:count]}
    data, error := json.marshal(frame, {use_enum_names = true})
    if error != nil { r.status = "encode_error"; report_error(debug, "Cannot encode QA frame"); return }
    line_limit := r.line_limit if r.line_limit > 0 else REPLAY_LINE_LIMIT
    if len(data) > line_limit {
        // Keep the world frame; the traces of this tick become an explicit gap.
        delete(data)
        r.oversized_frames += 1
        frame.ai = views[:0]
        data, error = json.marshal(frame, {use_enum_names = true})
        if error != nil { r.status = "encode_error"; report_error(debug, "Cannot encode QA frame"); return }
        report_error(debug, "Dropped oversized traces from a QA frame")
    }
    defer delete(data)
    if r.bytes + len(data) + 1 > r.limit - 1024 {
        r.status = "size_limit"
        fmt.printfln("[QA replay] Recording reached its %d-byte limit; simulation continues (%s).", r.limit, debug.directory)
        return
    }
    if replay_write_line(debug, data) { r.frames += 1; r.last_sequence = capture.sequence }
}

// Writer thread, after the producer stopped and the queue drained: write the end
// record with the final counts, then close the file.
@(private)
replay_close :: proc(debug: ^Diagnostics) {
    r := &debug.replay
    if r.file == nil { return }
    status := "complete" if r.status == "recording" else r.status
    data, error := json.marshal(Replay_End{"end", status, r.frames, r.last_sequence, debug.world_sequence, debug.dropped, r.oversized_frames})
    if error == nil { replay_write_line(debug, data) }
    delete(data)
    os.close(r.file)
    r.file = nil
    r.status = status
}
