package diagnostics

import "core:testing"

@(test)
launch_options_gate_diagnostics_to_debug_dev_loopback_hosts :: proc(t: ^testing.T) {
    // No diagnostic option at all is always a normal host, whatever the build.
    testing.expect(t, options_valid(false, "0.0.0.0", "", ""))
    testing.expect(t, options_valid(true, "127.0.0.1", "", ""))
    when ODIN_DEBUG {
        testing.expect(t, options_valid(true, "127.0.0.1", "/tmp/diagnostics-options-test", "run"))
        testing.expect(t, !options_valid(false, "127.0.0.1", "/tmp/diagnostics-options-test", "run"), "requires --dev")
        testing.expect(t, !options_valid(true, "0.0.0.0", "/tmp/diagnostics-options-test", "run"), "requires loopback")
        testing.expect(t, !options_valid(true, "127.0.0.1", "build/relative", "run"), "requires an absolute directory")
        testing.expect(t, !options_valid(true, "127.0.0.1", "/tmp/diagnostics-options-test", ""), "requires a run ID")
        testing.expect(t, !options_valid(true, "127.0.0.1", "", "run"), "requires a directory")
    } else {
        testing.expect(t, !options_valid(true, "127.0.0.1", "/tmp/diagnostics-options-test", "run"), "release builds reject diagnostics")
        testing.expect(t, open("/tmp/diagnostics-options-test", "run", {}, 11) == nil)
    }
}
