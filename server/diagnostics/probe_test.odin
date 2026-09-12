package diagnostics

import "core:time"

// Test-only paths. Production builds the state through open and never reads the queue or
// the capture slot; these let tests in other packages fill the queue without a writer
// and inspect exactly what the main thread handed over.
test_open_without_writer :: proc() -> ^Diagnostics {
    debug := new(Diagnostics)
    debug.origin = time.tick_now()
    return debug
}

test_queue_full :: proc(debug: ^Diagnostics) -> bool { return debug.count == len(debug.queue) }

test_dropped :: proc(debug: ^Diagnostics) -> u64 { return debug.dropped }

// The queued job at `position` counted from the oldest, when it is a world capture.
test_queued_world :: proc(debug: ^Diagnostics, position: int) -> (capture: World_Capture, found: bool) {
    if position < 0 || position >= debug.count { return }
    job := &debug.queue[(debug.head + position) % len(debug.queue)]
    if !job.is_world { return }
    return job.world, true
}

test_scent_capture :: proc(debug: ^Diagnostics) -> Scent_Capture { return debug.scent_capture }
