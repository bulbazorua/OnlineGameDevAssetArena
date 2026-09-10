package main

import "core:encoding/json"
import "core:fmt"
import "core:os"

REPLAY_LIMIT_BYTES :: 128 * 1024 * 1024
Replay_Capture :: struct {
    sequence: u64,
    tick, round_id: u32,
    packet: [138]u8,
    packet_size: int,
}
Replay_Writer :: struct {
    file: ^os.File,
    bytes, limit: int,
    frames, last_sequence: u64,
    status: string,
}
Replay_Header :: struct {
    kind: string,
    schema_version, protocol_version, simulation_hz: int,
    run_id, fingerprint: string,
    seed: u32,
}
Replay_Frame :: struct {
    kind: string,
    sequence: u64,
    tick: u32,
    packet_hex: string,
    ai: []AI_Debug_Record_View,
}
Replay_End :: struct {
    kind, status: string,
    frames, last_sequence, captured_frames, dropped_messages: u64,
}

ai_debug_hex :: proc(bytes: []u8) -> string {
    output := make([]u8, len(bytes) * 2)
    digits := "0123456789abcdef"
    for b, i in bytes { output[2*i], output[2*i+1] = digits[b >> 4], digits[b & 15] }
    return string(output)
}

ai_debug_capture_world :: proc(debug: ^AI_Debug, session: ^Session) {
    if debug == nil { return }
    debug.world_sequence += 1
    capture := Replay_Capture{sequence = debug.world_sequence, tick = session.server_tick, round_id = session.round_id,
        packet = protocol_encode_session(session), packet_size = 138 if session.character_count == 2 else 32}
    ai_debug_push(debug, AI_Debug_Job{is_world = true, world = capture})
}

replay_write_line :: proc(debug: ^AI_Debug, data: []u8) -> bool {
    written, error := os.write(debug.replay.file, data)
    newline, newline_error := os.write(debug.replay.file, []u8{'\n'})
    debug.replay.bytes += int(written + newline)
    if error != nil || newline_error != nil || written != len(data) || newline != 1 {
        debug.replay.status = "write_error"
        ai_debug_error(debug, "Incomplete QA recording write")
        return false
    }
    return true
}

replay_capture :: proc(debug: ^AI_Debug, capture: ^Replay_Capture) {
    r := &debug.replay
    if r.status != "" && r.status != "recording" { return }
    if r.file == nil {
        path := fmt.aprintf("%s/match.replay.jsonl", debug.directory)
        defer delete(path)
        file, error := os.open(path, {.Write, .Create, .Trunc})
        if error != nil { r.status = "open_error"; ai_debug_error(debug, "Cannot open QA recording"); return }
        r.file = file
        header := Replay_Header{"header", 1, int(PROTOCOL_HEADER[4]), SIMULATION_HZ, debug.run_id, debug.fingerprint, debug.seed}
        data, encode_error := json.marshal(header)
        defer delete(data)
        if encode_error != nil { r.status = "encode_error"; return }
        if !replay_write_line(debug, data) { return }
        r.status = "recording"
    }
    views: [MAX_PLAYERS]AI_Debug_Record_View
    count := 0
    for owner in 0..<MAX_PLAYERS {
        if debug.totals[owner] == 0 { continue }
        trace := &debug.history[owner][(debug.totals[owner] - 1) % AI_DEBUG_HISTORY]
        if trace.input.tick == capture.tick && trace.input.round_id == capture.round_id {
            views[count] = ai_debug_view(debug, trace)
            count += 1
        }
    }
    hex := ai_debug_hex(capture.packet[:capture.packet_size])
    defer delete(hex)
    frame := Replay_Frame{"frame", capture.sequence, capture.tick, hex, views[:count]}
    data, error := json.marshal(frame, {use_enum_names = true})
    defer delete(data)
    if error != nil { r.status = "encode_error"; ai_debug_error(debug, "Cannot encode QA frame"); return }
    if r.bytes + len(data) + 1 > r.limit - 1024 {
        r.status = "size_limit"
        fmt.printfln("[QA replay] Recording reached its %d-byte limit; simulation continues (%s).", r.limit, debug.directory)
        return
    }
    if replay_write_line(debug, data) { r.frames += 1; r.last_sequence = capture.sequence }
}

replay_close :: proc(debug: ^AI_Debug) {
    r := &debug.replay
    if r.file == nil { return }
    // Called after the producer stopped and the writer drained the queue.
    status := "complete" if r.status == "recording" else r.status
    data, error := json.marshal(Replay_End{"end", status, r.frames, r.last_sequence, debug.world_sequence, debug.dropped})
    if error == nil { replay_write_line(debug, data) }
    delete(data)
    os.close(r.file)
    r.file = nil
    r.status = status
}
