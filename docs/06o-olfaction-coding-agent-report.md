# 6B.2 olfaction: coding-agent report for the owner and Team Lead

Correction pass finished **2026-09-12** for the [Team Lead review](06p-olfaction-team-lead-review.md)
under the [active correction packet](delegation.md); the first candidate is described
by the [original assignment](06q-olfaction-original-delegation.md). Implementation
record: [06n-olfactory-trails.md](06n-olfactory-trails.md). Deep dive:
[codebase/olfaction.md](codebase/olfaction.md). Status: **candidate ready for Team
Lead re-review**. Nothing in `docs/delegation.md`, `docs/06p-*`, `docs/06q-*`,
`tests/vision_review/` or `tests/olfaction_review/` was edited; their SHA-256 digests
match the Team Lead's `reviewed-source.sha256.json`. The `initial-failures/` directory
of the review evidence is intact and gained only `coding-agent-before-fix-*` copies.

One note on the tree: the owner committed the working tree as `333bd1b` while this
pass was under way. That commit already contains the three host-side corrections
(`scent_field.odin`, `olfaction.odin`, `observations/types.odin`). Everything after
it, listed under *Changed files*, is uncommitted as the packet asks.

## R1–R3 outcomes

| Finding | Outcome |
| --- | --- |
| **R1** crossed cells | `scent_field_deposit_segment` now walks the step cell by cell (`scent_axis_walk` per axis) and gives each cell the share of the path inside it. Convention: a point on a grid line belongs to the higher cell, a corner crossing steps diagonally without touching the side cells, a zero-length step deposits under the body. The review's diagonal `(63.8, 63.5) → (64.55, 64.25)` deposits 4/15, 6/15 and 5/15 on `(1,1)`, `(2,1)`, `(2,2)` in both directions and leaves `(1,2)` at zero. Shares sum to the tick's emission; solid or off-map ground keeps its share out, so emission stays bounded. Stationary sources, blocked steps, teleports, resets and simulation-time stepping are unchanged. |
| **R2** freshness | A cell may only set a reading's freshness when it is detectable on its own: its level scaled by the range falloff reaches the weak band. The reading's band is the newest such cell across its reported zones. The review's 0.005 trace leaves the old trail **Old** with identical zones, strength and bearing; a trace at the weak band makes the reading honestly **Very_Recent** and appears as a Weak zone. Mixed ages resolve to the newest detectable cell; strength is independent (an old Medium trail plus a fresh detectable Weak trace reads Medium, Very recent). Receptors without estimation still say Unknown. The host audit keeps both the newest age of any trace and the newest detectable age. Sampling an old trail again yields Old again in the sample, the private memory and the search evidence. |
| **R3** coverage | Every nose sample carries sixteen `Scent_Coverage` words (`Unsampled`, `Partial`, `Sampled`), one per zone, computed by walking the whole reach box including ground beyond the map. The Olfaction page fills only measured zones (faint), stripes partly measured zones, leaves unmeasured zones as dark as unknown ground, draws the reach as an outline and the blind body disc at its true size, and counts measured / partly / unknown zones in the legend and the readings column. The review's 128-unit-tile, 32-unit-reach sample renders both probe pixels as the background colour (`101e2c`). A creature receives only the three words at its own zone resolution; the host audit's `cells_excluded` stays outside the brain input. |

Remaining limitations: coverage is coarse by design (three words per zone; a zone
that is 10% or 90% unmeasurable both read Partial). Freshness stays one band per
class reading, not per zone. The field is still tile-resolution and not recorded.
The nose sample now walks up to (2 × reach / tile + 1)² cells so the widest
accepted profile costs about 2.0 ms per sample instead of 1.5 ms.

## Changed files and call-flow changes

Host, committed in `333bd1b`: `server/perception/scent_field.odin` (cell walk),
`server/perception/olfaction.odin` (`Scent_Cell_Reach`, per-zone counts,
detectable-age tracking, coverage words, audit fields), `server/observations/types.odin`
(`Scent_Coverage`, `Scent_Sample.coverage`).

Host, uncommitted: `server/perception/scent_test.odin` (walk oracle, detectable
freshness, coverage cases), `server/dev_senses.odin` (senses.json schema 4),
`server/dev_ai_debug.odin` (trace schema 5), `server/dev_replay.odin` (envelope 5),
`server/dev_senses_test.odin` and `server/brain_workers_test.odin` (worst-case
fixtures with coverage and audit counts), `server/scent_battle_test.odin`
(coverage versus arena geometry, journal / snapshot / senses.json delivery, audit
isolation), `server/ai/scent_memory_test.odin` (old trail sampled again stays old).

Client: `client/dev/ai/trace_reader.gd` (schema 5, coverage and audit validation,
schema-4 honesty), `client/dev/sense_feed.gd` (schema 4), `client/dev/senses/olfaction_readings.gd`
(coverage counts, summary and note), `client/dev/senses/olfaction_sensor_view.gd`
(coverage-first drawing, `plot_geometry`, wrapped legend, `legend_fits`),
`client/dev/senses/senses_window.gd` (caption, footer, coverage summary, status export),
`client/dev/ai/ai_debug_window.gd` and `client/dev/ai/replay_window.gd` (coverage note on
the nose line, schema text).

Harnesses: `tests/ai_debugger_check.py` (exact serialized byte ceiling across rotated
segments, schema 5, audit keys in the leak list), `tests/senses_windows_check.py`
(`check_coverage`), `tests/senses_window_driver.gd` (live coverage assertions,
zero / partial / invalid coverage fixtures, disabled-sample coverage),
`tests/scent_check.py` (orc coverage on the small arena), `tests/ai_trace_check.gd`
(schema 5, coverage mutations, schema-4 honesty), `tests/replay_check.gd`,
`tests/search_replay_check.gd`, `tests/scent_replay_check.gd`, `tests/ai_debugger_driver.gd`
(schema 5). New: `tests/olfaction_coverage/coverage_fixture_test.odin`,
`tests/olfaction_coverage/coverage_render_check.gd`, `tools/measure_peak_memory.py`,
Make target `check_olfaction_review` (inside `check_scent` and `check`).

Docs: `06n`, this report, `codebase/olfaction.md`, `protocol.md`, `03f-dev-workflow.md`,
`project-structure.md`, `06d`, `06e`, `06l`, `codebase/live-senses-inspector.md`,
`plan.md`, `06j`.

Call flow is unchanged: `scent_environment_tick` → deposits (now the cell walk) →
field step → `senses_prepare` → `olfaction_sample` (gather with coverage → readings
with detectable freshness) → worker input by value → diagnostics. The only new
data crossing the brain boundary is the sixteen-word coverage array inside the
sample the brain already received; the brain does not act on it.

## Verification

### Independent probes before and after

Run from the repository root as listed in the review, on the unmodified tree first
(pinned under `build/verification/olfaction-fix-20260911/before/` and copied to
`build/verification/olfaction-review-20260911/initial-failures/coding-agent-before-fix-*`),
then on the corrected tree (`.../after/`).

| Command | Before fix | After fix |
| --- | --- | --- |
| `odin test tests/olfaction_review -out:build/olfaction_review_tests` | exit 1, R1 and R2 fail (`review-normal.log`) | exit 0, 3 tests (`review-normal-1.log`) |
| `odin test tests/olfaction_review -debug -out:build/olfaction_review_tests_debug` | exit 1 (`review-debug.log`) | exit 0, 3 tests (`review-debug-1.log`) |
| `godot --path client --script ../tests/olfaction_review/coverage_view_check.gd` | exit 1, near `0c1420` vs far `18293a` (`coverage-render.log`) | exit 0, both `101e2c` (`coverage-render-1.log`, `coverage-render.json`) |

`make check_olfaction_review` now runs those three plus `tests/olfaction_coverage`
(4 tests, normal and debug) and the rendered coverage probe; it is a prerequisite of
`check_scent` and listed in `check`. Both Godot probes render the real control, so the
target needs a display and fails explicitly without one.

### Suites and checks on the finished tree

All commands ran on this PC (Odin `dev-2026-03-nightly`, Godot 4.6.stable, display `:0`)
on 2026-09-12. Logs are under `build/verification/olfaction-fix-20260911/after/`.

| Command | Exit | Result and log |
| --- | --- | --- |
| `odin test server/perception` (normal, `-debug`) | 0 / 0 | 17 tests each: the 14 existing plus the walk oracle, detectable freshness and coverage cases (`host-tests-*` builds also compile them) |
| `odin test server/ai` | 0 | 18 tests: the 17 existing plus the old-trail re-sampling test |
| `odin test server` normal / `-debug`, repository ENet flags | 0 / 0 | 61 tests each (`host-tests-normal-2.log`, `host-tests-debug-2.log`), including the coverage-geometry and diagnostics test |
| `make check_olfaction_review` | 0 | 3 + 3 review tests, 4 + 4 coverage tests, both rendered probes (`check_olfaction_review-5.log`, `captures/coverage-*.png`, `captures/coverage-render.json`) |
| `make check_vision_review` | 0 | Unchanged Team Lead harness, 3 + 3 (`check_vision_review-1.log`) |
| `make check_ai_debugger` | 0 | Debug host suite, strict byte ceiling across rotated segments, schema-5 trace reader (`check_ai_debugger-1.log`) |
| `make check_search` | 0 | `check_search-1.log` |
| `make check_senses_windows` (headless) | 0 | Coverage assertions, zero / partial / invalid fixtures (`check_senses_windows-4.log`) |
| `make check_scent` (headless) | 0 | Orc coverage on the small arena, replay schema 5 (`check_scent-4.log`) |
| `python3 tests/senses_windows_check.py --graphical` | 0 | Six native windows, latency below (`senses_windows_check-graphical-1.log`, `captures/senses-graphical/`) |
| `python3 tests/scent_check.py --graphical` | 0 | Six native windows, live trail, both Olfaction pages, heatmap, reset, replay (`scent_check-graphical-1.log`, `captures/scent-graphical/`) |
| `python3 tests/ai_debugger_check.py --graphical` | 0 | `ai_debugger_check-graphical-1.log`, `captures/ai-debugger-graphical/` |
| `make -k check` (finished tree) | 0 | 42 passing checks, all suites green (`full-check-final.log`) |

The final `make -k check` on the finished tree ended with `exit=0`: 42 passing
integration checks and every Odin suite green (perception 17, AI 18, host 61 in
both builds, vision review 3 + 3, olfaction review 3 + 3, coverage fixtures 4 + 4),
including `check_olfaction_review` with both rendered probes (`full-check-final.log`).
A preliminary full run started before the last two cosmetic view edits (caption and
legend margin) also passed with `exit=0` (`full-check-final-1.log`).

Iterations of the same logs with lower numbers record the failures found and fixed
on the way: the coverage test's first expectations placed the nose on a grid corner,
the render probe first read pixels through the bearing arrow and the centre label, and
the driver's Disabled fixture kept live coverage words (which the validator rightly
refuses). The Team Lead harnesses were never edited to make anything pass.

### Rendered evidence

- `captures/coverage-zero-coverage-{700x500,400x350}.png`: the review's profile; a
  dark disc, "No ground was measured", legend fitting at both sizes.
- `captures/coverage-partial-coverage-*.png`: nose beside the north edge with a
  human trail south-east; northern far zones dark, near zones striped, the wedge
  and bearing only over measured ground.
- `captures/coverage-full-coverage-empty-*.png`: sixteen faint zones, no scent.
- `captures/senses-graphical/senses{1,2}-olfaction.png`, `*-olfaction-minimum.png`,
  `*-fixture-olfaction-no-coverage.png`, `*-fixture-olfaction-partial-coverage.png`:
  the native pages live on the vision QA arena (P1 reads "14 of 16 zones fully, 2
  partly", striped northern far zones beside the trees) and with the fixtures.
- `captures/scent-graphical/senses2-olfaction.png`: the Orc's live page after the
  trainer's trail, two anonymous readings, "Measured 6 of 16 zones fully, 5 partly;
  5 unknown", dark far zones beyond the north edge; `senses1-olfaction.png`,
  `p1-scent-heatmap.png` (F8 field, 204 cells with scent), `six-native-windows.txt`,
  `orc-human-reading.json`, `scent-search-evidence.json`, `scent-field.json`.
- Replayable corrected scenario: the path in `captures/scent-graphical/SOURCE.txt`
  (`match.replay.jsonl`, envelope 5, about 75 MB, trail, smell-driven decisions and
  the F7 reset); open with `make replay REPLAY=<path>`.

Input in every automated check is synthetic; physical keyboard and mouse acceptance
remains with the owner.

## Measured costs

| Measure | First candidate | Corrected candidate |
| --- | --- | --- |
| Serial tick, close-quarters QA arena, 3,600 ticks | ≈ 8–9 µs mean, 60–76 µs max | 11.6 µs mean, 84.6 µs max (normal); 10.2 µs mean, 80.3 µs max (debug) |
| Serial tick, worst accepted envelope (128 × 128 map, 16-unit tiles) | ≈ 253 µs mean, 1.7–2.4 ms max | 260 µs mean, 2.46 ms max |
| Field step, saturated 128 × 128 field | ≈ 2.4 ms | 2.40 ms |
| Nose sample, 1,024-unit reach | ≈ 1.5 ms over 11,047 cells | 2.01 ms over 11,047 measured cells (the walk now also classifies the 5,594 off-map cells of the reach box) |
| Sense_Input / Agent by value | 296 B / 1,280 B | 312 B / 1,280 B |
| Trace record | 40,931 B worst case | 41,232 B worst case, ceiling 48 KiB unchanged; live scent run max 28,035 B, mean ≈ 24.5 KB |
| Journal rotation (8 MiB segments) | every ≈ 5.5–6 s | every ≈ 5.7 s in the scent run (≈ 340 records per segment) |
| Replay recording | ≈ 44–48 KB per frame, cap after ≈ 46–51 s | 46,207 B per frame; the 128 MiB cap arrives after ≈ 48 s of arena time |
| Live snapshots (30 × 16 QA arena) | senses.json ≈ 4–6 KB, search.json ≈ 9.5 KB, scent.json ≈ 3 KB | senses.json 4,519 B (cap 32 KiB), search.json 9,346 B, scent.json 2,985 B (cap 96 KiB) |
| Host queue drops / oversized records | 0 / 0 | 0 / 0 in every run |
| Senses window read / update work | ≤ 0.73 / 1.17 ms | ≤ 0.67 / 1.39 ms |
| Writer full-history publish | ≈ 112–129 ms per cycle | 129 ms per cycle |

Delivery-to-display latency, six windows plus recording, graphical senses check,
production sensor rates (eyes 10 Hz, noses 5 Hz; `captures/senses-graphical/performance.json`):

| Page | Displays | p50 | p95 | max | Update gap p50 / p95 / max |
| --- | --- | --- | --- | --- | --- |
| Vision P1 | 80 | 40.6 ms | 75.6 ms | 109.5 ms | 99.8 / 135.4 / 168.1 ms |
| Vision P2 | 81 | 24.0 ms | 90.6 ms | 92.6 ms | 99.8 / 167.0 / 168.7 ms |
| Olfaction P1 | 60 | 40.4 ms | 106.4 ms | 106.9 ms | 199.9 / 266.1 / 267.2 ms |
| Olfaction P2 | 60 | 23.9 ms | 90.2 ms | 139.6 ms | 200.0 / 266.8 / 268.0 ms |

Every p95 is under the 150 ms target; no clock errors, no drops.

### Peak memory, six windows with recording

Measured with `tools/measure_peak_memory.py` (reports in
`build/verification/olfaction-fix-20260911/memory/`): `tools/dev_session.py` with
Archer versus Orc on the staged `vision_range` arena, seed 42, watcher off, AI debug
and recording on, `--run-seconds 60`; every 0.5 s the script read `/proc/<pid>/status`
(`VmRSS`, `VmHWM`) and `/proc/<pid>/smaps_rollup` (`Pss`) for the seven launched
processes. VmHWM is the kernel's resident high-water mark and includes shared
library pages; PSS divides shared pages between sharers. Excluded: GPU memory,
kernel memory, page cache, the launcher and the measuring script. The baseline is
the preserved pre-olfaction tree copy `build/verification/senses-windows-20260911-101114-549461`
(6B.1.2: search and senses windows, no olfaction), launched with the same command.

| Process | Baseline VmHWM | Candidate VmHWM | Baseline peak PSS | Candidate peak PSS |
| --- | --- | --- | --- | --- |
| Host | 10.8 MiB | 12.4 MiB | 8.7 MiB | 10.3 MiB |
| Client P1 / P2 | 213.3 / 213.4 MiB | 218.0 / 215.7 MiB | 132.5 / 132.4 MiB | 127.9 / 125.7 MiB |
| AI debugger P1 / P2 | 838.5 / 837.6 MiB | 1,009.6 / 1,004.6 MiB | 757.6 / 747.4 MiB | 919.6 / 913.8 MiB |
| Senses window P1 / P2 | 207.8 / 203.8 MiB | 208.2 / 207.0 MiB | 118.0 / 114.0 MiB | 118.4 / 117.2 MiB |
| **Sum** | **2,525 MiB** | **2,875 MiB** | **2,011 MiB** | **2,333 MiB** |

Both runs sampled 60.4 s (114–115 passes) with all six windows and the recording
active. The growth sits almost entirely in the two AI debugger windows: they keep
the same 2,048-record decision history, but each record grew from a schema-3
search record to a schema-5 record with nose sample, scent memory, coverage and
audit. The host grew by the fixed scent field and its diagnostic capture. This is a
60-second measurement on the QA arena, not a soak test.

## Outstanding QA and limitations

- Owner physical-input acceptance and exported release acceptance were not exercised.
- `make check` now needs a display for the two rendered coverage probes.
- The peak-memory figures are one 60 s run per tree on one machine; longer matches
  keep the AI windows at their bounded history but the replay file grows until its cap.
- The heatmap capture is the P1 arena window with the F4 panel open, as in the first
  candidate; the field itself is compared cell for cell by the harness.

## Owner launch and filter steps

1. `make check_olfaction_review` (needs the display): the Team Lead regressions and
   the coverage fixtures pass in both builds and the two probes write
   `build/verification/olfaction-fix-20260911/captures/coverage-*.png`.
2. `make dev_scent P1=archer P2=orc`. In the P2 senses window open **Olfaction**:
   the Orc stands near the northern trees, so the far northern zones stay dark
   ("unknown"), the near ones are striped, and the legend counts measured / partly /
   unknown zones. Toggle the **Human scent** / **Orc scent** filters to hide a class;
   the coverage drawing does not change.
3. Hold **Space + D** to run P1's trainer east past the Orc and walk back; the human
   reading appears only over measured ground with a coarse bearing. Press **F8** in P1
   and open **F4** to compare with the privileged host field.
4. Take a short diagonal step with the trainer beside a tile corner and watch the F8
   heatmap: the cell the step clips is painted too.
5. Wait about 40 s: the reading fades. A faint old trail never turns "very recent"
   by itself; only a detectable fresh trace does.
6. Press **F7**: field and readings clear, the new samples show all zones measured or
   unknown as the new placements dictate. `make replay REPLAY=<path from SOURCE.txt>`
   replays the corrected scenario with its recorded coverage.

## Recommended follow-ups for Team Lead review

1. Decide whether per-zone freshness (sixteen bands instead of one) is worth the
   extra brain-input bytes; the current contract keeps one band per class.
2. Consider a Partial fraction if QA needs to see how much of a zone was measurable;
   the three words were chosen as the smallest honest contract.
3. The AI debugger windows hold about 1 GB each with 2,048 retained schema-5
   records; a smaller retained history would cut peak memory more than any host change.
