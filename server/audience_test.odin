package main

import "core:testing"
import "core:time"

@(test)
audience_history_delays_copies_and_stays_bounded :: proc(t: ^testing.T) {
    stream := audience_init(DEFAULT_AUDIENCE_DELAY_MS)
    defer audience_destroy(&stream)
    capacity := len(stream.frames)
    live: Session
    // Wrap the ring several times while recording and releasing at 20 Hz.
    for sample in 0..=500 {
        live.server_tick = u32(sample)
        live.characters[0].position.x = f32(sample)
        released := audience_advance(&stream, &live, time.Duration(sample) * AUDIENCE_SAMPLE_INTERVAL)
        testing.expect(t, stream.count <= capacity && len(stream.frames) == capacity)
        if sample < 100 {
            testing.expect(t, !released && !stream.has_latest)
        } else {
            testing.expect(t, released && stream.has_latest)
            testing.expect(t, stream.latest.server_tick == u32(sample - 100))
            testing.expect(t, stream.latest.characters[0].position.x == f32(sample - 100))
        }
    }
    // Mutating current state, including reset, cannot change saved state.
    previous := stream.latest
    session_reset(&live)
    testing.expect(t, stream.latest == previous)
}

@(test)
audience_delay_uses_wall_time_and_fails_closed_during_warmup :: proc(t: ^testing.T) {
    stream := audience_init(1250)
    defer audience_destroy(&stream)
    live := Session{round_id = 42, server_tick = 100}
    testing.expect(t, !audience_advance(&stream, &live, 0))
    // A large simulated tick jump in little real time buys no earlier release.
    live.server_tick = 100000
    live.round_id = 43
    testing.expect(t, !audience_advance(&stream, &live, 1249 * time.Millisecond))
    testing.expect(t, !stream.has_latest)
    testing.expect(t, audience_advance(&stream, &live, 1250 * time.Millisecond))
    testing.expect(t, stream.latest.round_id == 42 && stream.latest.server_tick == 100)
    testing.expect(t, !audience_advance(&stream, &live, 2498 * time.Millisecond))
    testing.expect(t, audience_advance(&stream, &live, 2499 * time.Millisecond))
    testing.expect(t, stream.latest.round_id == 43)
    // A stalled host drops intermediate history instead of playing it fast.
    testing.expect(t, audience_advance(&stream, &live, 20 * time.Second))
    testing.expect(t, stream.count == 1)
}

@(test)
audience_delay_zero_and_welcome_contract :: proc(t: ^testing.T) {
    stream := audience_init(0)
    defer audience_destroy(&stream)
    live: Session
    testing.expect(t, !audience_advance(&stream, &live, 60 * time.Second))
    testing.expect(t, len(stream.frames) == 0 && !stream.has_latest)
    testing.expect(t, protocol_encode_welcome(0, 5000) == [11]u8{'O', 'G', 'A', 'A', 6, 2, 0, 136, 19, 0, 0})
    testing.expect(t, protocol_encode_welcome(1) == [11]u8{'O', 'G', 'A', 'A', 6, 2, 1, 0, 0, 0, 0})
    maximum := audience_init(MAX_AUDIENCE_DELAY_MS)
    defer audience_destroy(&maximum)
    testing.expect(t, len(maximum.frames) == 1202)
}
