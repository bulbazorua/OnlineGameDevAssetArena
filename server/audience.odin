package main

import "core:time"

DEFAULT_AUDIENCE_DELAY_MS :: 5000
MAX_AUDIENCE_DELAY_MS :: 60000
AUDIENCE_SAMPLE_INTERVAL :: 50 * time.Millisecond

Audience_Frame :: struct {
    captured_at: time.Duration,
    session: Session,
}

// One bounded history shared by all viewers, including when none are connected.
// Session is a value: later simulation changes cannot alter captured frames.
Audience_Stream :: struct {
    delay_ms: u32,
    frames: []Audience_Frame,
    head, count: int,
    last_capture: time.Duration,
    has_capture, has_latest: bool,
    latest: Session,
}

audience_init :: proc(delay_ms: u32) -> Audience_Stream {
    assert(delay_ms <= MAX_AUDIENCE_DELAY_MS)
    stream := Audience_Stream{delay_ms = delay_ms}
    if delay_ms > 0 {
        stream.frames = make([]Audience_Frame, int((delay_ms + 49) / 50) + 2)
    }
    return stream
}

audience_destroy :: proc(stream: ^Audience_Stream) {
    delete(stream.frames)
    stream^ = {}
}

// Elapsed monotonic wall time, not simulation ticks: catch-up ticks must never
// release information early. Return only the newest frame old enough to send.
audience_advance :: proc(stream: ^Audience_Stream, live: ^Session, now: time.Duration) -> (released: bool) {
    if stream.delay_ms == 0 { return false }
    delay := time.Duration(stream.delay_ms) * time.Millisecond
    for stream.count > 0 {
        frame := &stream.frames[stream.head]
        if now - frame.captured_at < delay { break }
        stream.latest = frame.session
        stream.has_latest = true
        stream.head = (stream.head + 1) % len(stream.frames)
        stream.count -= 1
        released = true
    }
    if !stream.has_capture || now - stream.last_capture >= AUDIENCE_SAMPLE_INTERVAL {
        // Never overwrite unreleased history. Capacity covers the full delay
        // at the maximum capture rate, independently of client/command counts.
        if stream.count < len(stream.frames) {
            tail := (stream.head + stream.count) % len(stream.frames)
            stream.frames[tail] = {captured_at = now, session = live^}
            stream.count += 1
            stream.last_capture = now
            stream.has_capture = true
        }
    }
    return
}
