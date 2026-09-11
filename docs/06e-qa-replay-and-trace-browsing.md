# QA playback and responsive AI inspection

Checkpoint 6A.2, implemented and checked on 2026-09-10. The plan below was recorded
before replay implementation. It extends the [dedicated-thread harness](06d-ai-debugger-harness.md).
The replay envelope is now 4 with trace schema 4 ([olfaction](06n-olfactory-trails.md));
envelopes 1–3 still decode with their own schemas, and the host scent field is not
recorded, so replay marks it unavailable.

## Run it

```sh
make dev_arena P1=archer P2=orc ARENA=tiny_swords_village
# After recording, or from another terminal while the match continues:
make replay
# Open a specific retained recording:
make replay REPLAY=/absolute/path/to/match.replay.jsonl
```

The default `AI_DEBUG=1` enables both inspectors and recording. `make replay` opens
the newest `build/dev/*/generation-*/ai-traces-*/match.replay.jsonl`; an unfinished
recording is indexed through its current complete frames, with a visible warning.
Reopen it to include later frames. The launcher prints the path and stores it in
`session.json` as `replay_path`. Prefer stopping the run with Ctrl+C for a finalized
recording. Opening a replay reuses that run's staged presentation project when present;
exported recordings use the current client and require a matching content fingerprint.
For an exported file on a fresh checkout, first run `make import_runtime_client`.

Pause/play, the seek slider, previous/next frame and 0.25–4× speed control one clock.
The arena supports overview, P1/P2 camera focus, wheel zoom and right-drag pan. P1/P2
decision tabs show actual branches at that same tick, with event stepping and node
details. Root/fit/zoom controls navigate the downward graph. Status words accompany
colors: cyan chosen, green true/allowed, coral false/rejected, purple host result,
gray skipped and amber unavailable. A highlighted false condition still stays false.

Recording stops at 128 MiB and reports `size_limit` in the inspectors and playback;
the simulation continues. At the measured 10.2 MB per 20.3 seconds, a similarly
instrumented run would reach that cap in roughly 4.5 minutes. This is an estimate for
the current two creatures, not a promised duration. [Daily cleanup](log-cleanup.md)
removes expired recordings; a `.keep-logs` marker in the run directory preserves QA evidence.

## Three separate capabilities

1. **Trace inspection** explains the branches one creature actually evaluated.
2. **Recorded-state playback** displays the authoritative match at a recorded tick,
   with pause/play, speed, seeking and both creatures' corresponding AI traces.
3. **Deterministic re-simulation** re-runs game logic to reproduce or investigate a
   bug. That needs the initial private state/RNG, exact accepted input ordering,
   lifecycle events, matching executable/content and state-hash comparisons.

This checkpoint implements the second capability alongside a faster first one.
Current AI journals alone are insufficient: they omit the other entities' complete
state, some lifecycle transitions and the complete input stream. Neither a selected
intent nor its textual explanation reconstructs the whole match.

## Fix the browsing work before adding views

The old inspector recreated all 2,048 timeline items on selection, parsed/validated
128-record snapshots on the UI thread every 250 ms, and formatted hidden tabs.
Replace this with a canvas that draws only visible rows, immutable pinned records,
a background file/validation worker, debounced search and lazy tab formatting.
Keep scene-tree work on the UI thread, following the
[Godot thread-safety boundary](https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html).

The graph consumes existing node IDs and parent IDs; AI behavior does not change.
Place the root above its children, retain rejected/skipped alternatives, and show
status words as well as color. Highlight the executed choices without turning a
false condition into a true one. Keep status styling in `trace_palette.gd` and layout,
pan/zoom and selection in `decision_graph.gd`, making future presentation changes local.

## Recorded-match contract

- Capture a complete public session after each 60 Hz simulation tick, including
  trainers, creatures, map, round, summon state and authoritative animation clocks.
  Reuse the validated public packet contract at 1/256 world-unit position precision.
  Render available recorded frames directly; this is not a capture of client prediction
  or network interpolation artifacts.
- Queue fixed-size copies to the existing writer. No JSON or file I/O on the host
  simulation or creature threads. Preserve trace/world queue ordering so each world
  frame can embed the two traces from its own tick. Missing traces are explicit.
- Write `match.replay.jsonl` with a versioned header, run/content/protocol identity,
  seed and tick rate. Each independent frame contains the session packet and actual
  matching traces, so rotating an AI journal does not destroy QA trace playback.
- Bound one recording to 128 MiB; report a full/failed recorder. Do not silently
  overwrite the start of a match. A host capture sequence and simulation ticks expose
  dropped frames. Playback stops at a gap until the reviewer explicitly seeks past it.
- A graceful close writes an end record. An interrupted last line is recoverable but
  shown as incomplete; corrupt interior records and mismatched identity are rejected.
- Build a bounded file index on a background thread and load requested frames by
  offset. Do not load an entire match's trace dictionaries into UI memory.

## QA viewer

Use a standalone development scene with no network connection or player input.
Reuse arena/character/trainer drawing resources; drive poses from the selected host
tick rather than the viewer's wall clock. Seeking backward or across a round must
clear obsolete entities. Pause freezes positions and animation. Playback speed and
camera pan/zoom change presentation only.

One replay cursor controls the arena and P1/P2 trace panels together. If a trace is
absent, show that absence rather than a previous tick's decision. Selection of a
branch reveals its actual operands and metadata. Controls: open recording, play/pause,
previous/next frame, seek, and speed. Opening playback must not disturb a live arena.

Generated diagnostics already live in ignored `build/`. Also ignore exported logs,
rotated AI journals and replay files outside that directory; retain source fixtures
and authored JSON. No tracked source files should be removed to accomplish this.

## Later deterministic re-simulation

Before promising bug reproduction by executing the AI again, add a versioned initial
`Simulation` checkpoint, private per-creature RNG and eventual persistent memories,
accepted commands tagged with host application tick and intra-tick order, connect/
disconnect/reset events, configuration changes, and canonical periodic state hashes.
Reset from a checkpoint, inject those events, and compare each hash while reporting
the first divergence. Future cognition must use logical work budgets, not CPU timing.
Source/asset revisions need archival too. Recorded-state playback cannot resume or
branch a live simulation and is not a pixel-exact video of hot-reloaded artwork.

## Acceptance

Verified with Godot 4.6 and local Odin on this PC:

- Full 2,048-record browsing benchmark: headless selection p95 decreased from
  **18,446 µs to 941 µs**. The final two native inspectors measured **1,344 µs** and
  **1,240 µs**, drawing 15 visible rows each. Selecting records never rebuilt the
  timeline. Snapshot parsing remains work on a separate thread; these are local
  selection-handler measurements, not universal whole-frame latency guarantees.
- Five pure AI tests and 32 server tests passed, including a separate debug build
  that exercises the writer. The writer test compares all 60 recorded packets to
  their corresponding production simulation states, validates seed and both matching
  AI traces, and checks the final record. A small-cap test verifies bounded size,
  preservation of the start, captured-versus-saved counts and reported drops. The
  existing serial/threaded comparison and no-allocation normal tick test still pass.
- The graphical process suite passed with two real inspectors, two players and a
  delayed audience. Its **1,217-frame** recording contains real trainer input and
  autonomous creature movement, with **zero host queue drops** and no writer errors.
  Both AI tabs match the selected world tick. Backward/forward seeking restores
  identical entity positions and animation frames; pause freezes both, including
  rejection of an already requested worker result. Play, speed, end restart,
  frame/event stepping and root-above-child layout passed.
- Reader/viewer tests reject wrong content/schema, corrupt interior frames, invalid
  packets, mismatched/duplicate AI traces, out-of-order sequences and oversized
  lines. Incomplete final lines recover with a warning. Playback pauses at a missing
  frame; explicit seeking crosses it. An absent trace displays absence. Rotating
  journals does not remove the traces embedded in replay frames.
- Existing native-window close, reload, audience isolation, telemetry-disabled,
  release-host gate and owned-process cleanup checks passed. The requested Archer/
  Orc Village launch also produced a finalized recording, and `make replay` opened
  its retained project in a native Godot window without script errors.
- `make check_character_ai check_dev` passed after the recorder changes, including
  live networked movement and the existing save/reload/failure workflow. Evidence:
  `build/replay-final-regressions.log` and
  `build/verification/dev-check-20260910-134522-379835/`.
- Three cleanup tests passed, including a real temporary process that protects old
  logs while alive and allows deletion after exit. Generated log/rotation/replay
  ignore patterns were checked; no tracked log files needed removal. Cron installation
  and retention details are in [log cleanup](log-cleanup.md).

Run `make check_ai_debugger` for unit and headless integration checks, or
`python3 tests/ai_debugger_check.py --graphical` for native windows and screenshots.
The integration invokes `tests/replay_check.gd` on a real host recording.

Local evidence: `build/ai-browse-profile/{before,after}.log`,
`build/replay-debug-host-check.log`, and
[`build/verification/ai-debugger-20260910-134336-375954/`](../build/verification/ai-debugger-20260910-134336-375954/).
That directory includes `replay-check.json`, `replay-check.log`, native-window records,
per-window performance assertions and the visually inspected
[`replay-arena-p1.png`](../build/verification/ai-debugger-20260910-134336-375954/replay-arena-p1.png)
and [`replay-tree-p1.png`](../build/verification/ai-debugger-20260910-134336-375954/replay-tree-p1.png).
Controls were exercised through their handlers and synthetic input, not a physical
mouse/keyboard session. Generated evidence is ignored and subject to log retention.

Unimplemented: deterministic re-simulation/checkpoint resume, branching an old match,
exact historical hot-reload artwork, and native worker breakpoints. Vision, mood,
combat and learning remain the following roadmap work; playback invents none of them.
