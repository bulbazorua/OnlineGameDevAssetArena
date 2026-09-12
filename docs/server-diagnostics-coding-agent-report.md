# Server diagnostics extraction: coding-agent report

Status: **READY FOR INDEPENDENT REVIEW, NOT ACCEPTED.**

Date: 2026-09-12 (UTC). Packet: [Odin diagnostics cleanup](delegation.md).
Architecture: [server diagnostics](codebase/server-diagnostics.md),
[server architecture](codebase/server-architecture.md).
Evidence root: `build/verification/server-diagnostics-20260912T003752Z/` (`.keep-logs`).

The five host `dev_*.odin` diagnostic files are now one package, `server/diagnostics/`,
with six public operations. The host keeps the codec and the launch options and passes
the encoded packet, its valid length and the protocol version across the boundary. No
schema, filename, unit, cadence, limit, drop policy or gameplay path changed; the
mechanical audit in section 4 lists every non-mechanical line.

## 1. Source identities and evidence layout

| Item | Value |
| --- | --- |
| Starting tree | Commit `570d66963c9e1b9e0faf3548be65f4f92fe28f84` plus the accepted dirty work (44 status entries: `baseline/git-status.txt`, `git-diff-unstaged.patch`, `git-untracked.txt`). |
| Starting manifest | `baseline/working-tree-manifest.sha256` (1,076 paths, `working-tree-paths.txt`), excluding `build/`, `.git/`, `client/.godot/`, `__pycache__`, `CLAUDE.md` and `AGENTS.md`. Protected scopes: `baseline/protected-*.sha256` with matching `-paths.txt` lists for `client`, `tools`, `tests`, `server/ai`, `server/perception`, `server/observations`, `server/content`, `server/simulation`. |
| Buildable snapshot | `baseline/source/` = `client`, `server`, `tests`, `tools`, `docs`, `Makefile` plus a copy of `build/deps/libenet.a`; `baseline/source-manifest.sha256`; `snapshot-vs-working-tree.diff` is empty for every buildable path. |
| Environment | `baseline/environment.txt`: Odin `dev-2026-03-nightly`, Godot `4.6.stable.official.89cea1439`, Python 3.12.3, Linux 7.0.0-31-generic, 32 cores, `DISPLAY=:0`. Debug flags `odin build server -out:build/server -debug -extra-linker-flags:"-L$PWD/build/deps"`; release flags the same with `-o:speed`. |
| Final manifest | `candidate/working-tree-manifest.sha256` and `candidate/working-tree-paths.txt`, taken after every gate and after this report was written; `candidate/pre-gate/` is the manifest taken before the gates; `candidate/protected-*` compared against the baseline scopes (section 7). |
| Exact delta | `candidate/candidate-vs-baseline.patch` (server, Makefile, docs), `candidate/mechanical-audit.txt` (section 4). |

Manifests are built with `find -print0 | sort -z | xargs -0 sha256sum`, so filenames with
spaces (the Tiny Swords assets) are preserved. The path lists detect new unlisted files.

## 2. Responsibility and file map

| Starting file | Responsibility | Now |
| --- | --- | --- |
| `server/dev_ai_debug.odin` | State and lifetime, options gate, queue, writer thread, journals, snapshots, record assembly, fan cache, delivery clocks | `server/diagnostics/diagnostics.odin` (state, `options_valid`, `open`, `close`, `record_decisions`), `queue.odin` (`Job`, `enqueue`, `push`), `record.odin` (`Record`, views, `attach_fan`, `note_delivery`), `writer.odin` (`writer_run`, `drain_queue`, `consume`, `report_error`), `journal.odin` (`journal_write`, `journal_rotate`, `publish_owner`, `Snapshot`) |
| `server/dev_replay.odin` | World capture, replay header/frames/end, limits | `server/diagnostics/replay.odin` (`capture_world` now takes the host packet; header uses the stored protocol version) |
| `server/dev_senses.odin` | Live senses projection and publication | `server/diagnostics/senses.odin` |
| `server/dev_search.odin` | Search publication; host reset notice | Publication in `server/diagnostics/search.odin`; `dev_log_search_reset` unchanged in `server/network.odin` beside its only caller |
| `server/dev_scent.odin` | Scent capture slot and publication | `server/diagnostics/scent.odin` |
| `server/dev_scenario.odin`, `dev_scenario_test.odin` | Launch scenario | Renamed `server/scenario.odin`, `server/scenario_test.odin`; contents unchanged |
| `server/host_simulation.odin` | Tick coordination | Imports `diagnostics`; adds `host_capture_world` (encode only when a recorder exists, hand over the slice) |
| `server/main.odin` | Options and lifecycle | Calls `diagnostics.options_valid(dev, bind, dir, run)`, `diagnostics.open(..., int(PROTOCOL_HEADER[4]), ...)`, `diagnostics.close` |
| `server/dev_senses_test.odin` | Projection and clock tests | `server/diagnostics/senses_test.odin` |

Dependency direction after the change: `main → diagnostics → simulation/content/ai/perception/observations`;
`main → simulation` and the codec stay in the host. The package imports nothing from the
host, ENet, the client or the tools (`grep -n '^import' server/diagnostics/*.odin`). No
`common`, `shared` or protocol package was created; the host passes the packet and the
protocol version as values.

## 3. Public API and visibility audit

Public production operations (`server/diagnostics/*.odin` without `@(private)`):

| Operation | Production caller | Justification |
| --- | --- | --- |
| `options_valid(dev, bind, directory, run_id) -> bool` | `main.odin` | Launch gate on the four values it checks; no `Options` crosses the boundary |
| `open(directory, run_id, fingerprint, protocol_version, catalog, log_limit, seed) -> ^Diagnostics` | `main.odin` | Lifecycle; the protocol version is the second real host dependency, passed as a value |
| `close(^Diagnostics)` | `main.odin` (deferred) | Lifecycle |
| `record_decisions(debug, sim, requests, &responses, outcomes)` | `host_simulation.odin` | Decision recording after both authoritative resolutions |
| `capture_world(debug, session, packet: []u8)` | `host_capture_world` in `host_simulation.odin` | World capture from the host-encoded packet |
| `capture_scent(debug, battle, session)` | `host_simulation.odin` | Scent capture into the mutex-guarded slot |

Public types and constants: `Diagnostics` (the handle), `WORLD_PACKET_BYTES` (owned packet
storage, checked against the codec by the host test), `LOG_BYTES` (default journal limit
used as `open`'s default), the file contracts `Snapshot`, `Record_View`, `Vision_Audit_View`,
`Sense_Snapshot`, `Sense_Record`, `Sense_World`, `Search_Snapshot`, `Search_Record`,
`Scent_Snapshot`, `Scent_Field`, `Replay_Header`, `Replay_Frame`, `Replay_End`, and the
recorded numbers `TRACE_SCHEMA` (5), `SENSE_SCHEMA` (4), `SEARCH_SCHEMA` (2),
`SCENT_SCHEMA` (1), `REPLAY_SCHEMA` (5), `RECORD_LIMIT` (48 KiB). The host tests decode the
files through these types; the Godot viewers read the same fields by name.

Package-private (`@(private)`): `QUEUE_CAPACITY`, `HISTORY`, `OLD_LOGS`, `REPLAY_LIMIT_BYTES`,
`REPLAY_LINE_LIMIT`, `SENSE_BYTES`, `SEARCH_BYTES`, `SCENT_BYTES`, `Job`, `Record`, `Grid_Copy`,
`Fan_Cache`, `Sense_Delivery`, `Delivery_Clocks`, `World_Capture`, `Replay_Writer`,
`Scent_Capture`, `enqueue`, `push`, `attach_fan`, `note_delivery`, `record_view`,
`report_error`, `writer_run`, `journal_write`, `publish_owner`, `hex`, `replay_write_frame`,
`replay_close`, `sense_record`, `sense_collect`, `publish_senses`, `publish_search`,
`publish_scent`. File-private: `delivery_note`, `consume`, `Drain`, `drain_queue`,
`publish_live`, `journal_rotate`, `replay_write_line`. The host cannot name any writer
step, queue operation, rotation, view conversion, hex helper, replay write or `publish_*`.

Test-only path (`server/diagnostics/probe_test.odin`, public, never called by production):
`test_open_without_writer`, `test_queue_full`, `test_dropped`, `test_queued_world`,
`test_scent_capture`. They replace the host tests' former `new(AI_Debug)` construction and
direct `debug.count`/`debug.dropped`/`debug.scent_capture` reads. Odin compiles the file
into every build; it adds no behavior.

Field ownership is a convention, not compiler-enforced: Odin has no field privacy, so any
importer can write `debug.history`. The ownership table in
[server-diagnostics.md](codebase/server-diagnostics.md#who-owns-which-field) states which
thread owns each field and which two are mutex-guarded.

## 4. Mechanical moves versus deliberate changes

`candidate/mechanical-audit.txt` applies the rename map to the five old files, strips
comments, imports and attributes, and lists every source line that is not identical on the
other side. Everything not listed below moved line for line.

Renames (no behavior): `AI_Debug → Diagnostics`; `ai_debug_<x> → <x>` with these exceptions:
`ai_debug_writer → writer_run`, `ai_debug_log → journal_write`, `ai_debug_view → record_view`,
`ai_debug_error → report_error`, `ai_debug_drain → drain_queue`, `replay_capture → replay_write_frame`,
`ai_debug_hex → hex`; `AI_DEBUG_QUEUE → QUEUE_CAPACITY`, `AI_DEBUG_SCHEMA → TRACE_SCHEMA`, other
`AI_DEBUG_*` and `*_DEBUG_*` constants drop the prefix; `AI_Debug_Job/Record/Record_View/Snapshot → Job/Record/Record_View/Snapshot`;
`Debug_Grid → Grid_Copy`, `Writer_Drain → Drain`, `Replay_Capture → World_Capture`, `*_Debug_* types` drop `Debug_`.

Dependency-seam changes:

1. `options_valid` takes `(dev, bind, directory, run_id)` instead of `Options`. Same two
   messages, same order of checks, same debug-build gate.
2. `open` takes `protocol_version: int`, stored in `Diagnostics.protocol_version` and written
   into `Replay_Header.protocol_version` where `int(PROTOCOL_HEADER[4])` was read before.
3. `capture_world(debug, session, packet)` copies the host's slice into
   `World_Capture.packet` (`[WORLD_PACKET_BYTES]u8`, 164 as before) and stores the copied
   length; `host_capture_world` in the host encodes with `protocol_encode_session` and slices
   with `protocol_session_size` only when `debug != nil`.

Readability changes: the journal rotation loop became file-private `journal_rotate`
(identical body); the local `hex` in the frame writer is `packet_hex` so it no longer shadows
the procedure; `@(private)` attributes and short plain-language comments were added.

Deletion: `ai_debug_publish` (five lines) had no caller in the starting tree and was not
moved.

Host-only: `dev_log_search_reset` moved verbatim to `network.odin` (with `core:math`);
`dev_scenario.odin` and its test were renamed by `mv`, contents unchanged.

## 5. Threads, lifetime and packet ownership

| Boundary | Producer | What crosses | When it becomes owned |
| --- | --- | --- | --- |
| `record_decisions` | Main thread, after `battle_resolve_decisions` | Copies of `Brain_Request`, `Brain_Response` (with the appended Outcome node), the adopted agent, both audits, the confirmed result | Built into a stack `Record`, copied into the queue slot by `enqueue → push` under `mutex` |
| `capture_world` | Main thread, after the battle phase | A slice into the host's `[164]u8` stack packet, `server_tick`, `round_id`, `map_id`, phase, entity IDs | `copy` into `World_Capture.packet` before return; `packet_size` is the copied length; then queued by `push` |
| `capture_scent` | Main thread, last step | Quantized levels/ages of the live field | Written into `scent_capture` under `scent_mutex`; the field pointer is not retained |
| Queue → writer | Writer thread `drain_queue` | Whole `Job` values | Copied out of the slot under `mutex`; the writer owns history, fans, clocks, files, replay state |
| `publish_scent` | Writer thread | The slot | Copied to a heap temporary under `scent_mutex`, encoded outside the lock |

Disabled path: with `debug == nil`, `host_capture_world` returns before encoding, and every
package operation returns immediately; the release build's `open` returns `nil` unconditionally.
The state is one allocation from `open` to `close`; `close` stops the producer, joins the
writer after it drained, published, wrote the replay end record and closed the journals,
then frees the grid copies, the fingerprint string and the state.

## 6. Changed files and test map

Changed or added under `server/`: `diagnostics/{diagnostics,queue,record,writer,journal,replay,senses,search,scent}.odin`,
`diagnostics/{probe,options,queue,replay,scent,senses,journal}_test.odin`, `diagnostics_host_test.odin`,
`host_simulation.odin`, `main.odin`, `network.odin`, `brain_workers_test.odin`, `host_simulation_test.odin`,
`scenario.odin`, `scenario_test.odin` (renamed). Removed: `dev_ai_debug.odin`, `dev_replay.odin`,
`dev_senses.odin`, `dev_search.odin`, `dev_scent.odin`, `dev_senses_test.odin`, `dev_scenario.odin`,
`dev_scenario_test.odin`. Also: `Makefile` (two discovery lines and one help line),
`docs/codebase/server-diagnostics.md` (new), `docs/codebase/server-architecture.md`,
`docs/project-structure.md`, and one-line file references in `docs/codebase/{arena-sense-overlay,live-senses-inspector,olfaction,opponent-search}.md`.
No Godot, content, fixture, tool, `tests/` or lower-package file changed (section 7).

Baseline test → destination (24 host tests before; 21 host + 10 package after):

| Baseline test (file) | Destination | Assertions |
| --- | --- | --- |
| `live_senses_drop_old_lifecycles_without_waiting_for_new_decisions` (`dev_senses_test`) | `diagnostics/senses_test.odin` | Unchanged; identifiers renamed |
| `live_senses_clock_keeps_original_delivery_and_never_invents_a_missing_time` | `diagnostics/senses_test.odin` | Unchanged |
| `live_senses_envelope_fits_bounded_reader_at_maximum_evidence` | `diagnostics/senses_test.odin` | Unchanged |
| `worst_case_record_fits_the_declared_ceilings` (`brain_workers_test`) | `diagnostics/journal_test.odin` with the `extreme_record` fixture | Unchanged; still prints 41,232 of 49,152 bytes |
| `oversized_diagnostics_are_dropped_and_counted_without_touching_gameplay` | `diagnostics/journal_test.odin` | Unchanged assertions; the 32-byte lobby packet is a literal byte pattern instead of `protocol_encode_session` (the packet bytes were never asserted) |
| `debug_journals_rotate_and_shutdown_publishes_complete_history` | `server/diagnostics_host_test.odin` (host: needs the host step and the codec) | Unchanged; the expected hex comes from a file-private test encoder instead of the writer's own `hex` |
| `scent_field_capture_matches_the_field_and_its_publication_stays_bounded` (`host_simulation_test`) | Split: `diagnostics/scent_test.odin` keeps every assertion (capture equality, publication bound, decoded levels, widest field, reset invalidation) driven by `simulation.advance` + `capture_scent`; `scent_capture_follows_the_host_step_and_clears_when_the_arena_ends` in `diagnostics_host_test.odin` keeps the host-step wiring, level equality and reset invalidation through `host_simulation_step` | Preserved on both sides |
| `dedicated_brains_match_serial_simulation_and_use_distinct_threads`, `audience_attachment_and_diagnostics_cannot_change_decisions`, `search_workers_match_serial_with_trace_loss_and_private_entity_lifecycle` | Same files | Same assertions; `new(AI_Debug)` → `test_open_without_writer()`, `debug.count == AI_DEBUG_QUEUE && debug.dropped > 0` → `test_queue_full(debug) && test_dropped(debug) > 0` |
| `delivered_coverage_reaches_diagnostics_without_a_map`, `replacing_one_creature_keeps_the_other_mind_and_the_ground_and_workers_agree`, `second_brain_completes_without_collecting_first_brain`, `dev_scenario_waits_for_players_and_spawns_once` (now `scenario_test.odin`), audience, network, protocol, trainers tests | Same | Unchanged apart from `diagnostics.` prefixes |

Deliberate additions: `world_capture_owns_a_copy_of_the_host_packet_and_its_valid_length`
and `absent_diagnostics_accept_every_operation_without_touching_the_caller`
(`diagnostics/replay_test.odin`), `queue_drops_new_jobs_when_full_and_keeps_counting`
(`queue_test.odin`), `launch_options_gate_diagnostics_to_debug_dev_loopback_hosts`
(`options_test.odin`), `world_capture_receives_the_host_packet_and_owns_its_copy` (host seam
against the protocol lobby fixture and a full arena packet) and
`host_capture_stays_disabled_without_diagnostics` (`diagnostics_host_test.odin`). No
reviewer-owned probe or fixture under `tests/` was touched.

## 7. Gates, commands and exit codes

Baseline (pre-edit) from `baseline/source`, logs under `baseline/logs/`, codes in
`baseline/exit-codes.txt`:

| Step | Command | Exit | Notes |
| --- | --- | --- | --- |
| Debug build | `make build_server` | 0 | `baseline/server-debug-binary` |
| Release build | `odin build server -o:speed …` | 0 | `baseline/server-release-binary` |
| Package discovery | `odin test server/diagnostics` | 1 | No such package in the starting tree (`diagnostics_tests_absent.log`) |
| `make check`, run 1 | | 2 | `check-run1-fresh-copy-no-import-cache.log`: `check_arena_overview` could not resolve the `ArenaCatalog` class name because the fresh copy had no `client/.godot` cache and that target runs before any import target. The working tree passes the same script (150 assertions). |
| `make check`, run 2 | | 2 | `check-run2-empty-import-cache-copy.log`: same failure; the cache copy used a wrong relative path and produced an empty directory. |
| `make check`, run 3 | | 2 | `check-run3-missing-asset-sources.log`: 18 PASS lines, then `check_character_contract` failed because the copy lacked the tracked `asset_sources/` directory (`snapshot_source` SHA-256 of `reference16/sheet.png`). |
| `make check`, run 4 | `make check` | 0 | `check.log`: 44 PASS lines; Odin suites 17 (perception), 18 (ai), 9×2 (content), 30×2 (simulation), 24×2 (host), 3×2 (vision review), 3×2 (olfaction review), 4×2 (olfaction coverage) = 181 tests. |
| Graphical senses | `tests/senses_windows_check.py --graphical` | 0 | Run alone after the candidate chain, as the latency reference (section 9). |

Runs 1 to 3 are copy-environment failures, not starting-tree failures; the fix each time
was to complete the copy (`run-baseline-check2.sh`, `-check3.sh`, `-check4.sh` say what
changed). `baseline/source-manifest.sha256` now includes `asset_sources/`.

Candidate, in the working tree, logs under `candidate/logs/`, codes in
`candidate/exit-codes.txt`, `candidate/chain-exit-codes.txt`, `candidate/release-host/exit-codes.txt`,
`candidate/replay-compat/exit-codes.txt`, `perf/exit-codes.txt`:

| Gate | Command | Exit | Evidence |
| --- | --- | --- | --- |
| Debug host build | `make build_server` | 0 | `build_server.log`, `candidate/server-debug-binary` |
| Package, normal | `odin test server/diagnostics -out:build/diagnostics_tests` | 0 | 10 tests, no ENet flags (`diagnostics_tests_normal.log`) |
| Package, debug | `odin test server/diagnostics -debug …` | 0 | 10 tests (`diagnostics_tests_debug.log`) |
| Discovery and integration | `make check_session check_ai_debugger` | 0 | content 9/9, simulation 30/30, diagnostics 10/10, host 21/21 in both builds; `tests/ai_debugger_check.py` PASS including its release-gate step (`check_session_ai_debugger.log`) |
| Release host | `odin build server -out:… -o:speed …` | 0 | `candidate/server-release-binary` |
| Release rejection | `server-release-binary --dev --dev-ai-dir=/tmp/forbidden-diagnostics --dev-ai-run=test` | 1 | Prints "Telemetry requires a debug host build." (`release_rejects_diagnostics.log`) |
| Full suite | `make check` | 0 | 44 PASS lines; Odin suites as the baseline plus 10×2 diagnostics and 21×2 host = 195 tests (`check.log`) |
| Graphical AI debugger | `tests/ai_debugger_check.py --graphical` | 0 | Journals, inspector responsiveness, capture/replay, close, reload, audience isolation, release gate, cleanup |
| Graphical senses | `tests/senses_windows_check.py --graphical` | 0 | Six native windows, private readings, separate clocks, stale recovery, paused brain, close, reload, round reset, failed launch, cleanup |
| Graphical scent | `tests/scent_check.py --graphical` | 0 | Real moving trail and decay, heatmap equal to the published field, saved F8/F6 across restart, F7 reset, recorded olfaction |
| Graphical development | `tests/dev_workflow_check.py --graphical` | 0 | Launch, source reload, failed-save recovery, cleanup |
| Release client smoke | `connection_check`, `selection_check`, `arena_selection_check`, `movement_check`, `audience_delay_check` against `candidate/server-release-binary` | 0 ×5 | `candidate/release-host/` |
| Source identity | `candidate/final-identity.sh` | | `pre-vs-post-gate-manifest.diff` names only the two documents written after the gates (this report and the packet's handback link); no source, test, Makefile or Godot file changed during the gates; all eight protected scopes unchanged (`protected-scopes-result.txt`); `path-list-changes.txt` lists exactly the 8 removed and 21 added paths of section 6 |

Display: `DISPLAY=:0` was available; the four graphical scripts ran with `--graphical` one
after another (`run-graphical.sh`), never concurrently with a baseline workload.

Test accounting by package, both builds where applicable: diagnostics 10 (senses 3, journal 2,
scent 1, replay 2, queue 1, options 1); host 21; content 9; simulation 30; ai 18; perception
17; reviewer packages 3, 3, 4. The independent fixtures under `tests/` are byte-identical to
the baseline (`protected-tests.sha256`).

## 8. Compatibility results

- **Recorded contracts.** Both trees write protocol 11, replay envelope 5, trace 5, senses 4,
  search 2, scent 1, `record_limit_bytes` 49,152, `retained_segments` 4, `log_limit_bytes`
  8,388,608, scent classes `["Human", "Orc"]`, `step_ticks` 6, packet lengths 32 and 164,
  final replay status `complete`, zero dropped, oversized or writer errors
  (`candidate/comparisons/ai-debugger-check-records.json`, `ai-debugger-first-session-records.json`).
- **Field-level comparison.** `candidate/compare_records.py` reduces every record, snapshot,
  live feed and replay frame to its key set and value kinds. Normalized: `run_id`,
  `published_us`, `origin_unix_us`, `publish_us`, `queued_us`, `started_us`, `finished_us`,
  `delivered_us`, `scent_delivered_us`, `elapsed_us`, `thread_id`, `worker_id`, record and
  frame counts, and the fingerprint (compared separately: equal). The newest-session
  comparison differs in no section. The first-session comparison differs only in the set of
  `decision_reason`/`result.kind` values seen in owner 2's retained journal window: the
  candidate's longer session (1,500 frames versus 1,069) rotated `ai-2.jsonl` past the four
  retained 8 MiB segments, so its window holds only late `Observe`/`Held` decisions. Leaf
  paths are identical on both sides; rotation size and retention are unchanged.
- **Recording produced by the preserved baseline host.** `replay_compat4.sh`: the baseline
  host's first-session recording (1,071 lines) decodes and seeks through its own staged
  generation-1 client and through the candidate sandbox's staged client; the candidate host's
  first-session recording (1,502 lines) decodes through its staged client; all three
  `tests/replay_check.gd` runs PASS with the legacy schema-1 fixture. The earlier attempts are
  kept: through the repository client the reader rejects both recordings on the content
  fingerprint (the harness stages QA content), and `replay_compat3.sh` picked a later
  generation without trainer movement. Neither is a protocol or envelope incompatibility.
- **Behavior paths.** Normal close, journal rotation, oversized records, replay line and size
  limits, invalidation and reset are exercised by the moved tests (`journal_test.odin`,
  `scent_test.odin`, `diagnostics_host_test.odin`) and by the graphical workflows; failed
  output is exercised by the AI debugger harness's incomplete-launch and cleanup steps. No
  assertion, tolerance or fixture was changed to pass.
- **Gameplay equivalence.** The serial/threaded equivalence tests still hold byte for byte
  with diagnostics absent (`replacing_one_creature…`, `host_capture_stays_disabled…`),
  attached without a writer and dropping (`dedicated_brains…`, `audience_attachment…`,
  `search_workers…`) and attached with a writer (`debug_journals…`, `delivered_coverage…`).

## 9. Performance comparison

Same machine, content, arena (`meadow_crossing`), creatures (`archer` vs `orc`), seed 7,
countdown 0, headless launcher, 45 s after arena entry, debug build flags, one run after the
other with the machine otherwise idle. Baseline from `perf/baseline-tree` (the snapshot),
candidate from `perf/candidate-tree` (a copy of the final working tree, manifest-identical).
Raw logs and JSON: `perf/diagnostics-on/`, `perf/diagnostics-off/`.

| Measure (diagnostics on, `--ai-debug 1`) | Baseline | Candidate |
| --- | --- | --- |
| Host CPU time over the run | 24.94 s | 24.87 s |
| Host resident memory at the end / peak | 12,736 kB / 12,736 kB | 12,732 kB / 12,732 kB |
| Threads | 4 | 4 |
| Decision records written (owner 1 / 2) | 1,203 / 1,228 | 1,203 / 1,228 |
| Worker compute per decision, median / p95 / max, owner 1 | 8 / 14 / 33 µs | 8 / 14 / 52 µs |
| Worker compute per decision, median / p95 / max, owner 2 | 10 / 18 / 33 µs | 8 / 18 / 36 µs |
| Queue wait per decision, median / p95 / max, owner 1 | 6 / 17 / 23 µs | 8 / 18 / 32 µs |
| Queue wait per decision, median / p95 / max, owner 2 | 10 / 18 / 21 µs | 4 / 18 / 44 µs |

| Measure (diagnostics off, `--ai-debug 0`, no `--dev-ai-dir`) | Baseline | Candidate |
| --- | --- | --- |
| Host CPU time over the run | 0.58 s | 0.58 s |
| Host resident memory at the end / peak | 6,540 kB / 6,540 kB | 6,620 kB / 6,620 kB |
| Threads | 3 | 3 |

The first diagnostics-off pass (`perf/diagnostics-off-run1-stale-session/`) summarized the
on-run's leftover session file (dead host, 0 samples) and was discarded; `perf_compare.py`
now takes only a session published by its own launch with a live host. Identical record
counts show the same number of decisions and no drops in either tree; the maxima differ by
tens of microseconds run to run (thread scheduling), the medians and p95 are equal. The
disabled path costs the same with the encode moved to the host, because `host_capture_world`
returns before encoding.

Suite timing, three runs each, non-debug `odin test`, host package linked with ENet
(`perf/*-timing-lines.txt`): baseline host 24 tests 180 / 185 / 197 ms; candidate diagnostics
10 tests 11.7 / 11.9 / 11.9 ms plus host 21 tests 185 / 187 / 199 ms. The worst-case schema-5
record is 41,232 bytes of 49,152 on both sides.

Graphical delivery latency (`tests/senses_windows_check.py --graphical`, threshold p95 ≤ 150 ms
unchanged, each run alone):

| Window | Baseline p95 / max | Candidate p95 / max |
| --- | --- | --- |
| senses1 vision | 81.8 / 82.4 ms | 88.5 / 105.0 ms |
| senses2 vision | 82.0 / 98.4 ms | 88.6 / 155.0 ms |
| senses1 olfaction | 82.1 / 232.3 ms | 88.7 / 204.3 ms |
| senses2 olfaction | 82.2 / 198.4 ms | 88.1 / 88.7 ms |

Maxima are single samples and swap between windows from run to run (the baseline's largest is
on olfaction 1, the candidate's on vision 2); a passing p95 is not a maximum guarantee.
Writer snapshot publish time reported by the debugger: 127,411 µs baseline, 133,912 µs
candidate, with ~106 MB recordings and zero drops on both sides
(`performance.json` in each `senses-windows-*` sandbox: baseline under
`baseline/source/build/verification/`, candidate under `build/verification/`).

## 10. Remaining risks, gaps and separately proposed changes

- `probe_test.odin` is compiled into the production host like every `_test.odin` file; it
  is dead code there, the same situation as `simulation/scenario_test.odin`. Renaming such
  files or excluding them from `odin build` would be a separate build change.
- `host_capture_stays_disabled_without_diagnostics` proves equivalence and no session
  mutation with `nil`; that no packet is encoded on that path is by construction (the early
  return in `host_capture_world`) and is reflected in the equal diagnostics-off CPU figure,
  not asserted by a counter.
- The baseline graphical reference covers the senses workflow only; the AI debugger, scent
  and development workflows ran graphically on the candidate and headless on the baseline
  (inside `make check`).
- The pre-edit `make check` needed a complete copy (import cache and `asset_sources/`) to
  pass; `check_arena_overview` has no import dependency in the Makefile, so a fresh clone
  running `make check` would hit run 1's failure. Not fixed here (unrelated to the extraction).
- `options_valid` prints its rejection lines on stderr during `options_test`; harmless noise.
- Deleted without replacement: the uncalled `ai_debug_publish`. If a caller was intended, it
  is one loop over `publish_owner`.
- The three P3 notes from the dev UI review (plot clipping, the uncalled Python overview
  helper, pixel-count wording) remain open and untouched.

All changes are unstaged and uncommitted (`candidate/git-status.txt`,
`git-diff-staged.patch` is empty). Nothing under `client/`, `tools/`, `tests/`, `server/ai`,
`server/perception`, `server/observations`, `server/content` or `server/simulation` changed.
