# 6B.1 coding-agent report: focused and peripheral vision

Prepared for the owner and Team Lead on **2026-09-11** against the working tree of
`c74e638` plus these uncommitted changes. Status: **corrections R1–R3 applied; ready for
Team Lead re-review**. Nothing was committed; `docs/delegation.md` and
`docs/06i-vision-team-lead-review.md` were not modified. The pre-existing edits to
`AGENTS.md`, `CLAUDE.md` and `docs/scratch2/planning.md` are not part of this work.

The first section covers the correction pass. The sections after it describe the whole
candidate and were updated where the corrections changed them.

## 0. Correction pass (2026-09-11)

Evidence root: `build/verification/vision-fix-20260911/` (pinned with `.keep-logs`).
Baseline first: the Team Lead harness failed exactly as reviewed in the normal build
(`baseline-review-normal.log`, exit 1, all three tests).

| Correction | What changed | Proof |
| --- | --- | --- |
| **R1** wall edges and corners | `server/perception/grid_visibility.odin`: the bounding-box scan is replaced by a lane sweep. Cells are enumerated per lane from closed spans (`ceil(lo) - 1 .. floor(hi)`), so a segment on a grid line sees the cells on both sides, then each candidate is confirmed by the unchanged exact touch test. The old box used `floor` on both ends and skipped the neighbor on the right and bottom edges. | `make check_vision_review` exit 0 in normal and `-debug` builds (`review-normal-1.log`, `review-debug-1.log`). New perception tests: the review's literal cases plus 14 blocked / 10 clear segments in both directions, and 4,000 random segments compared against an exhaustive full-grid scan. |
| **R2** supported range and map sizes | The 70×70 cell cap is removed. Work is bounded by the map side (`perception.MAX_GRID_SIDE = 128`, checked by `grid_valid`, `content_parse_arenas` and the client `ArenaCatalog`) and range by `perception.MAX_RANGE_GAMEPLAY_UNITS = 64` (host and client sense readers). The developer reference map draws only real cells, clamped to the arena, and marks the map edge in red. | Review harness; `accepted_envelope_is_visible_bounded_and_measured` (128×128 map, 16-unit tiles, 2,048-unit range, two focused sightings at ≈2,036 and ≈1,403 units, bounded fan); host `worst_supported_vision_envelope_stays_bounded` (3,600 ticks, no allocations, both creatures focus each other across an empty 128×128 map). |
| **R3** individual lifecycle | `server/battle.odin`: `battle_sync` rebuilds everything only when unbound or the round changed; otherwise it rebinds only a slot whose entity ID changed, through the new `battle_bind_creature`. | Review harness; host `replacing_one_creature_keeps_the_other_creatures_private_runtime` covers both slots, unchanged round-wide config/limits, the kept eye staying on schedule, the kept creature's aging memory of the replaced entity, and a round change clearing both. |
| Debugger failure recorded in the review | Three graphical runs of the unfixed tree passed (`debugger-graphical-baseline-{1,2,3}.log`), so the failure has no deterministic trigger from the harness itself. Its status signature (P2 `paused`, no selection, live sequence advancing, no reader or journal error) is exactly what a pause entered before the first decision arrives produces: `_begin_browsing`/`restart_decision` set `paused` with nothing selected and the live path then never auto-selects. The inspector now pins the first decision that arrives while keeping the pause (`client/dev/ai/ai_debug_window.gd`). The test driver forces that path for P2 and the Python check asserts P1 follows live while P2 is paused on its first decision. | `debugger-headless-inspector-fix-reverted.log`: with the fix removed, the new coverage fails with the review's exact signature (P2 `paused: True, nodes: 0, selected_sequence: 0, last_sequence: 193`). `check-ai-debugger-1.log` and `debugger-graphical-fixed-1.log`: exit 0 with the fix. |

Also in this pass: `make check_vision_review` runs the Team Lead harness in both builds and is
part of `make check_vision` and `make check`; the harness assertions are unchanged. Two
`docs/codebase/` explanations were added: [sight geometry](codebase/sight-geometry.md) and
[battle runtime lifecycle](codebase/battle-runtime-lifecycle.md). Code comments on touched
code stay at one to three plain lines.

Re-measured worst supported sensing workload (serial reference, this PC): a 3-candidate sample
at the envelope corner costs ≈19 µs and the 65-ray fan ≈0.35 ms (writer thread only); a full
simulation tick with both creatures and both trainers near the far end of sight on an empty
128×128 map averages ≈6.8 µs (≤47 µs), against ≈1.9 µs on the QA arena. Record layout did not
change, so the 28 KiB record ceiling, ≈100 ms writer publish per 250 ms cycle and the ≈100 s
recording horizon at the 128 MiB cap are unchanged.

## 1. Resulting behavior, scope and limitations

Every MoPock now has a 60° focused field inside a 160° peripheral field with an 8-unit
radius, sampled every 6 ticks. The default tactic is **Observe**: hold position and turn in
place through the resolver's `Face` action (one 45° step per 6 ticks). With nothing in view
it turns one step clockwise every 30 ticks. A peripheral cue (sector and range band only)
makes it face that sector; a focused sighting (position, visible kind/appearance, facing,
visible action at the sample tick) makes it face and hold. When the subject leaves focus, the
last sighting stays as old memory at its fixed position for 3 s (0.5 s for a cue); the
creature faces that memory, then resumes scanning when it expires.

Delivered: observation and perception packages, terrain sight blocking, `senses.json`,
private visual memory, the Observe tactic, the Face action, a schema-2 telemetry/replay
envelope, Vision panels with a host-diagnostics toggle in both inspectors, a staged QA arena
(`make dev_vision`), and Odin/Godot/Python verification. Random idle/walk, its RNG and the
wander tests are removed; the shared Move capability and its resolver/presentation tests
remain.

Limitations (all documented in `docs/06g-focused-and-peripheral-vision.md`): center-point
detection only; creatures and trainers do not occlude each other; planar sight (height never
occludes); body facing is the gaze; no pursuit or other senses; `--seed` is plumbed but unused
by the deterministic tactic; in the four normal arenas creatures mostly end up watching their
own nearby trainer because the opponent starts out of range; the 65-ray display fan is a
coarse guide at long ranges (detection uses exact per-subject segments).

## 2. Ownership and refactors

See the ownership table and "How the information boundary is enforced" in the checkpoint
record. In short: `server/observations` is the data-only brain input (imported by `ai` and
the host); `server/perception` is privileged geometry that returns a sample and a separate
host-only audit; `server/senses.odin` schedules per-instance receptors from one frozen phase;
`server/ai` gained `visual_memory.odin` and `observe.odin` and lost `wander.odin`/`random.odin`;
`character_actions.odin` owns the Face turn interval in `Character_Action_Runtime` beside the
agent in `Battle_Runtime`. `Brain_Request` carries only agent, context and Observe config by
value. Later senses add their own typed evidence to `obs.Sense_Input`; later tactics consume
the same `Decision_Context` and request through the same resolver.

Correction-pass refactors: the sight enumeration is split into `cells_touching_span`,
`segment_extent_in_lane` and the sweep in `sight_probe`; the battle runtime binding is split
into the round-wide `battle_sync` and the per-slot `battle_bind_creature`. Both are the seams
later work will use (more senses reading the same grid; summon/swap replacing one slot).

## 3. Implementation choices and deviations

- **Closed-cell occlusion with a lane sweep** instead of a DDA or a bounding box: every opaque
  cell whose closed square touches the segment blocks it, in either direction. Corner cracks
  and edge-aligned rays are conservatively blocked; the exact touch test is unchanged and the
  enumeration is proven equivalent to an exhaustive scan by test.
- **Named envelope constants** rather than a work cap: `MAX_GRID_SIDE` and
  `MAX_RANGE_GAMEPLAY_UNITS` live in `perception` and are used by host validation; the client
  readers keep the same literals. Anything inside the envelope is evaluated exactly.
- **Senses bindings are an array** (`bindings: [{character, profile}]`) rather than an object,
  so duplicate bindings are detectable identically in Odin and Godot.
- **Terrain schema 2 is required**; schema-1 terrain catalogs are rejected. All fixtures were
  migrated and `tests/fixtures/content.sha256` regenerated independently in Python.
- **Per-record ceiling 28 KiB**, not the proposed 24 KiB: the measured worst case with every
  array full is 27,526 bytes; real records are about 12 KB. Oversized records/traces are
  dropped and counted.
- **Subject handle = public runtime entity ID** (already in world packets); it grants no lookup.
  Replacing a creature therefore gives it a new handle; the other creature's old memory keeps
  the old handle until expiry, which is the honest reading of "not sensed yet".
- **Scan cadence**: on entering Scan the creature waits one interval before its first scan
  turn; evidence-driven turns are immediate. Cue selection prefers the near band, then the
  smaller turn, then clockwise; focused selection keeps the attended subject, then a creature,
  then the nearest, then the lower handle.
- **Trace labels are constants**; numbers travel in `value/threshold/reference/subject`, so
  tracing allocates nothing.
- **Inspector pause before the first decision pins that decision** instead of leaving the
  window empty; the pause itself is honored. This is presentation only.

## 4. Verification

Exact commands, outcomes and evidence paths. The full table, rendered-evidence list and
measured resource use are in the checkpoint record's "Verification record". All runs below
are against the finished tree unless marked baseline.

| Command | Outcome |
| --- | --- |
| `odin test tests/vision_review -out:build/vision_review_tests -extra-linker-flags:"-L$PWD/build/deps"` (baseline, before fixes) | exit 1, all 3 tests fail as reviewed: `vision-fix-20260911/baseline-review-normal.log` |
| `make check_vision_review` (normal and `-debug`) | PASS, 3 + 3 tests: `review-normal-1.log`, `review-debug-1.log` |
| `make check_session` (chains `check_perception`, `check_ai`) | PASS: 9 perception, 7 AI, 41 host tests: `check-session-2.log` |
| `odin test server -debug -out:build/session_tests_debug -extra-linker-flags:"-L$PWD/build/deps"` | PASS, 41 tests: `check-session-debug-1.log` |
| `make check_client` | PASS (edited inspector scripts): `check-client-1.log` |
| `make check_ai_debugger` (headless, with the early-pause coverage) | PASS: `check-ai-debugger-1.log`, artifacts `build/verification/ai-debugger-20260911-040309-146223/` |
| `python3 tests/ai_debugger_check.py --godot=godot --odin=odin` with the inspector fix reverted (negative control) | exit 1 with the review's signature: `debugger-headless-inspector-fix-reverted.log` |
| `python3 tests/ai_debugger_check.py --godot=godot --odin=odin --graphical` ×3 on the unfixed tree (reproduction attempts) | all PASS: `debugger-graphical-baseline-{1,2,3}.log` |
| `python3 tests/ai_debugger_check.py --godot=godot --odin=odin --graphical` on the fixed tree | PASS, two native `AI DEBUG` windows (`native-windows-fixed.txt`), captures under `captures/`; artifacts `build/verification/ai-debugger-20260911-040454-149377/` (pinned) |
| `make check` (full suite, finished tree, includes `check_vision_review` and the headless debugger check) | PASS, exit 0: `full-check.log` |

Untested claims: physical keyboard/mouse input on the QA arena (all trainer and inspector
input in the checks is synthetic: driver keystrokes, direct key events and the driver's
signal emission for the early pause); behavior on other machines/compilers; an exported
release Godot binary (the release **Odin** host gate is exercised and rejects debug export).
The exact wall-edge and corner cases are verified by headless geometry tests, not by a
screenshot; rendering and detection share `sight_probe`.

Scenario inputs for independent harnesses: `battle_test_scenario` (any map/pick),
`battle_test_content_with_qa` (shipped content plus the staged QA arena), an in-test 128×128
arena built as JSON in `worst_supported_vision_envelope_stays_bounded`, direct
`character_resolve_intent` calls with a `Character_Action_Runtime`, `senses_prepare` on a
copied `Simulation`, `battle_sync` after changing one entity ID, and `perception.vision_sample`
/ `sight_probe` with a hand-built `Vision_Query` and `Opacity_Grid`. Godot-side fixtures:
`tests/fixtures/ai/legacy-schema1-*.json(l)` and the mutation lists in `tests/ai_trace_check.gd`
/ `tests/replay_check.gd`.

## 5. Launch and manual QA

```sh
make dev_arena P1=archer P2=orc ARENA=tiny_swords_village   # normal arena; both inspectors open
make dev_vision P1=archer P2=orc                             # staged close-quarters QA arena
make replay                                                  # latest recording; Vision panel per creature
make check_vision                                            # perception, AI, host and Team Lead review suites
```

Manual steps are in the checkpoint record ("QA arena and manual steps"). Two additions for
the correction pass: toggle Host diagnostics and confirm the red map-edge border and that only
real cells are drawn; click the empty decision timeline of one inspector before the countdown
ends and confirm it shows the first decision, paused, once the battle starts.

## 6. Documentation and recommended next work

Updated in this pass: `06g-focused-and-peripheral-vision.md` (status, geometry rules,
lifecycle, inspector pause, corrections table, rerun verification and measurements),
`06d-ai-debugger-harness.md` (pause before the first decision), `plan.md` (status),
`project-structure.md` (new docs, harness directory, Make target), `tests/vision_review/README.md`
(routine verification note only; assertions untouched), new `docs/codebase/sight-geometry.md`
and `docs/codebase/battle-runtime-lifecycle.md`, and this report.

Recommended follow-up for Team Lead review: the overlapping labels for nearby candidates and
remembered entries in the Vision panel (readability, noted in the review); rename the
inspector window titles from `MoPock P1 · … · AI DEBUG` to the generic `Character P1 · …`
form when 6B.1.1 adds the senses windows (the integration check matches on `AI DEBUG`);
silhouette/footprint detection and mutual occlusion; a `last_subject` field in attention so a
cue never carries an identity even implicitly; independent gaze; per-profile scan tuning in
`senses.json`; a physical-input session on the QA arena by the owner.
