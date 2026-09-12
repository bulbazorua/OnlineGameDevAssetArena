package diagnostics

import "../simulation"
import "core:testing"

@(test)
queue_drops_new_jobs_when_full_and_keeps_counting :: proc(t: ^testing.T) {
    debug := test_open_without_writer()
    defer free(debug)
    session: simulation.Session
    packet: [WORLD_PACKET_BYTES]u8
    for tick in 1..=QUEUE_CAPACITY + 5 {
        session.server_tick = u32(tick)
        capture_world(debug, &session, packet[:32])
    }
    testing.expect(t, test_queue_full(debug) && test_dropped(debug) == 5, "a full queue drops without blocking")
    testing.expect(t, debug.world_sequence == u64(QUEUE_CAPACITY + 5), "dropped captures still consume sequence numbers")
    oldest, found := test_queued_world(debug, 0)
    newest, newest_found := test_queued_world(debug, QUEUE_CAPACITY - 1)
    testing.expect(t, found && newest_found && oldest.tick == 1 && newest.tick == u32(QUEUE_CAPACITY), "the queue keeps the oldest jobs")
}
