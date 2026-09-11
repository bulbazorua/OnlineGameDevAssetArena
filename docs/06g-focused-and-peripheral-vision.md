# Checkpoint 6B.1: focused and peripheral vision

Implemented **2026-09-11**, from the [6B.1 proposal](06f-focused-and-peripheral-vision-proposal.md)
and the requirements recorded in the [Team Lead review](06i-vision-team-lead-review.md).
Status: **Team Lead technical re-review passed; R1–R3 closed. Owner physical-input
feedback remains outstanding.** The corrections table records each fix, and the
review contains independent full-suite and graphical proof. The current
[delegation](delegation.md) is for the next checkpoint, dedicated live senses windows.

```sh
make dev_arena P1=archer P2=orc ARENA=tiny_swords_village   # normal arena, production vision, two inspectors
make dev_vision P1=archer P2=orc                             # staged close-quarters QA arena with cover and water
make check_vision                                            # perception, AI and host vision suites
```

## What a MoPock does now

Every summoned character has a **60° focused field inside a 160° peripheral field**, an
**8-gameplay-unit (256 world unit) radius**, and eyes that sample every **6 ticks (10 Hz)**.
Random idle/walk is gone. The default **Observe** tactic holds position and turns in place:

1. **Scan.** With no evidence, it waits 30 ticks, then turns one 45° step clockwise, and
   repeats. The first legal turn happens immediately; later steps respect the resolver's
   six-tick turn interval.
2. **Orient.** A coarse peripheral cue (sector and range band only) makes it face that
   sector. The cue never says who or exactly where.
3. **Observe.** A focused sighting supplies position, visible kind/appearance, facing and
   visible action at the sample tick. The creature faces the observed position and holds.
   It keeps attending the same subject while that subject stays in focus; otherwise it
   prefers a visibly identified creature, then the nearest subject, with fixed ties.
4. **Reacquire.** When the subject leaves focus, the last sighting is kept as **old memory**
   at its fixed last-observed position for 3 s (a coarse cue for 0.5 s). The creature faces
   that remembered position or bearing; the memory never follows the hidden subject.
5. When memory expires without fresh evidence, scanning resumes.

An empty field is a valid state. In the four normal arenas the opponent starts 31 units
away, so each creature scans, notices its own nearby trainer when it turns toward it, and
watches the trainer; that is the documented attention policy, not a bug. Trainers are real
visual subjects.

## Ownership

| Responsibility | Code | Boundary |
| --- | --- | --- |
| Brain input contract | `server/observations/types.odin` | Data only: sightings, cues, sample, profile, facing helpers. Imported by `ai` and `main`. |
| Privileged sensing | `server/perception/vision.odin`, `grid_visibility.odin` | Sees true poses and the baked opacity grid; emits an `obs.Vision_Sample` plus a separate host-only `Vision_Audit`. Never imports `ai` or `main`. |
| Host sampling adapter | `server/senses.odin` | Per-creature `Receptor` (profile, deadline, retained sample, audit). Samples every due eye from one frozen copy of the session, after the trainer update and before either action. |
| Private knowledge | `server/ai/visual_memory.odin` | Bounded (3 + 3) focused/cue memory with original ticks and expiry; once-only ingestion keyed by sample ID. |
| Behavior | `server/ai/observe.odin`, `orchestrator.odin`, `types.odin` | Attention state, scan deadlines and Hold/Face requests from permitted evidence only. |
| Action authority | `server/character_actions.odin` | `Face` intent: one 45° step per six ticks, no translation, cancels walk preparation, obeys locks. `Move` remains a tested shared capability. |
| Per-round runtime | `server/battle.odin` | `Battle_Runtime` owns agents, receptors and turn state. A round change clears everything; an entity change rebinds only that slot ([lifecycle](codebase/battle-runtime-lifecycle.md)). |
| Content | `client/content/data/senses.json` (schema 1), `terrains.json` (schema 2) | Validated by `server/content_senses.odin`/`arena.odin` and `client/content/sense_catalog.gd`/`arena_catalog.gd`; both fingerprints cover four files. |
| Diagnostics | `server/dev_ai_debug.odin`, `dev_replay.odin` (schema 2), `client/dev/ai/trace_reader.gd`, `vision_view.gd` | Records consumed evidence, memory before/after, branches, confirmed result and a labelled host audit. Writer-side ray fan only. |

### How the information boundary is enforced

- `Brain_Request` carries an `ai.Agent`, an `ai.Decision_Context` and an `Observe_Config` by
  value. `Decision_Context` holds identity, tick, own position/facing, `can_act`, `turn_ready`
  and one `obs.Sense_Input`. There is no session, arena, candidate list, callback or audit
  reachable from the `ai` package; it imports only `observations`.
- `perception.vision_sample` returns the sample and the audit as two values. The audit (per
  candidate verdict, exact position, distance, alignment, origin opacity, sight-test counts)
  stays in `Receptor.audit` on the host and travels to diagnostics as `host_audit`, outside
  `input`, `before` and `after`. The Godot readers and the process check reject any brain-side
  record that contains audit fields.
- A `Peripheral_Cue` has exactly three fields: observation ID, sector, band. The Godot reader
  rejects cues with extra keys and rejects non-zero evidence in unused array slots, so removed
  detail cannot linger.
- Focused detail is removed by the next sample that lacks the subject; a peripheral cue never
  refreshes a remembered position (memory keys cues by absolute bearing and band, sightings by
  subject handle). `memory_ingest` refuses repeated sample IDs and non-new inputs.
- Hidden-world tests compare P1's agent, delivered sample and public character across two
  simulations that differ only in unseen state; the host audit is explicitly excluded from that
  comparison and is asserted to differ.

### Geometry rules

- Eye origin is the authoritative ground position; the cone axis is the eight-way body facing.
  Sprites, cameras and interpolation never affect sight.
- A candidate center is visible when `distance <= range + 1e-4`, `dot(normalize(d), forward) >=
  cos(half field) - 1e-4`, and the segment eye→center touches no opaque cell. Focus uses the
  same test with the focused half angle; boundaries belong to the inner class (focused edge is
  Focus, outer edge is Peripheral, range edge is inside).
- **Closed-cell occlusion.** Every opaque cell whose closed square touches the segment blocks
  it, on every side, at endpoints and at corners, in either direction: a ray exactly on the
  boundary between an open and an opaque column is blocked, and so is a ray ending on a
  wall's corner. An opaque origin or target cell blocks. Any endpoint outside the map blocks;
  the map's outer boundary line itself is inside. Cells are enumerated by a lane sweep along
  the segment and confirmed by an exact touch test, so work grows with segment length and
  there is no work limit that can invent cover ([sight geometry](codebase/sight-geometry.md)).
- **Supported envelope.** Maps of 3–128 cells per side with 16–128-unit tiles and vision up to
  64 gameplay units (2,048 world units) are accepted by both content readers
  (`perception.MAX_GRID_SIDE`, `perception.MAX_RANGE_GAMEPLAY_UNITS`) and evaluated exactly.
  The developer reference map draws only real cells and marks the map edge; the 65-ray fan is
  a coarse visual guide at long ranges, never the detector.
- Terrain `blocks_vision` is authored: stone, cliff, forest and building block sight; grass,
  ground, sand, stairs, tall grass and **water** do not. Walkability is untouched.
- Sight is planar: elevation never enters the query, so height alone never occludes and
  opaque cells block at every level. Buildings use their baked terrain footprint. Trainers
  and creatures do not occlude one another. Partly exposed bodies are not detected (center
  point only). Coincident positions are Focus when the origin cell is transparent; NaN or
  infinite input is `Invalid` in the audit and never a sighting.
- Peripheral quantization: signed angle from forward to the subject, rounded to the nearest
  45° sector (positive is clockwise on screen); `Near` is `[0, R/2]`, `Far` is `(R/2, R]`.
  Detections in the same sector and band merge into one cue; cues are sorted by band then
  sector and numbered after filtering, so cue order and count cannot leak identity.

### Configuration

`client/content/data/senses.json` (schema 1) holds `profiles` and one binding per selectable
character. Both readers require `0 < range_units <= 64`, `45 <= focused < overall <= 180`,
an integer interval `1..60`, finite numbers, unique keys and exactly one binding per character;
a disabled profile is still validated. The gameplay ruler converts range once (×32). The
Observe tuning (`ai.observe_defaults`: 180/30 tick retention, 30-tick scan interval, one
sector per scan step) and the turn interval (`CHARACTER_TURN_INTERVAL_TICKS = 6`) are
explicit constants recorded in every trace (`config`). Sample interval is per profile; each
instance owns its own deadline.

## Sampling and causality

`battle_tick` calls `senses_prepare` before building contexts. It copies both character
records and both trainer records once, then evaluates each due eye against that copy. A
non-due eye keeps its last sample byte-for-byte (`vision_is_new = false`), including its
original pose and tick, so a worker cannot learn anything from re-reading it. Both worker
requests are submitted before either is collected, exactly as before; the serial reference
path is unchanged and compared against the threaded path in the worker tests. Turning changes
sight only at a later sample. The order of the two receptor evaluations does not change
either observer's sample (tested by swapping slots).

Statuses are distinct: `Waiting_For_Summon` during the lock, `Disabled` for a disabled or
invalid profile, `Sampled` for a completed sample (possibly empty), and `Unsupported` is
reserved. Only a `Sampled` sample with `vision_is_new` can be ingested.

Replacing one creature (a new runtime entity ID in the same round) rebinds only that slot:
a fresh agent, receptor, anchor and turn timing. The other creature's memories, attention,
retained sample, sampling deadline and turn timing are untouched, and its old memory of the
replaced entity ages normally until it expires. Leaving the arena or changing the round
still clears both creatures.

## Diagnostics and replay

Trace schema **2** (`AI_DEBUG_SCHEMA`) records `input` (context with the sample), `config`,
`before`/`after` agents (memory and attention), `decision_reason`, `result` (with confirmed
facing), `facing_after`, the trace nodes (now with `reference` observation/sample IDs and
`subject` handles), `host_audit` and a writer-side `sight_fan` (65 clipped rays, cached per
round/observer/sample and never computed on the simulation or creature threads). The
per-record ceiling is **28 KiB**, chosen from a measured worst case of 27,526 bytes with every
array full; real records measure about 12 KB. Oversized records are dropped and counted
(`oversized_records`), and a replay frame that would exceed 120 KiB keeps its world packet and
drops its traces (`oversized_frames`). Existing limits (48 nodes, 256 queued messages, 128
snapshot records, 2,048 browsable records, 8 MiB journals, 128 MiB recording) are unchanged.

The replay envelope is schema **2** with `trace_schema: 2`. Readers still decode envelope 1
with schema-1 traces (the checks use genuine schema-1 fixtures under `tests/fixtures/ai/`);
they never invent eyes for them, and a schema-1 payload labelled schema 2 is rejected. Old
recordings still open with their retained staged project through `make replay`.

Each AI window has a **Vision** tab (creature knowledge: cyan focused field and sightings,
amber peripheral field and sector/band wedges without dots, violet dashed aged memory, self at
the sampled pose plus a distinct decision-time marker) and a **Host diagnostics** toggle that
adds the reference opacity map (real cells only, red map edge) and rejected candidates,
labelled as developer knowledge. A pause entered before the first decision exists pins that
first decision when it arrives; the inspector is never left paused on nothing.
Stepping reveals memory only after its update node and the confirmed result only after the
Outcome node. Selecting a branch shows the evidence it referenced. The replay window shows the
same view beside each decision graph, driven by the recorded sample of the selected frame,
including samples older than that frame.

## QA arena and manual steps

`make dev_vision P1=archer P2=orc` stages `client/dev/fixtures/content/vision_range.arenas.json`
into the private candidate's `arenas.json` (both host and clients read the staged copy, so the
fingerprint matches and the recording stays replayable). The authored maps are untouched.

Layout (24×14 cells): P1 trainer spawns at (5,5) with its creature at (7,5) facing east; P2
trainer at (14,10) with its creature at (12,10) facing west. A stone wall occupies (11..12,7),
a water pool (9..12, 2..3). Each creature starts as a peripheral cue for the other (sector 1,
far band); each trainer starts behind its own creature and out of the other's range.

1. Launch and watch both inspectors' Vision tabs: at the first unlocked tick both creatures
   turn one step toward the cue (P1 to south-east, P2 to north-west); at the next sample each
   shows the other as a focused sighting and holds.
2. Walk P2's trainer north along column 14 with W. Row 8 is hidden from P1 by the wall; row 6
   is visible again. Watch P1's cue/sighting for that trainer appear and disappear while the
   other creature stays in focus.
3. Walk P1's trainer around the water pool toward (11,1): P1 sees it across the water once it
   enters the field, although the trainer must walk around the pool.
4. Move a watched trainer behind the wall and stop: the inspector shows a violet remembered
   marker with age, the creature holds facing it (Reacquire), then resumes scanning after 3 s.
5. Toggle Host diagnostics to compare the reference map and rejected candidates with what the
   creature received; toggle it off and confirm the creature view did not change.
6. `make replay` after Ctrl+C: seek to a frame between samples and confirm the Vision panel
   shows the older sample tick and the memory before/after stepping.

## Corrections after review

Applied on 2026-09-11 against the review's three required corrections. Logs for the
correction pass are under `build/verification/vision-fix-20260911/` (pinned with
`.keep-logs`); the baseline reproduction of all three failures is `baseline-review-normal.log`.

| Correction | Change | Proof |
| --- | --- | --- |
| R1 wall edges and corners | `sight_probe` enumerates cells with a lane sweep whose closed spans include the cells on both sides of a grid line, then confirms each with the exact touch test. The old bounding box used `floor` on both ends and skipped the neighbor on the right and bottom edges. | `tests/vision_review` passes in both builds; new perception tests `opaque_cell_edges_corners_and_endpoints_block_regardless_of_direction` (14 blocked and 10 clear literal cases, both directions) and `lane_sweep_matches_exhaustive_cell_scan` (4,000 random segments against a full-grid scan). |
| R2 supported range and map sizes | The 70×70 work cap is gone. Work is bounded by the map side instead (`MAX_GRID_SIDE = 128`, checked by `grid_valid` and both arena readers) and the range by `MAX_RANGE_GAMEPLAY_UNITS = 64` (both sense readers). The reference map draws only real cells with the map edge marked. | Review harness; `accepted_envelope_is_visible_bounded_and_measured` (128×128 map, 16-unit tiles, 2,048-unit range: two focused sightings at about 2,036 and 1,403 units, bounded fan, timing); host `worst_supported_vision_envelope_stays_bounded` (3,600 ticks, no allocations, both creatures focus each other across an empty 128×128 map). |
| R3 individual lifecycle | `battle_sync` rebuilds everything only when unbound or the round changes; otherwise it rebinds only a slot whose entity ID changed through `battle_bind_creature`. | Review harness; host `replacing_one_creature_keeps_the_other_creatures_private_runtime` (both slots, round-wide fields unchanged, kept eye stays on schedule, old memory of the replaced entity ages until expiry, round change clears both). |
| Debugger integration failure from the review | Reproduced deterministically: a pause before the first decision exists (a click on the empty history) left the inspector paused on nothing forever. The inspector now pins the first decision that arrives while keeping the pause. Three graphical runs of the unfixed tree did not reproduce it by chance (`debugger-graphical-baseline-{1,2,3}.log`); the driver now forces the path for P2. | `debugger-headless-inspector-fix-reverted.log` shows the review's exact signature (P2 `paused`, `nodes 0`, live sequence advancing) with the fix removed; `check-ai-debugger-1.log` and `debugger-graphical-fixed-1.log` pass with the fix and the new assertions. |

The assertions in `tests/vision_review` were not changed; `make check_vision_review` now runs
them in both builds and `make check_vision`/`make check` include it.

## Verification record

Automated (headless), rendered and physical-input coverage are listed separately. All
commands ran on this PC with Odin `dev-2026-03-nightly` and Godot 4.6.stable on 2026-09-11,
rerun after the corrections above.

### Automated

| Command | Result |
| --- | --- |
| `make check_perception` | 9 tests: eight facings and exact boundaries, coincident/self/invalid/disabled inputs, closed-cell occlusion rules (clear lane, water, wall, opaque origin/target, diagonal corner, edge-aligned ray, map edge, largest map, oversized grid rejected), the review's edge/corner/endpoint cases in both directions with clear controls, sweep-versus-exhaustive equivalence on 4,000 random segments, the accepted envelope with timing, coarse/deduplicated/position-invariant cues, bounded display fan, facing helpers. |
| `make check_ai` | 7 tests: once-only ingestion with original times, expiry/eviction/tick wrap, cue→orient→focus→observe→memory→reacquire→scan sequence, fixed selection rules, locks/reset/private ownership, tracing equivalence over 2,400 ticks, evidence references and capacity loss. |
| `make check_session` (release and `-debug`) | 41 host tests: every map/pick observes without translating, Face legality/intervals/ties/locks/preparation cancel, shared Move rules, audience/diagnostics invariance, hidden-world invariance with positive and equivalent-cue cases, QA-arena geometry, frozen-pose sampling with independent deadlines and slot-order independence, one-creature replacement keeps the other's runtime, worst-envelope workload, no tick allocations, worst-case record ceiling, oversized drops, schema-2 journals/replay/end records. |
| `make check_vision_review` | The Team Lead's 3 independent regression tests (wall edges/corners both directions, accepted range on 16-unit tiles across a 128×128 map, P1 replacement preserving P2) pass in the normal and `-debug` builds. |
| `make check_content`, `make check_arena_content` | Godot readers agree on `senses.json`, terrain schema 2 sight blocking, the four-file fingerprint and the regenerated fixture digest; tile metadata carries `blocks_vision`. |
| `make check_character_ai` | Real host, two players and a 5 s delayed audience on Tiny Swords Village: creatures never translate, turn in ≤2 steps per snapshot, settle facing their own trainers, lose sight when the trainer walks past, then turn again; stalled feed freezes facing; mirror shapes scan after a normal countdown. |
| `make check_ai_debugger` | Real host, two inspectors, audience and replay on the staged `vision_range` arena: both creatures reach facings SE/NW with locomotion idle; journals contain `Orient` records with one cue and `Turned`, `Observe` records with a focused sighting; no brain-side record carries audit fields; cues have exactly three fields; every journal line ≤ 28 KiB; P1 follows live decisions while P2's driver pauses before its first decision and must show that decision; inspector stepping hides memory changes before their node; legacy schema-1 snapshot/replay fixtures decode and are rejected against current content; window close, reload, relaunch, release gate and cleanup pass. |
| `make check_dev` | Launcher, live visual reload, failed saves, code/data relaunch (including an `observe.odin` edit) and cleanup. |
| `make check` | Full regression suite passed on the corrected tree (exit 0), including `check_vision_review`; log `build/verification/vision-fix-20260911/full-check.log`. The original candidate's run is `build/vision-verify-full-check.log`. |

### Rendered (native windows and screenshots)

After the corrections, `python3 tests/ai_debugger_check.py --graphical` passed with two
native `AI DEBUG` windows recorded by `wmctrl` (pinned artifacts
`build/verification/ai-debugger-20260911-040454-149377/`, copies of the captures under
`build/verification/vision-fix-20260911/captures/`). Inspected images: `ai1-vision.png`
(P1 at tick 203: cyan focused field, amber peripheral field, the far-band sector-1 cue
wedge, the requested SE turn and the confirmed facing; the fan is clipped where the stone
wall at cells 11–12 × 7 cuts the field), `ai1-vision-host.png` (reference map with red
sight-blocking cells, the red map-edge border, rejected candidates and the audit line),
`ai2-vision.png` (P2 pinned by the early pause, later stepped to a retained sample with two
focused sightings and their remembered entries), `ai1-tree.png`, `ai2-tree.png`,
`replay-vision-p1.png`/`p2.png` (same panel beside the recorded decision graph, header
"replay schema 2 / trace schema 2"). Rendering and detection share `sight_probe`, so the
clipped fan and the delivered verdicts follow the same closed-cell rule; the exact edge and
corner cases are covered by the headless geometry tests rather than by a screenshot. The
original candidate's captures remain under `build/verification/ai-debugger-20260911-031507-73040/`
and `build/verification/character-ai/`.

### Physical input

Not exercised. All trainer input in the checks was synthetic (driver keystrokes or direct
key events). The owner's manual pass on `make dev_vision` covers physical input.

### Measured resource use (two creatures, QA arena, this PC)

| Measure | Value |
| --- | --- |
| Serial simulation tick with vision (3,600 ticks, QA arena) | ≈1.9 µs mean, ≤13 µs max, 1,170 eye samples, no tick allocations |
| Serial tick at the worst supported envelope (128×128 map, 16-unit tiles, 2,048-unit range, both creatures and trainers near the far end of sight, 3,600 ticks) | ≈6.8 µs mean, ≤47 µs max, no tick allocations |
| One 3-candidate sample / one 65-ray fan at that envelope with one cell in five opaque | ≈19 µs / ≈0.35 ms (fan runs on the writer thread only) |
| `Sense_Input` / `Agent` payload | 176 B / 344 B by value per worker request |
| Schema-2 record | mean 12.2 KB, max 12.4 KB observed; worst-case fixture 27.5 KB; ceiling 28 KiB |
| Snapshot (128 records) | 1.58 MB; writer publish ≈100 ms per 250 ms cycle for both creatures (was ≈36 ms with schema 1) |
| Replay recording | ≈22.5 KB per frame (1,235 frames = 27.7 MB); the 128 MiB cap arrives after roughly 100 s of arena time (was ≈4.5 min) |
| Inspector browsing | selection p95 2.8–3.5 ms at 2,048 retained records (budget 12 ms); background snapshot read/validation ≈43–53 ms |
| Queue/drops | 256-message queue, 0 drops, 0 oversized records in every run |

Growth limits: publish cost and recording duration scale with record size and creature count;
the writer already spends about 40% of one core at two creatures. The corrections changed no
record layout, so the 28 KiB ceiling, the ≈100 ms publish per 250 ms cycle and the ≈100 s
recording horizon are unchanged. Options for later work are in the report.
