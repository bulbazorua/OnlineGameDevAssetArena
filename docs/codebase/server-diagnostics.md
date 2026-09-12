# Server diagnostics: the owned writer and its feeds

Code: [`server/diagnostics/`](../../server/diagnostics) (package `diagnostics`), wired from
[`server/host_simulation.odin`](../../server/host_simulation.odin) and
[`server/main.odin`](../../server/main.odin). Viewers: [`client/dev/`](../../client/dev).
Handback: [diagnostics coding-agent report](../server-diagnostics-coding-agent-report.md).
Package map: [server architecture](server-architecture.md).

The package owns the job queue, the writer thread, the per-creature history, the journals, the live feeds and the
match recording. The host hands it copies during the tick; the writer thread turns them
into versioned files; the Godot developer windows read those files. Nothing in this
package changes a creature's knowledge, decision, movement, memory or learning, and the
simulation packages never import it.

## How one feed flows, end to end

```text
host_simulation_step (main thread)
    simulation.battle_resolve_decisions            authoritative result
    diagnostics.record_decisions                   append the Outcome trace node, copy one Record per creature, enqueue
    host_capture_world -> protocol_encode_session  encode once, only when a recorder exists
        diagnostics.capture_world                  copy packet bytes + valid length into an owned World_Capture, enqueue
    diagnostics.capture_scent                      quantize the field into the scent slot under scent_mutex
writer_run (writer thread)
    drain_queue -> consume                         Record: fan, delivery clock, history, journal_write
                                                   World_Capture: sense_world, replay_write_frame
    publish_senses / publish_search                senses.json, search.json (fresh sample or 50 ms)
    publish_scent                                  scent.json (100 ms) from a copy of the scent slot
    publish_owner x2                               ai-1.json, ai-2.json (250 ms), draining between them
    replay_close at stop                           end record, then the journals close
```

| Feed | File under `--dev-ai-dir` | Schema | Captured on the main thread by | Written by | Read by |
| --- | --- | --- | --- | --- | --- |
| Decision journal | `ai-<owner>.jsonl` (+ `.1` … `.3`) | trace 5 (`TRACE_SCHEMA`) | `record_decisions` | `journal_write` | `client/dev/ai/ai_debug_window.gd` (live reader) |
| History snapshot | `ai-<owner>.json` | trace 5 | same records | `publish_owner` | `ai_debug_window.gd` |
| Live senses | `senses.json` | 4 (`SENSE_SCHEMA`) | same records + world capture | `publish_senses` | `client/dev/senses/senses_window.gd`, `client/dev/sense_overlay.gd` |
| Private search | `search.json` | 2 (`SEARCH_SCHEMA`) | same records + world capture | `publish_search` | `client/dev/search/search_overlay.gd`, `client/dev/senses/exploration_memory_panel.gd` |
| Host scent field | `scent.json` | 1 (`SCENT_SCHEMA`) | `capture_scent` | `publish_scent` | `client/dev/scent_overlay.gd`, `client/dev/senses/olfaction_page.gd` |
| Match recording | `match.replay.jsonl` | envelope 5 (`REPLAY_SCHEMA`), protocol from the host | `capture_world` | `replay_write_frame`, `replay_close` | `client/dev/ai/replay_window.gd` |

The viewer keeps three kinds of data apart, and the package keeps them apart at the
source: developer-only host truth (`scent.json`, the `host_audit` and
`host_scent_audit` fields of a record) comes from the field and the receptor audits;
private readings (`senses.json`, the `input` of a record) come from the copied
`Brain_Request`; personal exploration memory (`search.json`) comes from the adopted
agent's `after` state. Nothing infers an emitter's identity, and no host value is fed
back into a brain.

## Public production operations

These are the only procedures the host calls. Operations taking a `^Diagnostics`
accept `nil` as "diagnostics disabled" and return without work.

| Operation | Called from | What it does with its inputs |
| --- | --- | --- |
| `options_valid(dev, bind, directory, run_id)` | `main.odin` `run_host`, before anything is loaded | Pure check of four launch values. Both strings empty means a normal host. Otherwise a debug build, `--dev`, `127.0.0.1`, an absolute directory and a run ID are required; the same two rejection messages as before. |
| `open(directory, run_id, fingerprint, protocol_version, catalog, log_limit, seed) -> ^Diagnostics` | `main.odin` `run_host`; host tests | Returns `nil` in a release build or with an empty directory. Borrows `directory` and `run_id` until `close` returns. Allocates the one state, hex-encodes the fingerprint, copies every arena's opacity grid for the writer, stores the host's protocol version for the replay header, starts the writer thread. |
| `close(^Diagnostics)` | `main.odin` (deferred); host tests | Requires the caller to stop all capture calls first. Sets `stopping` under the mutex, wakes the writer, joins it, then frees the grid copies, the fingerprint string and the state. It does not reject new jobs. |
| `record_decisions(debug, sim, requests, &responses, outcomes)` | `host_simulation.odin`, after `battle_resolve_decisions` | Appends the confirmed `Outcome` node to each response trace (the one intentional mutation of caller-owned temporary data, exactly once per creature per tick), then copies request, response, adopted agent, confirmed result and both receptor audits into a `Record` and enqueues it. |
| `capture_world(debug, session, packet)` | `host_capture_world` in `host_simulation.odin` | Numbers the capture, copies `packet` (the host's encoded session, valid for its whole length) into the owned `World_Capture.packet`, reads round, tick, map, phase and entity IDs from the borrowed session, enqueues. |
| `capture_scent(debug, battle, session)` | `host_simulation.odin`, last step of the tick | Under `scent_mutex`: clears the slot outside a bound arena; otherwise, when the field stepped since the last copy, quantizes levels and ages into the slot. No allocation, JSON or file work. |

Public types and constants exist for two boundaries only: the host's handle and inputs
(`Diagnostics`, `WORLD_PACKET_BYTES`, `LOG_BYTES`) and the recorded file contracts that
tests decode (`Snapshot`, `Record_View`, `Vision_Audit_View`, `Sense_Snapshot`,
`Sense_Record`, `Sense_World`, `Search_Snapshot`, `Search_Record`, `Scent_Snapshot`,
`Scent_Field`, `Replay_Header`, `Replay_Frame`, `Replay_End`, and the five schema
numbers plus `RECORD_LIMIT`). `WORLD_PACKET_BYTES` is the owned packet storage; the host
test checks the codec's array fits it, so the two packages agree without one importing
the other.

## Private procedures, by file

| File | Package-private (`@(private)`) | File-private |
| --- | --- | --- |
| `diagnostics.odin` | `QUEUE_CAPACITY`, `HISTORY`, `OLD_LOGS` | |
| `queue.odin` | `Job`, `enqueue` (numbers a record), `push` (drop-when-full) | |
| `record.odin` | `Record`, `Grid_Copy`, `Fan_Cache`, `Sense_Delivery`, `Delivery_Clocks`, `attach_fan`, `note_delivery`, `record_view` | `delivery_note` |
| `writer.odin` | `report_error`, `writer_run` (thread entry) | `consume`, `Drain`, `drain_queue`, `publish_live` |
| `journal.odin` | `journal_write`, `publish_owner` | `journal_rotate` |
| `replay.odin` | `REPLAY_LIMIT_BYTES`, `REPLAY_LINE_LIMIT`, `World_Capture`, `Replay_Writer`, `hex`, `replay_write_frame`, `replay_close` | `replay_write_line` |
| `senses.odin` | `SENSE_BYTES`, `sense_record`, `sense_collect`, `publish_senses` | |
| `search.odin` | `SEARCH_BYTES`, `publish_search` | |
| `scent.odin` | `SCENT_BYTES`, `Scent_Capture`, `publish_scent` | |

The compiler enforces that the host cannot name any of these. A private type may still
be a field of the public `Diagnostics` state or the result of a test probe; Odin hides
the name, not the memory.

### Test-only path

`probe_test.odin` is compiled like every other file, but nothing in production calls it.
It exists so the host package's integration tests can keep their original assertions
without the writer internals becoming host API:

| Probe | Used by |
| --- | --- |
| `test_open_without_writer()` | The serial/threaded equivalence, audience isolation and trace-loss tests: a state with no writer thread, so the queue fills and drops deterministically. |
| `test_queue_full`, `test_dropped` | Their saturation assertions (queue at capacity, drops counted). |
| `test_queued_world(debug, position)` | The host packet seam test: what `host_capture_world` queued, byte for byte. |
| `test_scent_capture(debug)` | The host scent wiring test: the slot after `host_simulation_step`. |

## Who owns which field

`Diagnostics` is allocated once in `open` and freed once in `close`; it is never moved.
The table is the ownership convention. Only the two mutexes are compiler-visible;
everything else is a rule kept by the thread that runs each procedure.

| Fields | Owner | Notes |
| --- | --- | --- |
| `queue`, `head`, `count`, `stopping`, `dropped` | Shared, under `mutex` | `push` (main) and `drain_queue` (writer) hold the mutex. `close` sets `stopping` under it. |
| `scent_capture` | Shared, under `scent_mutex` | `capture_scent` writes, `publish_scent` copies out. The lock covers one 64 KiB copy at most. |
| `scent_captured_steps` | Main thread | Which field step the slot already holds. Written under `scent_mutex` for convenience, never read by the writer. |
| `sequence[owner]`, `world_sequence` | Main thread | Counters that include dropped jobs, so a gap in a journal is visible. `replay_close` reads `world_sequence` and `dropped` on the writer thread only after `close` stopped the producer. |
| `history`, `totals`, `oversized`, `files`, `bytes`, `last_error`, `publish_us`, `fans`, `delivery`, `sense_world`, `replay`, `grids` | Writer thread | Filled by `consume` and the publishers. `grids` is prepared in `open` before the thread starts and read only. |
| `directory`, `run_id` | Borrowed from the caller | Keep the backing bytes alive and unchanged until `close` returns. Read by both threads; not copied or freed by the package. |
| `fingerprint`, `protocol_version`, `origin`, `origin_unix_us`, `log_limit`, `seed` | Immutable after `open` | Read by both threads. The package owns and frees the fingerprint string. |

### When borrowed inputs become owned copies

- `record_decisions` reads `sim.session`, `sim.battle.agents`, `sim.battle.receptors` and
  the request/response values synchronously and copies them into a `Record` on the stack,
  which `enqueue` copies into the queue slot. The record holds no pointer.
- `capture_world` receives a slice into the host's stack array from
  `protocol_encode_session`; `copy` moves the bytes into `World_Capture.packet` before the
  call returns, and `packet_size` is the copied length. The round, tick, map, phase and
  entity IDs are read from the borrowed session at the same moment.
- `capture_scent` reads the live field under `scent_mutex` and writes quantized bytes
  into the slot; the field pointer is not retained. `publish_scent` copies the whole slot
  into a heap temporary under the same lock and then encodes without holding it.
- The writer's `Record_View` slices (`nodes`, `candidates`, `sight_fan`) point into the
  writer-owned history entry only for the duration of one `json.marshal`.

## Gating, queue and shutdown behavior

- **Build and launch gating.** `open` returns `nil` unless `ODIN_DEBUG`; `options_valid`
  rejects any diagnostic option in a release build with "Telemetry requires a debug host
  build." and in a debug build without `--dev`, the loopback bind, an absolute directory and
  a run ID. A release host therefore runs normally without diagnostics and refuses them
  when asked (`tests/ai_debugger_check.py` builds and checks that gate).
- **Queue.** 256 jobs; a full queue drops the newest job and counts it; the producer
  never waits. Per-owner sequence numbers and the world sequence still advance for dropped
  jobs.
- **Journals.** One record over 48 KiB is counted as oversized and skipped. A journal
  rotates at `log_limit` (8 MiB by default, 1 KiB minimum) into three retained segments.
- **Recording.** The header carries the host's protocol version, the simulation rate, run
  ID, fingerprint, seed and trace schema. A frame line over 120 KiB keeps the packet and
  drops the traces (counted). The file stops at 128 MiB with status `size_limit`; write
  and encode failures set their own status and the simulation continues.
- **Cadence.** Live senses and search publish on a fresh sample or every 50 ms, scent
  every 100 ms, the two history snapshots every 250 ms with a drain between them so a
  fresh sample never waits behind both.
- **Shutdown.** The caller stops producing captures before calling `close` and must not
  start another capture while it runs. `close` signals the writer to drain queued work;
  it does not prevent new jobs. The writer publishes every feed once more, writes the
  replay end record with the final counts, closes the journals and exits. `close` joins
  the writer, then frees the owned storage. Borrowed strings can be released afterward.
- **Errors.** Every failure is reported once on stderr and kept in `last_error` for the
  snapshot's `writer_error`. Nothing propagates to the host loop.

## Compatibility

File names, field names, units, enum names, class ordering, sequence rules and the
run/fingerprint binding are those of the pre-extraction host. Recorded contracts:
protocol 11 (from the host codec), trace 5, senses 4, search 2, scent 1, replay envelope 5.
Historical documents name the old files and identifiers; read them with this table.

| Before (host package) | Now (`diagnostics`) |
| --- | --- |
| `dev_ai_debug.odin`: `AI_Debug`, `ai_debug_open/close`, `ai_debug_options_valid(Options)`, `ai_debug_record_decisions`, `ai_debug_enqueue/push`, `ai_debug_writer`, `ai_debug_log`, `ai_debug_publish_owner`, `ai_debug_view`, `ai_debug_attach_fan`, `ai_debug_note_delivery`, `ai_debug_error` | `diagnostics.odin` (`Diagnostics`, `open`, `close`, `options_valid(dev, bind, directory, run_id)`, `record_decisions`), `queue.odin` (`enqueue`, `push`), `writer.odin` (`writer_run`, `report_error`), `journal.odin` (`journal_write`, `journal_rotate`, `publish_owner`), `record.odin` (`record_view`, `attach_fan`, `note_delivery`) |
| `AI_DEBUG_QUEUE`, `AI_DEBUG_HISTORY`, `AI_DEBUG_LOG_BYTES`, `AI_DEBUG_OLD_LOGS`, `AI_DEBUG_SCHEMA`, `AI_DEBUG_RECORD_LIMIT` | `QUEUE_CAPACITY`, `HISTORY`, `LOG_BYTES`, `OLD_LOGS`, `TRACE_SCHEMA`, `RECORD_LIMIT` |
| `AI_Debug_Job`, `AI_Debug_Record`, `AI_Debug_Record_View`, `AI_Debug_Snapshot`, `Debug_Grid` | `Job`, `Record`, `Record_View`, `Snapshot`, `Grid_Copy` |
| `dev_replay.odin`: `Replay_Capture`, `ai_debug_capture_world(debug, session)`, `replay_capture`, `ai_debug_hex` | `replay.odin`: `World_Capture`, `capture_world(debug, session, packet)`, `replay_write_frame`, `hex` |
| `dev_senses.odin`: `Sense_Debug_World/Record/Snapshot`, `SENSE_DEBUG_SCHEMA/BYTES`, `sense_debug_record/collect`, `ai_debug_publish_senses` | `senses.odin`: `Sense_World/Record/Snapshot`, `SENSE_SCHEMA/BYTES`, `sense_record/collect`, `publish_senses` |
| `dev_search.odin`: `Search_Debug_Record/Snapshot`, `SEARCH_DEBUG_SCHEMA/BYTES`, `ai_debug_publish_search` | `search.odin`: `Search_Record/Snapshot`, `SEARCH_SCHEMA/BYTES`, `publish_search` |
| `dev_search.odin`: `dev_log_search_reset` | Stays in the host, now in `network.odin` beside its only caller |
| `dev_scent.odin`: `Scent_Debug_Capture/Field/Snapshot`, `SCENT_DEBUG_SCHEMA/BYTES`, `ai_debug_capture_scent`, `ai_debug_publish_scent` | `scent.odin`: `Scent_Capture/Field/Snapshot`, `SCENT_SCHEMA/BYTES`, `capture_scent`, `publish_scent` |
| `dev_scenario.odin`, `dev_scenario_test.odin` | `scenario.odin`, `scenario_test.odin` in the host (same procedures) |
| `PROTOCOL_HEADER[4]` read inside the replay header | `protocol_version` passed by the host to `open` |

## Tests and commands

```sh
odin test server/diagnostics -out:build/diagnostics_tests            # no ENet; senses, journal, scent, replay, queue, options
odin test server/diagnostics -debug -out:build/diagnostics_tests_debug
make check_session      # content, simulation, diagnostics and host packages, normal builds
make check_ai_debugger  # the same four in -debug builds, then tests/ai_debugger_check.py (real workers, inspectors, release gate)
```

Placement: capture, projection, journal, replay-frame and scent-publication behavior is
tested inside the package (`*_test.odin` there). Anything that needs the host step, the
codec, the brain threads or the audience history stays in `server/*_test.odin`:
`diagnostics_host_test.odin` covers the packet seam, the disabled path, the scent wiring
and the end-to-end journal/recording run; `host_simulation_test.odin` and
`brain_workers_test.odin` keep the serial/threaded equivalence, trace-loss, lifecycle and
delivered-coverage runs.

## Where a new diagnostic output belongs

1. Decide which thread has the data. A per-decision value goes into `Record` in
   `record.odin` and is filled by `record_decisions`; a world-level value goes into
   `World_Capture`; a bulk field goes into its own capture slot with its own mutex, like
   `capture_scent`.
2. Copy on the main thread, never point: the capture must own its bytes before it returns.
3. Project and write on the writer thread in a new `publish_*` procedure, called from
   `writer_run` on a stated cadence, with a byte ceiling and a schema constant.
4. Keep the procedure `@(private)`; the host needs a new public operation only for a new
   capture entry point, and that entry point must accept `nil`.
5. Version the file, extend the Godot reader, and add the package test that decodes the
   file plus the host test that proves the wiring if the capture entry point is new.
