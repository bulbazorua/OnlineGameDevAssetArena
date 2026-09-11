# Server refactor R1: coding-agent report

Status: **READY FOR INDEPENDENT R1 REVIEW** (not accepted). Assignment:
[R1 packet](delegation.md). Finding: [Team Lead review](server-refactor-team-lead-review.md), R1.
Prior handback: [original coding-agent report](server-refactor-coding-agent-report.md) (historical,
not edited). Architecture record: [server architecture](codebase/server-architecture.md).
All changes are unstaged and uncommitted. Evidence root:
`build/verification/server-refactor-20260912/r1-20260911T193256Z/` (`.keep-logs` present; the
directory name is the UTC start time of the run).

## 1. Starting source identity

| Item | Value |
| --- | --- |
| HEAD | `333bd1b5948474e5d2cf5315f15f4f1223c5ba21` (`main`), unchanged since the original handback |
| Starting source | The reviewed candidate: the tree identified by `independent-review/candidate-source.sha256` (135 files: `Makefile`, `server/**`, `tests/**` Odin and tools). Not the old clean commit and not `baseline/source`. |
| Proof | `source-identity/candidate-manifest-vs-r1-tree.log`: 127 files `OK`, the 8 edited simulation files `FAILED`. `source-identity/reconstructed-candidate-check.log`: removing only the 16 inserted attribute lines from those 8 files reproduces files whose SHA-256 match the reviewed manifest (21 of 21 simulation files `OK`). Together: R1 tree = reviewed candidate + `r1-vs-candidate.patch`. |
| R1 manifest | `r1-source.sha256`, the same 135 paths hashed after the edit |
| Git state | `source-identity/git-status.txt`, `head.txt`. The pre-existing dirty refactor, olfaction work, historical reports, fixtures and recordings were not touched. |
| Tools | Odin `dev-2026-03-nightly`, Godot `4.6.stable.official.89cea1439`, Python 3.12.3, display `:0` (`environment.txt`) |

## 2. The audit

Method: every top-level declaration in `server/simulation/*.odin` was cross-referenced with
(a) production callers inside the package, (b) same-package `_test.odin` callers, (c) callers
in the host package (`server/*.odin`, production and tests), and (d) the external fixtures
(`tests/vision_review`, `tests/olfaction_review`, `tests/olfaction_coverage`, `tools/`). The
simulation is imported as `simulation` by 20 host files and by the vision fixture as
`simulation "../../server/simulation"`; the two olfaction fixtures import only `observations`
and `perception`. No caller uses a different alias.

### 2a. Before/after visibility of production procedures

Sixteen procedures had no caller outside the package. They are now package-private, or
file-private where every caller is in the same file. Bodies, names, signatures, defaults and
call order are unchanged.

| Procedure | File | Before | After | Internal production callers | Same-package tests | External callers |
| --- | --- | --- | --- | --- | --- | --- |
| `trainer_tick_energy` (R1 example) | `trainers.odin` | public | `@(private = "file")` | `trainer_tick_motion` | none | none |
| `trainer_tick_motion` | `trainers.odin` | public | `@(private)` | `session_tick` | `trainer_run_test` | none |
| `character_resolve_intent` (R1 example) | `character_actions.odin` | public | `@(private)` | `battle_resolve_creature` | `battle_test` | none |
| `character_turn_ready` | `character_actions.odin` | public | `@(private)` | `character_resolve_intent`, `battle_prepare_decisions` | `battle_test` | none |
| `receptor_bind` (R1 example) | `senses.odin` | public | `@(private)` | `battle_bind_creature` | none | none |
| `senses_prepare` (R1 example) | `senses.odin` | public | `@(private)` | `battle_prepare_decisions` | `senses_test` | none |
| `scent_environment_tick` (R1 example) | `scent_environment.odin` | public | `@(private)` | `battle_prepare_decisions` | none | none |
| `scent_environment_bind` | `scent_environment.odin` | public | `@(private)` | `battle_sync` | none | none |
| `scent_environment_bind_creature` | `scent_environment.odin` | public | `@(private)` | `scent_environment_bind`, `battle_bind_creature` | none | none |
| `character_move` | `movement.odin` | public | `@(private)` | `trainer_tick_motion` | `movement_test` | none |
| `movement_apply_delta` | `movement.odin` | public | `@(private)` | `character_move`, `character_resolve_intent` | none | none |
| `character_facing_to_observation` | `character.odin` | public | `@(private)` | `character_actions`, `battle`, `senses` | `battle_test`, `senses_test` | none |
| `serial_is_newer` | `commands.odin` | public | `@(private)` | `session_apply` | `movement_test` | none |
| `dev_search_reset` | `dev_search_reset.odin` | public | `@(private)` | `session_apply` (the `Dev_Reset_Search` command) | none directly; tests go through `session_apply` | none (`dev_search.odin` only logs the result) |
| `dev_search_reset_placements` | `dev_search_reset.odin` | public | `@(private)` | `dev_search_reset` | `dev_search_reset_test` | none |
| `dev_search_distance_squared` | `dev_search_reset.odin` | public | `@(private)` | `dev_search_reset_placements`, `dev_search_reset_farthest` | `dev_search_reset_test` | none |

`@(private = "file")` was used only where the single caller shares the file
(`trainer_tick_energy`). The other fifteen have callers or tests in other files of the
package, so package scope is the narrowest scope that keeps them compiling without any
test change.

Already private before R1 and left as they were: `session_next_entity`, `summon_position`,
`battle_bind_creature`, `battle_resolve_creature`, `dev_search_reset_farthest`,
`dev_search_reset_spawn`, `dev_search_reset_reachable` (package scope) and `receptor_gate`,
`schedule_next`, `vision_status_sample`, `scent_status_sample`, `vision_receptor_sample`,
`olfaction_receptor_sample`, `scent_emitter_arm`, `scent_emitter_follow` (file scope). Some
of the package-scoped ones have a single-file caller set and could be narrowed to file scope
later; they were never external entry points, so R1 leaves them untouched to keep the delta
small.

### 2b. Public production API kept, with external production callers

| Procedure | External production callers |
| --- | --- |
| `session_join`, `session_leave`, `session_apply` | `network.odin` |
| `session_start_match` | `dev_scenario.odin` |
| `session_player_mask` | `protocol.odin`, `dev_scenario.odin` |
| `session_countdown_seconds` | `protocol.odin` |
| `begin_tick`, `battle_prepare_decisions`, `battle_resolve_decisions`, `decide_serially` | `host_simulation.odin` |
| `advance` | `host_simulation.odin` (serial path), host tests, vision fixture |
| `brain_decide` | `brain_workers.odin` |

Types and constants (`Simulation`, `Session`, `Battle_Runtime`, `Receptor` and its parts,
`Brain_Request`/`Brain_Response`, `Decision_Outcome`, the command types, `MAX_PLAYERS`,
`SIMULATION_HZ`, the trainer and character constants) stay public. They are not callable
API; the host codec, audience history, diagnostics and workers read them; and hiding a type
name would not hide a field, since `Battle_Runtime` embeds them and Odin has no field privacy.

### 2c. Public procedures whose only external callers are tests

These four stay public. Each is a coherent lifecycle operation on a public type and is listed
as an allowed mutation path in the architecture record; none is one of the out-of-order
internal steps R1 names. Hiding them would require rewriting external tests onto
`Simulation`/`advance`, which changes what those tests measure (extra ticks and brain
decisions), so that is not a minimal adaptation.

| Procedure | Internal production callers | External test callers | Why it stays public |
| --- | --- | --- | --- |
| `session_reset` | `session_leave`, `session_apply` (`Return_To_Lobby`) | `audience_test` (1), `brain_workers_test` (2), `host_simulation_test` (2), `trainers_test` (1) | The round reset on a bare `Session`; the tests check that a reset clears public state and cannot reach saved audience history |
| `session_tick` | `begin_tick` | `dev_scenario_test` (1), `trainers_test` (2) | The public session step; those tests step a bare `Session` through the countdown and summoning with no battle runtime |
| `session_enter_arena` | `session_start_match`, `session_tick`, `dev_search_reset`; the shared scenario builders | `trainers_test` (1), `tests/vision_review` (1) | The single arena-entry path for normal play, development scenarios and fixtures |
| `battle_sync` | `begin_tick` | `host_simulation_test` (3), `tests/vision_review` (1) | Rebinding one replaced creature without ticking is what those hidden-information tests assert; `begin_tick` would also advance the session |

Residual note for the reviewer: `session_tick` alone does not rebind the private runtime; the
coordinating operation is `begin_tick`, which the host production step uses. That was already
the case before R1.

### 2d. Test-only exports

`battle_test_scenario`, `battle_test_content_with_qa` and `scent_test_scenario` in
`simulation/scenario_test.odin` stay public because `brain_workers_test.odin` and
`host_simulation_test.odin` build their worlds with them. They are fixtures, not production
API; Odin compiles `_test.odin` files into normal builds, which is the pre-existing pattern
disclosed in the original handback. The other helpers defined in simulation test files
(`movement_test_ready`, `trainer_run_test_ground`, `walk_trainer`, `reading_of`,
`silence_creature_emitters`, `pocket_arena`, `expected_coverage`) are used only inside their
own file and were left unchanged; narrowing them is a possible follow-up, not an R1 item.

## 3. Changed files

| File | Change |
| --- | --- |
| `server/simulation/trainers.odin`, `character_actions.odin`, `senses.odin`, `scent_environment.odin`, `movement.odin`, `character.odin`, `commands.odin`, `dev_search_reset.odin` | 16 inserted attribute lines, nothing else (`r1-vs-candidate.patch`) |
| `docs/codebase/server-architecture.md` | New section "The simulation's public operations and private mutation paths" (public API table with external callers, private steps per public operation, procedure visibility versus field conventions); the session mutation cell now names `session_reset` and routes the search reset through `session_apply`; the tick diagram marks its private steps; R1 handback link |
| `docs/server-refactor-r1-coding-agent-report.md` | This report |
| `docs/delegation.md` | One handback link line at the end, as the packet allows |

Not changed: every `_test.odin` file, `tests/**`, `tools/**`, `Makefile`, content, fixtures,
recordings, Godot code, `server/ai`, `server/perception`, `server/observations`,
`server/content`, the host package, the historical reports and the Team Lead review, and all
prior evidence (`baseline/`, `stage1-3/`, `independent-review/`, including the reviewer-owned
parity probe and its log). The manifest check confirms the test files and fixtures are
byte-identical to the reviewed candidate.

## 4. Test adaptations

None. No assertion, test, fixture or Makefile target was changed, skipped, or reordered.
`test-names.txt` lists every `@(test)` procedure per package from the unchanged files:
content 9, simulation 30, host 24, vision review 3, olfaction review 3, olfaction coverage 4.

## 5. Verification

`run-r1.sh` in the evidence root ran the packet's commands from the repository root, in
order, each with its own log and exit code (`exit-codes.txt`; `runner.log` has UTC times).
It was set to stop at the first failure; there was none. Whole run 19:33:48 to 19:44:13 UTC.

| Step | Command | Exit | Log (relative to the evidence root) | Result |
| --- | --- | --- | --- | --- |
| 1 | `make check_session check_ai_debugger` | 0 | `logs/make-check_session-check_ai_debugger.log` | perception 17, ai 18; content 9, simulation 30, host 24 in normal and `-debug` builds; AI debugger harness `PASS` |
| 2 | `make build_server` | 0 | `logs/make-build_server.log` | debug host built |
| 3 | `make check` | 0 | `logs/make-check.log`, `check-summary.txt` | 42 `PASS` markers and 14 Odin suite totals, all successful: olfaction review 3, olfaction coverage 4, perception 17, ai 18, content 9, simulation 30, host 24, vision review 3, each Odin package in normal and debug builds. Display `:0` was available, so the rendered probes ran; nothing was blocked. 8 min 28 s. |
| 4 | `odin build server -out:build/server-r1-release -o:speed -extra-linker-flags:"-L$(pwd)/build/deps"` | 0 | `logs/odin-build-server-r1-release.log` | optimized non-debug host |
| 5 | `connection_check` on the release host | 0 | `logs/release-connection_check.log` | `PASS: connection_check.gd` |
| 6 | `selection_check` on the release host | 0 | `logs/release-selection_check.log` | `PASS: selection_check.gd` |
| 7 | `arena_selection_check` on the release host | 0 | `logs/release-arena_selection_check.log` | `PASS: arena_selection_check.gd` |
| 8 | `movement_check` on the release host | 0 | `logs/release-movement_check.log` | `PASS: movement_check.gd` |
| 9 | `audience_delay_check` on the release host | 0 | `logs/release-audience_delay_check.log` | `PASS: audience_delay_check.gd` |

Steps 5 to 9 each ran
`godot --headless --path client --script "$PWD/tests/<check>.gd" -- --server="$PWD/build/server-r1-release"`.

Worker/serial equivalence, hidden-information, reset, sensing and diagnostic tests ran in
their normal places inside the simulation (30) and host (24) suites; none was moved, skipped
or weakened. Fixture counts are vision 3, olfaction review 3 and olfaction coverage 4; the
original handback had the two olfaction counts reversed. The seven lines in `make-check.log`
that contain the word "fail" are inside `PASS` messages describing negative-path coverage.

Post-run consistency: `source-identity/r1-source-final-check.log` verifies all 135 entries of
`r1-source.sha256` after the run (the development-workflow check edits a sandbox copy, not
the tree), and `git status --short` is identical before and after the run.

## 6. Prior-candidate evidence not rerun on R1

Clearly labeled as evidence for the reviewed candidate, not for R1: the four graphical
workflow runs, the performance comparison, the pre-refactor recording replay check, the
baseline/candidate search-outcome comparison and the rebuilt baseline tests under
`stage3/` and `independent-review/`. R1 changes visibility only; no execution path, data or
behavior changed, so no realignment of those measurements was made. The Team Lead's parity
probe (`independent-review/parity/`) is unchanged and still not counted as evidence; for the
record, it references only `simulation.advance`, `session_apply`, `session_join` and
`session_leave`, all of which remain public.

## 7. Untested, blocked and observed

- Physical keyboard/mouse input and an exported client were not exercised; client coverage is
  scripted headless checks plus the graphical harnesses inside `make check`.
- Release-build timing was not measured; the release host was exercised functionally only.
- Historical checkpoint documents still name pre-refactor file paths, as disclosed before.
- `tests/dev_workflow_check.py` still edits `server/simulation/movement.odin` by constant text;
  the inserted `@(private)` lines do not touch the text it replaces, and the check passed.
