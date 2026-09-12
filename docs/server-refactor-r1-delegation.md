# Server refactor R1: tighten the simulation API

Updated **2026-09-12**. **Status: ready for coding-agent correction; not accepted.**

This is the only active assignment. The package extraction is already
implemented and independently reviewed. Do not restart the refactor.
The [original assignment](server-refactor-original-delegation.md) is archived
for its preservation rules, not as permission for more restructuring.

## Read first

- [Independent Team Lead review](server-refactor-team-lead-review.md): finding R1.
- [Original coding-agent handback](server-refactor-coding-agent-report.md).
- [Current server architecture](codebase/server-architecture.md).

Completed independent checks found no new gameplay or multiplayer regression.
R1 is an encapsulation correction, not a gameplay repair.

## Roles and handoff

The owner manually passes this packet to the coding agent and returns its
report to the Team Lead. The coding agent implements and verifies the small
correction. The Team Lead independently reviews and tests the handback before
acceptance. Do not mark the refactor accepted yourself.

Follow the repository instructions for your agent. Codex must not access
`CLAUDE.md`. Keep work unstaged and uncommitted. Preserve the existing dirty
refactor, unrelated changes, historical reports, fixtures and recordings.
Do not publish, deploy, or change Git/host configuration.

## R1: the specific problem

The host should use the simulation's coordinating operations, not call
individual internal steps out of order. Reviewed examples:

| File | Procedures to examine | Responsibility that stays inside simulation |
| --- | --- | --- |
| `server/simulation/trainers.odin` | `trainer_tick_energy` | Energy changes as part of trainer motion. |
| `server/simulation/character_actions.odin` | `character_resolve_intent` | Resolution stays paired with confirmed feedback to the agent. |
| `server/simulation/senses.odin` | `receptor_bind`, `senses_prepare` | Receptor resets and sampling stay within their owning phases. |
| `server/simulation/scent_environment.odin` | `scent_environment_tick` | Ground scent advances at its existing point in the fixed step. |

Their reviewed production callers are inside the simulation package. These
are audit leads, not a blind replacement list: inspect actual definitions
and callers, including imported aliases, host adapters and tests.

## Authorized correction

1. Identify the starting source and keep the R1 delta distinguishable from the
   existing refactor. Start from the reviewed candidate, not the old clean
   commit or pre-refactor snapshot.
2. Audit the callable API exported by `server/simulation/`. Distinguish
   external production callers, internal production callers, same-package
   tests and external test fixtures.
3. Make implementation-only helpers package-private with `@(private)`.
   Use `@(private = "file")` only when callers, including tests, allow that
   narrower scope. Same-package tests do not require public procedures.
4. Keep necessary external lifecycle, phase, worker and diagnostic contracts
   available. Do not hide every procedure merely because it has few callers.
   Explain any helper retained solely for an external test separately from
   the production API.
5. Update `docs/codebase/server-architecture.md` to describe the actual public
   operations and internal mutation paths. Distinguish procedure visibility
   from conventions governing mutable struct fields.

The expected code change is visibility annotations, not rewritten procedure
bodies. Keep names, signatures, layouts, algorithms and call ordering.
If closing R1 requires broader changes, explain the dependency and pause
before expanding the scope.

Do not weaken assertions, skip tests, add replacement public wrappers, or
move helpers into a utility package to make compilation succeed. Preserve
useful cross-package tests. Any necessary test adaptation must be minimal,
reported explicitly, and preserve the original assertion's meaning.

## Guardrails

- No new packages or directory moves, including a diagnostics extraction.
- No opaque-state redesign, accessor framework, per-tick hashing or replay work.
- No gameplay tuning, unrelated bug fixes, content edits or Godot changes.
- Preserve authority, wire bytes, fingerprints and audience timelines.
- Preserve tick order, summon timing, sampling clocks, private memories,
  random streams, action feedback, synchronization and allocation lifetimes.
- Keep diagnostic capture, queues and formats unchanged.
- Keep comments plain and at most three physical lines per block. Prefer
  self-explanatory code; deeper explanations belong in `docs/codebase/`.

## Verification

Prior independent evidence is under
`build/verification/server-refactor-20260912/independent-review/`.
Its `candidate-source.sha256` identifies the reviewed runtime/test/tool
source. Preserve that evidence and the original `baseline/` snapshot.
Identify any starting-source differences; old passes do not prove R1 passes.

Record fresh commands, exit codes and logs in a new
`build/verification/server-refactor-20260912/r1-<timestamp>/` directory
with a `.keep-logs` marker.

Run from the repository root, recording each result and stopping on failure:

```sh
make check_session check_ai_debugger
make build_server
make check
odin build server -out:build/server-r1-release -o:speed -extra-linker-flags:"-L$(pwd)/build/deps"
```

Exercise that optimized non-debug binary with the existing client checks:

```sh
for check in connection_check selection_check arena_selection_check movement_check audience_delay_check; do
    godot --headless --path client --script "$PWD/tests/$check.gd" -- --server="$PWD/build/server-r1-release" || exit
done
```

Capture each check's command, exit code and log, not just the final command
in a sequence. Current content/simulation/host totals are 9/30/24 tests in
normal and debug builds. Preserve those tests, not merely their counts.

Keep worker/serial equivalence, hidden-information, reset, sensing and
diagnostic tests in their normal paths. Independent fixture counts are
vision 3, olfaction review 3, and olfaction coverage 4. The original handback
reversed the last two counts; use the actual counts in the R1 report.

`make check` includes rendered probes and needs a display. A blocked check
is not a pass. Report relevant failures; do not fix unrelated problems or
soften checks silently.

For visibility-only changes, do not build new benchmark/debug infrastructure.
The previous four graphical workflow runs and performance measurements may
remain prior-candidate evidence, clearly labeled. Do not claim they were
rerun on R1 unless they were. Execution, data or behavior changes would require
realignment and a broader verification plan.

## Deliverables and acceptance

- The small visibility correction and accurate architecture documentation.
- `docs/server-refactor-r1-coding-agent-report.md`, marked
  **READY FOR INDEPENDENT R1 REVIEW**, not accepted.
- A before/after visibility table with caller evidence and reasons for any
  retained public helper or test-only export.
- Starting/candidate source identity, changed files, any test adaptations,
  exact commands, exit codes, evidence paths and untested or blocked coverage.

Preserve the original coding-agent report and Team Lead review as historical
records. Link them from the R1 report rather than overwrite their results.
A concise handback link may be added to this packet without expanding scope.

The Team Lead will check that internal helpers are no longer unnecessary
external entry points, required consumers still compile, assertions are
preserved, and fresh regressions pass on the exact handed-back candidate.
Only then will it recommend closing R1 and the refactor.

## Separate reviewer-owned item

The Team Lead's extra cross-version parity probe failed to compile. That is
a review-harness issue, not a server failure or part of the coding agent's
R1 task. Leave its source and evidence unchanged. Do not claim it passed or
assign its repair to this correction. Physical-input, exported-client and
other untested coverage remain explicit limitations until exercised.

## Handback

Coding-agent R1 handback: [R1 coding-agent report](server-refactor-r1-coding-agent-report.md), marked READY FOR INDEPENDENT R1 REVIEW, not accepted.
