# Server refactor R1: independent Team Lead review

Date: 2026-09-12, Asia/Manila.

Status: **ACCEPTED. R1 is closed.** The content/simulation refactor is accepted
within the agreed scope, with the nonblocking documentation note below. This does
not authorize the proposed diagnostics extraction or other follow-on changes.

Assignment: [R1 delegation](server-refactor-r1-delegation.md). Agent handback:
[R1 report](server-refactor-r1-coding-agent-report.md). The
[original independent review](server-refactor-team-lead-review.md) remains the
historical record of the finding and the earlier verification.

Independent R1 evidence:
`build/verification/server-refactor-20260912/independent-r1-20260911T200917Z/`.

## Findings

No blocking code findings remain. No runtime regression was found in the checks
run for this review.

**P3: the public-API documentation needs a small caller-classification correction.**
In the architecture document's "The simulation's public operations and private
mutation paths" section, the fixed-step row attributes `advance` to the production
host. The R1 report repeats this. In fact,
`server/host_simulation.odin:16` calls `simulation.decide_serially` on its serial
branch; `simulation.advance` is the reference path used by tests. The host's
mention of `advance` is a comment, not a call.

The same table lists `network_test.odin` under production callers. Also, the
claim that these are the only procedures another package can call should be
qualified as the production API: existing test helpers remain exported alongside
the three documented scenario builders. The agent report already acknowledges
this distinction. Correct the descriptions, not the implementation or tests.

These are documentation inaccuracies, not another runtime defect or a reason to
widen R1. They do not require another full test cycle if corrected as prose only.

## Source identity and scope

- The reviewed candidate and R1 manifests contain the same 135 paths.
- 127 file hashes match directly; exactly eight simulation source files differ.
- Independently removing only the 16 added visibility-attribute lines reproduces
  the previously reviewed contents of all eight files byte for byte.
- Fifteen attributes are `@(private)`; `trainer_tick_energy` alone gains
  `@(private = "file")`.
- No procedure body, signature, data layout, update ordering, test, fixture, tool,
  or Makefile change is part of this source delta.
- The R1 source manifest passed before and after the independent test run. The
  source-path set also matches the reviewed candidate, covering additions and
  deletions as well as changed contents.
- Godot script and content/QA-fixture hashes were independently checked against
  the saved pre-refactor manifests and match.

The review did not use Git, modify production code, weaken tests, stage files,
or create a commit. Test runs generated their normal build artifacts. This is
not an independent claim about Git status; source identity was checked using
the preserved manifests and source comparison.

## R1 closure: mutation helpers are no longer external API

The changed files are `trainers.odin`, `character_actions.odin`, `senses.odin`,
`scent_environment.odin`, `movement.odin`, `character.odin`, `commands.odin`, and
`dev_search_reset.odin`, all under `server/simulation/`.

The newly hidden operations cover trainer motion and energy, turn/action
resolution, receptor preparation, scent binding and ticking, creature movement,
facing conversion, command serial comparison, and search-reset helpers. Their
callers stay inside the simulation package. The energy helper's only caller is
in the same file, supporting its narrower file visibility.

The four retained lifecycle operations have concrete external test callers:

| Procedure | External test examples | Reason to retain this test boundary |
| --- | --- | --- |
| `session_reset` | `server/audience_test.odin`, `server/brain_workers_test.odin`, `server/host_simulation_test.odin` | Reset state without also advancing the simulation. |
| `session_tick` | `server/trainers_test.odin`, `server/dev_scenario_test.odin` | Exercise the session phase rather than a complete battle tick. |
| `session_enter_arena` | `server/trainers_test.odin`, `tests/vision_review/vision_review_test.odin` | Enter the arena directly for placement and perception fixtures. |
| `battle_sync` | `server/host_simulation_test.odin`, `tests/vision_review/vision_review_test.odin` | Bind or replace battle entities independently of decisions and elapsed time. |

Replacing these calls with `advance` would change the unit under test. Their
retention is allowed by the packet and does not reopen R1.

Procedure visibility is compiler-enforced. Ownership of publicly accessible
struct fields remains a documented convention, not enforced field privacy.
R1 does not claim otherwise or introduce opaque wrappers just to hide fields.

## Independent verification

All commands below ran against the actual R1 tree, rather than relying on the
coding agent's recorded exits. Odin was `dev-2026-03-nightly`; Godot was
`4.6.stable.official.89cea1439`; `DISPLAY=:0` was available.

| Gate | Result | Evidence inside the independent directory |
| --- | --- | --- |
| R1 source hashes and source-path set | Passed | `source-before.log`, `source-path-delta.txt` |
| `make check_session check_ai_debugger` | Exit 0 | `make-check_session-check_ai_debugger.log` |
| `make build_server` | Exit 0 | `make-build_server.log` |
| `make check` | Exit 0; 42 PASS markers | `make-check.log`, `check-summary.txt` |
| Optimized host build with `-o:speed` and the existing ENet library | Exit 0 | `release-build.log`, `server-release` |
| Release-host connection, selection, arena selection, movement, and audience-delay client checks | All five exit 0 | `release-connection_check.log`, `release-selection_check.log`, `release-arena_selection_check.log`, `release-movement_check.log`, `release-audience_delay_check.log` |
| Final R1 source hashes | Passed | `source-after.log` |

`exit-codes.txt` records the gate results. `unchanged-client.log` and
`unchanged-content.log` are quiet successful hash checks; empty output is normal.

The full suite's Odin totals were content 9, simulation 30, and host 24 in both
normal and debug builds. Vision review ran 3 tests, olfaction review 3, and
olfaction coverage 4, each in both modes. AI ran 18 and perception 17 in their
normal suite builds. "Every package in both modes" would overstate this run.

The full suite also exercised its normal rendered probes, networking, creature
behavior, diagnostic/replay tooling, assets, and development reload workflows.
Expected negative-test diagnostics are not acceptance failures.

## Evidence limits and preserved earlier results

The four separate graphical workflow modes, performance measurements, old-host
recording compatibility, and search-outcome comparison were not rerun for R1.
They remain earlier-candidate evidence, not fresh R1 results. The exact
attribute-only delta and the fresh gates above support closing this visibility
finding without broadening the assignment.

The separate reviewer-owned parity probe was left untouched. Its earlier
compilation failure is neither a server regression nor passing parity evidence;
no debug parity result exists. This acceptance does not depend on that probe.

Physical keyboard/mouse interaction, an exported client, and release-build
performance remain untested. Passing tests establish the exercised coverage,
not a guarantee that every possible multiplayer scenario is regression-free.
