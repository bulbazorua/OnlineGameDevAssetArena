# Server refactor: coding-agent report

Status: **READY FOR INDEPENDENT REVIEW** (not accepted). Assignment:
[server refactor packet](delegation.md). Architecture record:
[server architecture](codebase/server-architecture.md). All changes are unstaged
and uncommitted. Evidence root: `build/verification/server-refactor-20260912/`
(`.keep-logs` present).

## 1. Starting source identity

| Item | Value |
| --- | --- |
| HEAD | `333bd1b5948474e5d2cf5315f15f4f1223c5ba21` (`main`) |
| Working tree | Dirty before this assignment: 42 tracked files modified (olfaction correction work) plus untracked `docs/06r-olfaction-closed-delegation.md`, `tests/olfaction_coverage/`, `tools/measure_peak_memory.py`. Exact list: `baseline/git-status.txt`; patch: `baseline/git-diff-unstaged.patch`. |
| Buildable baseline snapshot | `baseline/source/` holds byte-exact copies of `server/`, `tests/`, `tools/`, `client/content/data/`, `client/dev/fixtures/content/` and `Makefile` as they were before any edit. `baseline/source-manifest.sha256` (146 files) and `baseline/client-gd-manifest.sha256` (92 Godot scripts) identify the rest. |
| Tools | Odin `dev-2026-03-nightly`, Godot `4.6.stable.official.89cea1439`, Python 3.12.3, ENet `build/deps/libenet.a` (pinned 1.3.17 build) |
| Machine | AMD Ryzen 9 9950X (32 threads), 61.8 GB RAM, Linux 7.0.0-31-generic, X display `:0`, `wmctrl` present |
| Build flags | Debug host: `odin build server -out:build/server -debug -extra-linker-flags:"-L$(pwd)/build/deps"`. Release gate: the same with `-o:speed` (as `tests/ai_debugger_check.py` builds it). Content: `client/content/data` (fingerprint unchanged). |

`baseline/environment.txt` records these values; `baseline/server-debug-binary` and
`baseline/server-release-binary` are the pre-refactor executables.

## 2. Baseline results (before any edit)

| Gate | Command | Exit | Log |
| --- | --- | --- | --- |
| Debug build | `make build_server` | 0 | `baseline/logs/build_server.log` |
| Release build | `odin build server -o:speed ...` | 0 | `baseline/logs/build_server_release.log` |
| Full suite | `make check` | 0, 42 PASS lines | `baseline/logs/check.log`, `baseline/logs/check-pass-lines.txt` |

Odin test totals in the baseline: root `server` 61, `server/ai` 18, `server/perception` 17,
`tests/vision_review` 3, `tests/olfaction_review` 4, `tests/olfaction_coverage` 3, all
passing in normal and debug builds. The display was available, so the rendered probes ran.

## 3. Final ownership map

| Package | Owner of | Public API (production) | Imports |
| --- | --- | --- | --- |
| `server/content` | Catalogs, definitions, baked arena rules, geometry queries, fingerprint, allocation lifetime | `Game_Content`, `Character_Definition`, `Terrain_Definition`, `Arena_Definition`, `Sense_Profile`, `Content_Kind`, `load`, `destroy`, `parse_extra`, `find_character`, `find_arena`, `find_terrain`, `arena_terrain_id`, `arena_cell_is_blocked`, `arena_cell_blocks_sight`, `arena_refresh_rules`, `arena_opacity_grid`, `arena_cell_center`, `arena_world_to_cell`, `arena_elevation_at`, `arena_step_is_allowed`, `arena_spawn_is_clear`, `arena_position_is_clear` | `observations`, `perception`, core |
| `server/simulation` | `Simulation` (public `Session` + private `Battle_Runtime`), commands, lifecycle, movement, trainers, receptors, scent environment, battle phases, action resolution, development reset | `Simulation`, `begin_tick`, `advance`, `Session` and `session_*`, `Client_Command`/`Message_Kind`/`Command_Reject_Reason`, `session_apply`, `Character`/`Trainer` and constants, `character_move`, `movement_apply_delta`, `trainer_tick_motion`, `character_resolve_intent`, `Receptor`, `senses_prepare`, `Scent_Environment`, `Battle_Runtime`, `battle_sync`, `battle_prepare_decisions`, `battle_resolve_decisions`, `Decision_Outcome`, `Brain_Request`, `Brain_Response`, `brain_decide`, `decide_serially`, `dev_search_reset*` | `content`, `ai`, `observations`, `perception`, `core:math/sync/time` |
| `server` (host) | Startup, ENet, codec, audience history, brain threads, diagnostic writer, development scenario, host step | `host_simulation_step`, `brain_workers_*`, `protocol_*`, `network_*`, `audience_*`, `ai_debug_*`, `dev_*` | `content`, `simulation`, `ai`, `observations`, `perception`, ENet, core |
| `server/ai`, `server/perception`, `server/observations` | Unchanged | Unchanged | Unchanged |

Package-private helpers: content parsers, JSON helpers, digest framing (`write_u32_le`
replaces the codec dependency with identical bytes); in the simulation the receptor
sampling helpers, `battle_bind_creature`, `battle_resolve_creature`, `session_next_entity`,
`summon_position`, emitter helpers and the reset search helpers.

Mutation paths: catalogs are written only by `load`; the session by `session_join/leave`,
`session_apply`, `session_tick`, `session_enter_arena`, `session_start_match` and
`dev_search_reset`; the battle runtime by `battle_sync`, `battle_prepare_decisions` and
`battle_resolve_decisions`; bodies by `session_tick` (trainers) and
`battle_resolve_decisions` (creatures). Details and the tick/thread flow:
[server architecture](codebase/server-architecture.md).

## 4. Staged changes

### Stage 1: content and static arenas (`server/content/`)

Reason: the content files depended on the rest of the root only through
`protocol_write_u32`; everything else already read them. The package gives catalogs one
owner, one lifetime and a smaller API (parsers and JSON helpers private).

- Moved: `content.odin` → `content/catalog.odin`, `content_senses.odin` → `content/senses.odin`,
  `characters.odin`, `arena.odin` (same names). Package-name stutter removed
  (`content_load` → `content.load`, `content_character` → `content.find_character`, ...).
- `hash_file` writes its own little-endian lengths; digest bytes are covered by the unchanged
  fixture tests (`CONTENT_FIXTURE_DIGEST`, `tests/fixtures/content` digest).
- Consumers: every root file that took `content: ^Game_Content` now takes
  `catalog: ^content.Game_Content` (a local named `content` would shadow the package).
- Tests: `content_test.odin` → `content/catalog_test.odin`; `arena_test.odin` and
  `elevation_test.odin` were split by subject (content tests moved, session/protocol/movement
  tests stayed for Stage 2). Makefile `check_session` and `check_ai_debugger` test the package.
- Verification: `odin test server/content` 9/9 (normal, debug); root 52/52 (normal, debug);
  `make check_content check_arena_content check_session` exit 0
  (`stage1/make-check_content-check_arena_content-check_session.log`); vision review 3/3 both
  builds; release build exit 0. Diff: `stage1/stage1-vs-baseline.patch`.

### Stage 2: lifecycle and simulation (`server/simulation/`)

Reason: the authoritative runtime was spread over root files that also held the codec,
threads and diagnostics. The package makes the owners explicit and keeps sockets, files,
threads and console output out of the simulation.

Dependencies resolved before the move:

- Commands: `Message_Kind`, `Client_Command`, `Command_Reject_Reason` and `session_apply`
  live in `simulation/commands.odin`; the codec (`server/protocol.odin`) imports the
  simulation, never the reverse. Bytes unchanged (wire fixture tests moved intact).
- Execution: `battle_tick` became two simulation phases, `battle_prepare_decisions` and
  `battle_resolve_decisions`, with `Brain_Request`/`Brain_Response` values and the single
  `brain_decide` between them. The host composes them in `host_simulation_step` with
  either the two threads (`brain_workers_decide`: both submitted before either collected) or
  `decide_serially`; `simulation.advance` is the serial reference used by simulation tests.
- Diagnostics: `battle_resolve_decisions` returns a `Decision_Outcome` per creature;
  `ai_debug_record_decisions` (host) builds the same `AI_Debug_Record` fields as before
  (`facing` = `u8(request.ctx.facing)`, identical to the pre-resolution facing; `after` read
  after both resolutions, which cannot differ because each resolution touches only its own
  slot). The Outcome trace node is still appended by the host before enqueueing.
- Snapshot cadence: `SNAPSHOT_INTERVAL` moved to `server/main.odin` (host publication).
- Development reset: the mutation stays in `simulation/dev_search_reset.odin`; the console
  line moved to `dev_log_search_reset` in `server/dev_search.odin`, printed by
  `network_receive` after an accepted reset with the same text and values.
- Development scenario: `dev_scenario_start` now calls `simulation.session_start_match`
  instead of writing session fields from the host.
- `senses_prepare` receives `&battle.receptors` and `&battle.scent.field` instead of the
  whole runtime, making its mutation explicit.

Lifecycle placement: `simulation/session.odin` holds `Session`, membership, countdown,
`session_tick`, `session_enter_arena`, `session_start_match`, entity allocation and
summon placement; `character.odin` the live body and its enums; `movement.odin` the
terrain step; `trainers.odin` the trainer; `character_actions.odin`, `senses.odin`,
`scent_environment.odin` unchanged in content.

Verification: `odin test server/simulation` 30/30, `server/content` 9/9, `server` 24/24, each
in normal and debug builds; `tests/vision_review` 3/3 both builds; debug and release builds
exit 0. Diff: `stage2/stage2-vs-baseline.patch` (cumulative against the baseline snapshot).

### Stage 3: integration

See sections 6 to 9.

## 5. Changed files

Removed from the root package: `arena.odin`, `arena_test.odin`, `battle.odin`,
`battle_test.odin`, `character_actions.odin`, `characters.odin`, `content.odin`,
`content_senses.odin`, `content_test.odin`, `dev_search_reset.odin`,
`dev_search_reset_test.odin`, `elevation_test.odin`, `movement.odin`, `movement_test.odin`,
`scent_battle_test.odin`, `scent_environment.odin`, `search_battle_test.odin`, `senses.odin`,
`senses_test.odin`, `session.odin`, `session_test.odin`, `simulation.odin`,
`trainer_run_test.odin`, `trainers.odin`.

Added to the root package: `host_simulation.odin`, `host_simulation_test.odin`,
`network_test.odin`, `protocol_test.odin`.

Modified root files: `audience.odin`, `audience_test.odin`, `brain_workers.odin`,
`brain_workers_test.odin`, `dev_ai_debug.odin`, `dev_replay.odin`, `dev_scenario.odin`,
`dev_scenario_test.odin`, `dev_scent.odin`, `dev_search.odin`, `dev_senses.odin`,
`dev_senses_test.odin`, `main.odin`, `network.odin`, `protocol.odin`, `trainers_test.odin`.

New packages: `server/content/` (`arena.odin`, `catalog.odin`, `characters.odin`, `senses.odin`
and three test files) and `server/simulation/` (`battle.odin`, `character.odin`,
`character_actions.odin`, `commands.odin`, `decisions.odin`, `dev_search_reset.odin`,
`movement.odin`, `scent_environment.odin`, `senses.odin`, `session.odin`, `simulation.odin`,
`trainers.odin` and ten test files including `scenario_test.odin`).

Unchanged: `server/ai/`, `server/perception/`, `server/observations/`, all Godot code, all
content and fixtures. Other changed files: `Makefile` (test targets),
`tests/dev_workflow_check.py` (two path strings), `tests/vision_review/vision_review_test.odin`
(imports and package prefixes), documentation listed in section 10.

Line counts after: host package 2,449, content 864, simulation 2,351 (tests included).

## 6. Changed tests and fixtures

Test totals: 63 = baseline 61 + 2 deliberate additions; every assertion of every baseline
test is present in exactly one package. Placement:

| Destination | Tests |
| --- | --- |
| `server/content/catalog_test.odin` | The four `content_test.odin` tests, unchanged |
| `server/content/arena_test.odin` | `arena_content_and_coordinate_fixture`, `sight_blocking_is_baked_independently_of_walkability`, `arena_rejects_invalid_cells_dimensions_and_spawns` |
| `server/content/elevation_test.odin` | `land_arenas_are_large_connected_and_have_accessible_high_ground`, `elevation_rows_reject_invalid_shape_and_values` |
| `server/simulation/session_test.odin` | `session_preserves_roles_and_reuses_only_departed_slots`, `selection_authority_readiness_and_round_reset`, `arena_selection_authority_and_ready_invalidation` |
| `server/simulation/movement_test.odin` | Three movement tests plus `elevation_changes_require_stairs_in_both_directions` (needs `character_move`) |
| `server/simulation/trainer_run_test.odin` | The three trainer running tests; the last one's three wire lines became the root test `input_packet_carries_the_run_bit` |
| `server/simulation/battle_test.odin`, `senses_test.odin`, `search_battle_test.odin`, `dev_search_reset_test.odin`, `scent_battle_test.odin` | Every serial test from the corresponding root file |
| `server/simulation/scenario_test.odin` | `battle_test_scenario`, `battle_test_content_with_qa`, `scent_test_scenario` (shared builders; the host tests call them as `simulation.*`) |
| `server/protocol_test.odin` | `protocol_version_six_fixtures`, `arena_command_wire_fixtures`, `movement_protocol_fixtures_and_channel_validation`, `search_reset_command_has_a_bounded_reliable_wire_contract`, new `input_packet_carries_the_run_bit` |
| `server/network_test.odin` | `network_forgets_membership_once` |
| `server/host_simulation_test.odin` | `audience_attachment_and_diagnostics_cannot_change_decisions`, `replacing_one_creature_keeps_the_other_mind_and_the_ground_and_workers_agree`, `scent_field_capture_matches_the_field_and_its_publication_stays_bounded`, `search_workers_match_serial_with_trace_loss_and_private_entity_lifecycle`, and the diagnostics half of the coverage test as `delivered_coverage_reaches_diagnostics_without_a_map` |
| `server/trainers_test.odin` (root) | `trainers_summon_selected_gladiators_on_land_and_own_input` (it watches audience history) |

The one split: `delivered_coverage_matches_the_arena_and_reaches_diagnostics_without_a_map`
became `delivered_coverage_matches_the_arena_geometry` (simulation, the arena oracle) and
`delivered_coverage_reaches_diagnostics_without_a_map` (host, the `when ODIN_DEBUG`
half with the same scenario setup). No assertion was removed, weakened or reordered.

Serial-versus-threaded equivalence tests now compare `simulation.advance` with
`host_simulation_step(..., workers, debug)`; `senses_test` calls `senses_prepare` with the
receptors and the field.

Independent review fixtures, listed explicitly for the Team Lead:

- `tests/vision_review/vision_review_test.odin`: import lines only (`host "../../server"` →
  `content "../../server/content"` and `simulation "../../server/simulation"`) and the
  package prefixes on `Game_Content`, `content_load/destroy`, `Simulation`,
  `session_enter_arena`, `simulation_tick` (→ `simulation.advance`), `battle_sync`; the
  local `content` variable is now `catalog`. Every assertion is byte-identical. The README's
  commands are unchanged and still run through `make check_vision_review`.
- `tests/olfaction_review/`, `tests/olfaction_coverage/`, `tests/fixtures/`: untouched.
- `tests/dev_workflow_check.py`: the file it edits to prove an Odin relaunch is now
  `server/simulation/movement.odin` (two path strings); the expected constant and the
  rest of the check are unchanged.

Makefile: `check_session` runs `odin test server/content`, `server/simulation` and `server`;
`check_ai_debugger` runs the same three in `-debug`. No target was removed or softened.

## 7. Reproduction commands and exit codes

Run from the repository root (a display is needed for `make check`).

```sh
make build_server                                   # exit 0
odin build server -out:build/server-release -o:speed -extra-linker-flags:"-L$(pwd)/build/deps"   # exit 0
odin test server/content -out:build/content_tests                                   # 9 tests
odin test server/simulation -out:build/simulation_tests                             # 30 tests
odin test server -out:build/session_tests -extra-linker-flags:"-L$(pwd)/build/deps" # 24 tests
# the same three with -debug                                                        # 9 / 30 / 24
make check_vision_review                            # 3 tests, normal and debug
make check_content check_arena_content check_session   # exit 0 (stage1 log)
make check                                          # see section 8
```

Stage 3 gate results (candidate tree):

| Gate | Exit | Evidence |
| --- | --- | --- |
| `make build_server` | 0 | `stage3/logs/build_server.log`, `stage3/server-debug-binary` |
| `make check` | 0, 42 PASS lines; Odin totals content 9, simulation 30, host 24 (each normal and debug), ai 18, perception 17, vision review 3 ×2, olfaction review 4 ×2, coverage 3 ×2 | `stage3/logs/check.log`, `stage3/logs/steps.txt` |
| Release host (`-o:speed`) exercised by real clients | 0 for `connection_check`, `selection_check`, `arena_selection_check`, `movement_check`, `audience_delay_check` (the other client checks pass `--dev` scenario flags that a non-debug host rejects by design; the release gate inside `check_ai_debugger` covers that rejection) | `stage3/release-host/` |
| Pre-refactor recording decodes and seeks | 0: `tests/replay_check.gd` run exactly as `ai_debugger_check.py` runs it (through the recording's staged client) on `match.replay.jsonl` written by the baseline host during the baseline `make check`; it also re-checks the legacy schema-1 fixture. A first attempt through the repository client failed on the content fingerprint because that scenario stages the `vision_range` QA arena (fingerprint `1358f9…` versus plain `1bc683…`); a second probe on a 105 MB plain-content recording was invalid (that recording ran the Search controller, while `replay_check.gd` is written for an observe-only recording) and was aborted and discarded. Both attempts are recorded in `exit-codes.txt`. The candidate `make check` and the graphical AI-debugger run also decode a fresh candidate-host recording plus the legacy schema-1 fixture through the same harness | `stage3/replay-compat/` |
| Graphical scenarios | 0 for `tests/scent_check.py --graphical`, `tests/senses_windows_check.py --graphical`, `tests/ai_debugger_check.py --graphical`, `tests/dev_workflow_check.py --graphical`; sandboxes listed in `stage3/graphical/evidence-directories.txt` (`.keep-logs` set) | `stage3/graphical/` |
| Performance comparison | see section 9 | `stage3/performance/` |

## 8. Behavior comparisons

- Wire bytes: the protocol fixture tests (`protocol_test.odin`, `audience_test.odin`) compare
  exact byte arrays and pass; `PROTOCOL_HEADER` version 11 unchanged; Godot decoding untouched.
- Content: `content_validates_and_matches_digest_fixture` and
  `arena_content_and_coordinate_fixture` check exact SHA-256 digests after the codec
  dependency was removed; `tests/content_check.gd` compares the Godot fingerprint with the
  same fixtures (in `make check_content`).
- Simulation order: `begin_tick` computes the pre-step `can_act`, then `session_tick`,
  `battle_sync`; `battle_prepare_decisions` runs `scent_environment_tick`, `senses_prepare`,
  then builds both contexts; both decisions; `battle_resolve_decisions` resolves slot 0 then
  slot 1, each followed by `agent_record_result` and the target alert; then world and scent
  captures. The serial/threaded equivalence tests hold byte-for-byte across 700 to 2,400 ticks.
- Diagnostics: trace, senses, search, scent and replay schemas (5, 4, 2, 1, 5) unchanged;
  `AI_Debug_Record` fields are filled from the same sources (section 4).
- Console output: identical lines; only the search-reset line is now printed by the host.

## 9. Performance comparison

Same machine, same content, arena, seed, duration and build flags for both sides; the
machine was otherwise idle (the full suite had finished). Baseline code ran from
`baseline/source`; scripts and raw logs are under `stage3/performance/` and `stage3/`.

**Whole host (debug build, headless launcher, `archer` vs `orc` on `meadow_crossing`, seed 7,
AI debugging on, 45 s after arena entry, sampled every second from `/proc`):**

| Measure | Baseline | Candidate |
| --- | --- | --- |
| Host CPU time over the run | 24.91 s | 24.89 s |
| Host resident memory at the end / peak | 12,692 kB / 12,692 kB | 10,936 kB / 11,028 kB |
| Threads | 4 | 4 |
| Worker compute per decision, median / p95 / max (owner 1) | 9 / 17 / 35 µs | 9 / 14 / 31 µs |
| Worker compute per decision, median / p95 / max (owner 2) | 9 / 16 / 33 µs | 9 / 18 / 38 µs |
| Queue wait per decision, median / p95 / max (owner 1) | 7 / 18 / 23 µs | 14 / 19 / 31 µs |
| Queue wait per decision, median / p95 / max (owner 2) | 13 / 18 / 25 µs | 6 / 18 / 24 µs |
| Decision records written | 1,203 / 1,228 | 1,200 / 1,225 |

The queue-wait medians swap between owners from run to run (thread scheduling), so they
are noise, not a shift. Worker timing alone does not establish whole-server performance;
the CPU-time row is the whole-host figure.

**Serial simulation microbenchmarks (the timing lines printed by the Odin suites, three
runs each, `odin test` default optimization, baseline root package versus candidate
`simulation` package):**

| Suite line | Baseline (3 runs) | Candidate (3 runs) |
| --- | --- | --- |
| `[vision]` 3,600 QA-arena ticks, mean per tick | 9.37 / 9.43 / 9.85 µs | 9.72 / 10.06 / 10.76 µs |
| `[vision]` 3,600 worst-envelope ticks, mean per tick | 257.6 / 259.2 / 259.3 µs | 256.2 / 256.6 / 257.3 µs |
| `[AI]` 3,600 enclosed-world ticks, total | 17.3 / 23.2 / 26.2 ms | 19.9 / 22.0 / 24.1 ms |
| `[search]` 18,000 ticks, meadow_crossing | 729 / 730 / 737 ms | 712 / 718 / 720 ms |
| `[search]` 18,000 ticks, sandbar | 832 / 834 / 836 ms | 824 / 826 / 828 ms |
| `[search]` 18,000 ticks, stone_garden | 421 / 423 / 423 ms | 422 / 423 / 426 ms |
| `[search]` 18,000 ticks, tiny_swords_village | 521 / 521 / 522 ms | 519 / 520 / 523 ms |
| Worst-case trace record | 41,232 bytes | 41,232 bytes |

Search acquisition ticks and travel figures are identical on all four maps, which also
shows the random streams and draw order survived. The QA-arena vision line is about 4 to
9 percent slower per tick (roughly 0.4 µs); the likely cause is that a decision now passes
through by-value `Brain_Request`/`Brain_Response` copies of the 1,280-byte agent instead
of deciding in place on the serial path. The worst-envelope and search lines, which do far
more work per tick, are equal or slightly faster. No allocation was added to the tick: the
enclosed-world test still runs with the allocator disabled.

**Diagnostic queue and recording behavior:** the candidate `make check` and the graphical
AI-debugger run report zero dropped or oversized records, complete recordings and the
same journal rotation; `stage3/comparisons/recording-and-journal-comparison.json` shows
identical header fields (protocol 11, envelope 5, trace 5, same content fingerprint) and
identical frame/trace keys between a baseline-host and a candidate-host recording.

Debug-enabled figures are the whole-host table above; the serial microbenchmarks are
non-debug `odin test` builds. No release-build timing was measured beyond the release host
passing the client checks.

## 10. Documentation

New: `docs/codebase/server-architecture.md`. Updated: `docs/codebase/battle-runtime-lifecycle.md`,
`docs/codebase/opponent-search.md`, `docs/codebase/olfaction.md`, `docs/project-structure.md`
(tree and Odin-side paragraphs), `docs/protocol.md` (implementation links),
`docs/03f-dev-workflow.md` (files table), `docs/plan.md` (handoff status). Historical
checkpoint records keep their original file names; the architecture document's file map
translates them. Their relative links to moved root files no longer resolve:
`docs/03a-connection-session-lobby.md`, `docs/06-character-ai-orchestration-proposal.md`,
`docs/06b-autonomous-idle-walk.md`, `docs/06c-senses-and-ai-debug-windows-plan.md`,
`docs/06d-ai-debugger-harness.md`, `docs/06f-focused-and-peripheral-vision-proposal.md` and the
Team Lead's `docs/06i-vision-team-lead-review.md`. They were left as written (historical
reports and a review document); `06b` already carried dead links to `ai/wander.odin` and
`ai/random.odin` before this work. `docs/delegation.md` was not edited.

## 11. Untested, blocked and observed

- Physical keyboard and mouse input and an exported client were not exercised; all
  client coverage is scripted (headless integration) or the graphical harness modes.
- Debug-build host timing was measured; release-build timing was not.
- The replay evidence is a recording written by the pre-refactor host decoded by the
  unchanged client tooling; no deterministic re-simulation exists to compare.
- Historical checkpoint documents still name the old file paths on purpose.

Observed but not changed (outside this assignment):

- Odin compiles `_test.odin` files into normal builds, so `core:testing` and the test
  fixtures are part of the executable's compilation unit. Unreachable procedures are
  dropped by the compiler, but the pattern predates this work and applies to every package.
- `dev_search_reset` keeps its `when !ODIN_DEBUG { return ... }` early return followed by
  unreachable code in release builds, as before.
- The inspector memory use and the recording size cap noted in the olfaction review remain.

## 12. Recommendation for the next task: a `diagnostics` package

Not implemented here (outside the two authorized boundaries); offered for the Team Lead to
shape into the next packet.

**Why.** The `dev_*.odin` files in the host package are one unit: the writer thread, its
bounded queue, journals, snapshots, the replay recorder and the live senses, search and
scent feeds, all state of one `AI_Debug`. The host reaches it through about eight procs.
A prefix says "these files are about diagnostics"; a package says "this is an owner with a
small API and its own build gate". The files are already on the package side of that line.

**How large codebases do it.** Every reference converges on three layers: data-only
instrumentation inside the owning system (id Software's `RunDebugInfo` gated by cvars at
the end of the game frame; Unreal's Gameplay Debugger categories implemented beside the AI
module; Unreal's Visual Logger `GrabDebugSnapshot` on the actor; Godot's `scene/debugger/`
inside the scene subsystem), a developer-only module that owns queues, serialization and the
tool connection (Unreal `DeveloperTool` modules, which load only where developer tools are
built; Bevy's `bevy_dev_tools` crate behind a feature flag; Godot's `core/debugger`), and a
separate viewer reading a versioned stream (Unreal Insights over `.utrace`, the Visual Logger
viewer, Godot's editor debugger over TCP). This server already has layers one and three
(`Decision_Outcome`, receptor audits and sample flags in the simulation; the Godot
inspectors reading schema-numbered JSON). Layer two exists but is unnamed.

**Proposed shape.**

| Item | Proposal |
| --- | --- |
| Package | `server/diagnostics/` holding `dev_ai_debug.odin`, `dev_replay.odin`, `dev_senses.odin`, `dev_search.odin`, `dev_scent.odin`, renamed by the output they own (writer, journal, replay, senses feed, search feed, scent feed). Name it for what it owns, not when it runs; `dev` reads as a bucket. |
| API | `open`, `close`, `options_valid`, `capture_world`, `capture_scent`, `record_decisions`, `publish_*` on the writer thread, and `log_search_reset`. The host touches nothing else. |
| Dependency fix 1 | `capture_world` receives the already-encoded session packet and its size from the host, and `open` receives the protocol version for the replay header. The package then never imports the codec, which avoids an import cycle with the host. (Alternative: a small `server/protocol/` package.) |
| Dependency fix 2 | `options_valid` takes the three fields it checks (`dev`, `bind`, the directory and run strings) instead of the host's `Options` struct. |
| Stays in the host | `dev_scenario.odin` is launch wiring on `Options` and the simulation's `session_start_match`; keep it in the host, renamed `scenario.odin`, so the `dev_` prefix stops meaning two things. |
| Gating | Unchanged: `when ODIN_DEBUG` at `open` plus `--dev` and the loopback bind at runtime. This is the Unreal Shipping-exclusion plus Source `sv_cheats` shape; the search-reset packet stays in the command vocabulary with its host gate. |
| Tests | `dev_senses_test.odin`, the journal rotation and oversized-record tests and the scent capture test move into the package and run without ENet; `host_simulation_test.odin` keeps the wiring and equivalence tests. The tests that fill the queue without a writer read the drop counter directly; state that as a test-only path. |
| Godot side | `client/dev/` is the viewer program, correctly outside the runtime; no change. |
| Make | Add `odin test server/diagnostics` (normal and debug) beside the other three packages. |

**Two follow-ons worth noting, not part of that packet.** A per-tick hash of `Session`
plus `Battle_Runtime` written into the journal would give a cheap desync and regression
detector in the style of Factorio's per-tick CRC, long before a re-simulating replay
exists; the serial-versus-threaded equivalence tests already prove the determinism it
relies on. And the vision-fan computation on the writer thread is the Visual Logger model
(emitter adds display shapes) rather than the Insights model (viewer computes); either is
acceptable as long as it never touches the simulation thread.

References: Unreal [EHostType::Type](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Projects/EHostType__Type),
[Gameplay Debugger](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-the-gameplay-debugger-in-unreal-engine),
[Visual Logger](https://dev.epicgames.com/documentation/unreal-engine/visual-logger-in-unreal-engine),
[Unreal Insights](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-insights-in-unreal-engine);
Godot [EngineDebugger](https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html),
[scene/debugger](https://github.com/godotengine/godot/tree/master/scene/debugger);
[bevy::dev_tools](https://docs.rs/bevy/latest/bevy/dev_tools/index.html);
id Software [DOOM 3 BFG Game_local.cpp](https://github.com/id-Software/DOOM-3-BFG/blob/master/neo/d3xp/Game_local.cpp);
Source [FCVAR_CHEAT](https://wiki.alliedmods.net/ConVars_(SourceMod_Scripting));
Factorio [FFF-188](https://factorio.com/blog/post/fff-188).
