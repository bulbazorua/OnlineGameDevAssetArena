# 6B.2 olfaction: coding-agent report for the owner and Team Lead

Date: **2026-09-11**. Assignment: [delegation.md](delegation.md) (unchanged).
Implementation record: [06n-olfactory-trails.md](06n-olfactory-trails.md).
Deep dive: [codebase/olfaction.md](codebase/olfaction.md). All changes are
uncommitted in the working tree, beside the owner's earlier uncommitted work.
Nothing in `docs/delegation.md`, `docs/06i-*` or `tests/vision_review/` was edited.

## Delivered behavior

- **Persistent trails.** Every summoned body (both creatures, both trainers)
  deposits scent on the cells its confirmed movement crossed, every tick, at
  1.5 × intensity per second, capped at 1.0 per cell. Deposits stay after the
  body leaves, spread a faint halo to open neighbours (0.3% per neighbour per
  10 Hz step) and thin with simulation time (half-life 20 s on open ground,
  2 s on water). A cell under 0.001 becomes empty. Emission starts when
  summoning completes; a jump longer than two tiles in one tick paints nothing,
  so reset placement and replacement never draw a line. A blocked step deposits
  where the body is, never on the attempted destination.
- **Terrain rules.** `terrains.json` schema 3 names an explicit scent medium per
  terrain: open, water or solid. Solid cells never hold scent and spread goes
  around them; water carries scent briefly; the map edge is closed. Elevation
  does not enter the rules. Walking and sight blocking are separate fields.
- **Anonymous noses.** Each creature's receptor samples the field on its own
  schedule (12 ticks) inside its own reach (Archer 160 world units, Orc 256).
  A reading per class present carries strength (weak/medium/strong), freshness
  (very recent/recent/old, or unknown for the fixture shapes), a coarse compass
  bearing only when the sixteen sampled zones agree, and the zones themselves.
  No identity, owner, hostility, coordinate, action, velocity, count or route
  leaves the host. Two humans blend into one human reading; a trainer can
  mislead a searcher.
- **Self-scent.** The body's own cell is blind (¾ tile). The brain knows what
  its own body gives off and discounts same-class zones that point at ground it
  visited within the last 20 s; a scentless body discounts nothing. The shared
  8-second weak-evidence budget and 15-second cooldown bound any remaining false
  lead. Limits: another same-class body on the searcher's own recent ground is
  discounted with it; own trails older than 20 s can start a short, abandoned
  investigation.
- **Search integration.** A smelled bearing starts Investigate (`Scent_Trail`),
  presence without bearing starts Intensive search (`Scent_Presence`), fading
  memory hands over to the local-search budget (`Scent_Faded`), and extensive
  exploration resumes. Visual cues outrank smells while current; focused
  sightings keep the existing acquisition, marker and hop. Smell never sets the
  public target flag, never triggers the hop and never moves a last-seen visual
  fix. Re-steering on a smell happens at a leg end or a change of at least two
  sectors, not per sample.
- **Emission and reception are independent.** Diamond ships as the
  scentless-body QA configuration (nose on with freshness unknown, emitter
  off); the host test also runs a silenced-emitter content variant. Circle,
  Square and Triangle are geometric placeholders with no nose and no emission,
  so their behaviour on the shipped maps is unchanged; the live Disabled
  receptor status comes from real content.
- **Inspectors.** Both Senses windows have a live Olfaction page (zones per
  class at the sensor's resolution, blind disc, range ring, bearing arrow,
  readings table, own LIVE/STALE/DISCONNECTED/WAITING/DISABLED clock). The arena
  F4 panel has a **Senses · Olfaction** group with **Host scent field [F8]**,
  class filters and both observers' smell ranges; the heatmap draws the
  published field one pixel per cell, labelled as privileged world data. All of
  it is saved per player window (`scent-p1.cfg` / `scent-p2.cfg`), beside the
  untouched F6 setting. Normal and release runs open nothing and export nothing.
- **Recording.** Trace schema 4 and replay envelope 4 record the nose sample,
  scent memory, scent evidence and a separate host olfaction audit. Older
  schemas read back as before and say olfaction was not recorded. The host
  field is not recorded and replay marks it unavailable.

## Initial tuning

| Setting | Value |
| --- | --- |
| Emission | 1.5 × intensity per second (0.025 per tick), cap 1.0 per cell |
| Field step | Every 6 ticks (10 Hz) |
| Half-life | Open 20 s; water 2 s; solid holds nothing |
| Spread | 0.3% of a cell to each open neighbour per step |
| Empty threshold | 0.001 |
| Teleport limit | 2 tiles per tick |
| Nose reach / interval | Human 5 units (160), Orc 8 units (256); 12 ticks |
| Blind disc | 0.75 tile around the nose |
| Range scaling | 100% at the nose down to 40% at the reach edge |
| Bands | Weak ≥ 0.03, Medium ≥ 0.15, Strong ≥ 0.45 |
| Freshness | Very recent < 3 s, Recent < 15 s, else Old; Unknown when not estimated |
| Bearing | Valid when ≥ 35% of the zone pull agrees |
| Scent retention | 3 s from the sample tick |
| Self-trail window | 20 s of own visits |
| Steering | scent weight 3 × confidence (0.2 / 0.3 / 0.4; old × 0.7); visual cue weight 3 × 0.45 |

## Architecture and refactoring

Shared lifecycle: **configuration → scheduled measurement → private observation
→ brain input → diagnostic projection / recorded evidence**, with vision and
olfaction as two instances of the same shape and separate measurement rules.

| Responsibility | Where | Notes |
| --- | --- | --- |
| Content | `content_senses.odin`, `arena.odin`, `sense_catalog.gd`, `arena_catalog.gd` | senses schema 2 (receptor + emitter + trainer emitter), terrains schema 3 (`scent`); fixtures and digest regenerated |
| Brain contract | `observations/types.odin` | `Scent_Sample`, `Scent_Reading`, `Olfaction_Profile`, `Scent_Emitter`; `Sense_Input` has both senses with separate new flags |
| World physics | `perception/scent_field.odin` | Fixed-storage field, media rules, deposits, segment painting, step |
| Measurement | `perception/olfaction.odin` | Nose sampler, bands, bearing, freshness, host-only audit |
| Host orchestration | `scent_environment.odin`, `senses.odin`, `battle.odin` | Emitters and field inside `Battle_Runtime`; `Receptor` split into `Vision_Receptor` / `Olfaction_Receptor` with one `Receptor_Schedule` gate; scent tick before the frozen sampling phase |
| Private memory / search | `ai/scent_memory.odin`, `ai/search_scent.odin`, `search_evidence.odin`, `search_steering.odin`, `search_types.odin` | Once-only ingestion, own-trail discount, `search_follow_scent`, `cue_from_scent`, `scent_weight` |
| Diagnostics | `dev_ai_debug.odin` (schema 4, per-sense delivery clocks, queue catch-up between the two history snapshots), `dev_senses.odin` (3), `dev_search.odin` (2), `dev_scent.odin` (new), `dev_replay.odin` (envelope 4) | Field capture under a small mutex on the simulation thread; JSON and files only on the writer thread |
| Godot | `sense_feed.gd`, `trace_reader.gd`, `search_contract.gd`, `senses_window.gd` + `olfaction_*.gd`, `scent_feed.gd`, `scent_overlay.gd`, `window_preferences.gd`, `debug_overlay.*`, AI/replay windows, `search_details.gd` | Validation first, then presentation; heatmap as a texture |

Call flow per tick: `simulation_tick` → `battle_sync` → `battle_tick` →
`scent_environment_tick` (deposits, step) → `senses_prepare` (both receptors
per creature from the frozen phase) → workers decide by value → host resolves
actions → diagnostics enqueue → `ai_debug_capture_scent`.

## Changed files

New: `server/perception/scent_field.odin`, `server/perception/olfaction.odin`,
`server/perception/scent_test.odin`, `server/scent_environment.odin`,
`server/scent_battle_test.odin`, `server/dev_scent.odin`, `server/ai/scent_memory.odin`,
`server/ai/search_scent.odin`, `server/ai/scent_memory_test.odin`,
`client/dev/senses/olfaction_readings.gd`, `client/dev/senses/olfaction_sensor_view.gd`,
`client/dev/scent_feed.gd`, `client/dev/scent_overlay.gd`, `client/dev/window_preferences.gd`,
`client/dev/fixtures/content/scent_trail.arenas.json`,
`client/dev/fixtures/content/blind_tracker.senses.json`, `tests/scent_check.py`,
`tests/scent_client_driver.gd`, `tests/scent_replay_check.gd`,
`docs/06n-olfactory-trails.md`, `docs/06o-olfaction-coding-agent-report.md`,
`docs/codebase/olfaction.md`.

Modified: `server/observations/types.odin`, `server/senses.odin`, `server/battle.odin`,
`server/content_senses.odin`, `server/content.odin`, `server/characters.odin`,
`server/arena.odin`, `server/simulation.odin`, `server/dev_ai_debug.odin`,
`server/dev_senses.odin`, `server/dev_search.odin`, `server/dev_replay.odin`,
`server/ai/types.odin`, `server/ai/orchestrator.odin`, `server/ai/observe.odin`,
`server/ai/search.odin`, `server/ai/search_types.odin`, `server/ai/search_evidence.odin`,
`server/ai/search_steering.odin`, tests `server/content_test.odin`, `arena_test.odin`,
`battle_test.odin`, `senses_test.odin`, `search_battle_test.odin`,
`dev_search_reset_test.odin`, `dev_senses_test.odin`, `brain_workers_test.odin`;
`client/content/data/senses.json`, `terrains.json`, `client/content/sense_catalog.gd`,
`arena_catalog.gd`, `game_content.gd`, `client/world/terrain_tileset.gd`,
`client/dev/sense_feed.gd`, `client/dev/ai/trace_reader.gd`, `ai_debug_window.gd`,
`replay_window.gd`, `client/dev/search/search_contract.gd`, `search_feed.gd`,
`search_details.gd`, `client/dev/senses/senses_window.gd`, `client/ui/debug_overlay.gd`,
`debug_overlay.tscn`; `tests/fixtures/content/{senses,terrains}.json`,
`tests/fixtures/movement/{senses,terrains}.json`, `tests/fixtures/content.sha256`,
`tests/content_check.gd`, `arena_content_check.gd`, `ai_trace_check.gd`,
`replay_check.gd`, `search_replay_check.gd`, `ai_debugger_check.py`,
`ai_debugger_driver.gd`, `senses_windows_check.py`, `senses_window_driver.gd`;
`tools/dev_session.py` (`--qa-senses` staging); `Makefile`; docs `plan.md`,
`03f-dev-workflow.md`, `protocol.md`, `project-structure.md`, `06j`, `06k`,
`06l`, `06m`, `06d`, `06e`, `codebase/opponent-search.md`,
`codebase/live-senses-inspector.md`, `codebase/battle-runtime-lifecycle.md`.
Godot generates `.uid` files for the new scripts during import; they belong
beside the scripts like the existing ones.

## Material deviations and limitations

- **Pre-existing harness gap fixed.** On the unmodified tree,
  `tests/senses_windows_check.py` failed deterministically here: journals now
  rotate about every 7 s, and the check read only the current segment, missing
  the decision the window was showing. `tests/ai_debugger_check.py` had the
  same gap for its Orient/Observe checks once records grew. Both now read
  across rotated segments (as the search harness already did). Baseline logs:
  `baseline-senses-graphical.log`, `baseline-senses-graphical-2.log`.
- **Blind-tracker QA content for the live scenario.** With the shipped catalog,
  the two searching creatures can find each other before or while the trail is
  laid, and a creature pursuing a visible opponent rightly ignores smell, which
  made the live smell-driven-search assertion timing-dependent. The harness
  stages `blind_tracker.senses.json` (the shipped catalog with the Orc's eyes
  disabled) through the new launcher option `--qa-senses`, which mirrors the
  QA-arena staging and never touches the authored catalog. Vision precedence
  itself is covered by the AI unit tests.
- **Field resolution is the arena tile.** Trails on 128-unit tiles are blocky.
- **Zone-based nose.** The Olfaction page cannot show a tiled trail because the
  creature never receives one; the arena heatmap shows the host field instead.
- **No wind, no per-individual scent, no hearing/tactile/pain, no field
  recording.** Replay marks the field unavailable.
- **Cost.** The worst accepted envelope (saturated 128 × 128 field, 1,024-unit
  nose) costs about 2.4 ms per field step and 1.5 ms per nose sample; the
  serial worst-envelope tick rose from about 7 µs to about 250 µs on that map
  because the step runs over the box holding scent. Shipped 60 × 28 maps and
  the QA arenas stay in single-digit microseconds per tick. Journal rotation
  is more frequent because records grew (worst case 40,931 bytes).
- **Shared weak-evidence budget.** Cues and smells share the 8 s / 15 s
  budget; a smell abandoned once suppresses fresh visual cues for the cooldown.
- **Team Lead review harness and the placeholder shapes.** The independent
  regression `replacing_one_creature_preserves_the_other_creatures_private_state`
  runs 900 default-controller ticks with Circle picks and requires P2 to hold a
  *current* focused memory at that moment. On the baseline that holds by
  trajectory luck (P2's memory flips between 0 and 1 through the run and is 1 at
  tick 900; probe traces in this report's evidence directory). My first
  candidate gave the shapes human noses and scent, which changed that trajectory
  (P2 investigated its trainer's smell, abandoned, and walked off), so the
  precondition failed before the guarantee was tested. I did not touch the
  harness; I removed the arbitrary human smell from the placeholder shapes,
  which restores their byte-identical search behaviour and lets the harness run
  its guarantee. The Team Lead may want to make that precondition robust (for
  example the QA arena or the Observe controller), since any future search
  tuning can move it again. The R3 guarantee itself is also covered with real
  experience by `replacing_one_creature_keeps_the_other_creatures_private_runtime`
  and the new `replacing_one_creature_keeps_the_other_mind_and_the_ground_and_workers_agree`.

## Test commands and results

All commands ran on this PC (Odin `dev-2026-03-nightly`, Godot 4.6.stable) on
2026-09-11. Logs and inspected artifacts are pinned under
`build/verification/olfaction-20260911/` (marker `.keep-logs`); the `captures/`
subdirectories hold copies of the native captures, status files and
`performance.json` from the runs named below. Input in every automated check is
synthetic; physical keyboard and mouse acceptance remains with the owner.

| Command | Exit | Result and log |
| --- | --- | --- |
| `make check_perception` | 0 | 14 tests: existing 9 plus deposits/fade, media rules (wall, water, edge), teleport/blocked/cap, nose zones/bearing/freshness/blind disc/range, worst envelope |
| `make check_ai` | 0 | 17 tests: existing 13 plus scent memory, scent-driven search/abandonment/cooldown, cue precedence and no acquisition, own-trail discount |
| `odin test server` (normal and `-debug`) | 0 / 0 | 60 tests each: normal inside `full-check-final.log`, debug in `host-tests-final-debug-2.log`; includes trail persistence/reset, Orc reach and scentless bodies, hidden-emitter invariance, replacement and worker equivalence, bounded capture, worst-case record ceiling |
| `make check_vision_review` | 0 | Team Lead harness unchanged; 3 + 3 tests in normal and debug builds (also inside `full-check-final.log`); probe traces `review-precondition-probe-*.log` show P2's trajectory identical to the baseline |
| `make check_senses_windows` (headless) | 0 | `senses-windows-headless-4.log`: Olfaction page bound to journals across rotated segments, fixtures, disabled/empty/stale states |
| `python3 tests/senses_windows_check.py --graphical` | 0 | `senses-windows-graphical-3.log`, six native windows; latency below |
| `make check_scent` (headless) | 0 | `scent-headless-5.log`: blind-tracker trail scenario, orc reading, scent-driven decision with trace reference, heatmap equal to the published field, F8/F6 persistence over a restart, F7, replay |
| `python3 tests/scent_check.py --graphical` | 0 | `scent-graphical-2.log`, six native windows, captures `p1-scent-heatmap.png`, `senses1-olfaction.png`, `senses2-olfaction.png` |
| `python3 tests/ai_debugger_check.py --graphical` | 0 | `ai-debugger-graphical-2.log` |
| `make -k check` (finished tree) | 0 | `full-check-final.log` (keep-going mode so every target reports) |

Earlier iterations of the same logs (`*-2`, `*-3`, …) record the failures found and
fixed along the way; the final ones are named above. `full-check.log` is the earlier
full run that stopped at the review harness precondition described under deviations.

### Measured costs

| Measure | Baseline (before this slice) | Candidate |
| --- | --- | --- |
| Serial tick, close-quarters QA arena, 3,600 ticks | ≈ 2.5 µs mean, 11 µs max | ≈ 8–9 µs mean, 60–76 µs max (four emitters, two 5 Hz noses, one field step every 6 ticks) |
| Serial tick, worst accepted envelope (128 × 128 map, 16-unit tiles) | ≈ 7 µs mean, 66 µs max | ≈ 253 µs mean, 1.7–2.4 ms max (field step over the box holding scent) |
| Field step, saturated 128 × 128 field | — | ≈ 2.4 ms per step (every 100 ms) |
| Nose sample, 1,024-unit reach over 11,047 cells | — | ≈ 1.5 ms per sample (every 200 ms per creature) |
| Sense_Input / Agent by value | 176 B / 1,112 B | 296 B / 1,280 B |
| Trace record | ≈ 20.6 KB observe mode; 37,881 B worst case (schema 3) | mean ≈ 23.5–25 KB, max ≈ 28.8 KB in live search runs; 40,931 B worst case, ceiling 48 KiB unchanged |
| Journal rotation (8 MiB segments) | every ≈ 7 s in search mode | every ≈ 5.5–6 s |
| Replay recording | ≈ 22.5 KB per frame (schema 2) | ≈ 44–48 KB per frame; the 128 MiB cap arrives after ≈ 46–51 s of arena time |
| Writer full-history publish | ≈ 100–117 ms per 250 ms cycle | ≈ 112–129 ms per cycle, now split per owner with queue catch-up in between |
| Live snapshots | senses.json ≈ 6 KB, search.json ≈ 9 KB | senses.json ≈ 4–6 KB, search.json ≈ 9.5 KB, scent.json ≈ 3 KB on the 30 × 16 QA arena (worst case ≈ 88 KB, cap 96 KiB) |
| Host queue drops / oversized records | 0 / 0 | 0 / 0 in every run |
| Senses window read / update work | ≤ 0.8 / 0.83 ms | ≤ 0.73 / 1.17 ms |
| Peak memory | not measured | not measured (fixed field storage adds 213 KB per simulation; no tick allocations, verified by test) |

Delivery-to-display latency, six windows plus recording, graphical senses check
(`captures/senses-graphical/performance.json`):

| Page | Displays | p50 | p95 | max | Update gap p50 / p95 / max |
| --- | --- | --- | --- | --- | --- |
| Vision P1 | 81 | 44.6 ms | 78.2 ms | 111.3 ms | 100.0 / 133.7 / 167.0 ms |
| Vision P2 | 80 | 44.6 ms | 78.5 ms | 111.5 ms | 100.0 / 133.7 / 167.0 ms |
| Olfaction P1 | 60 | 44.6 ms | 78.2 ms | 111.5 ms | 200.0 / 234.0 / 266.3 ms |
| Olfaction P2 | 60 | 44.5 ms | 78.1 ms | 111.6 ms | 200.0 / 233.7 / 266.3 ms |

The previous 6B.1.1 record measured 95.9 / 113.0 ms p95 for the two Vision pages.
My own baseline reruns of the graphical senses check on the unmodified tree did
not reach the measurement because of the pre-existing journal-rotation gap
(`baseline-senses-graphical*.log`). The first candidate measurement was 112.7 /
113.1 ms (Vision) and 162.6 ms (Olfaction, one window, 41 samples) before the
writer learned to catch up between the two history snapshots; the table above is
the finished tree. Sensor rates are unchanged (eyes 10 Hz, noses 5 Hz).

### Pinned evidence

- `captures/scent-graphical/`: `*-p1-scent-heatmap.png` (F8 host heatmap with
  its privileged label and cell count), `*-senses1-olfaction.png` and
  `*-senses2-olfaction.png` (live Olfaction pages), `six-native-windows.txt`,
  `orc-human-reading.json` (the blind Orc's anonymous human reading),
  `scent-search-evidence.json` (its recorded `Investigate` / `Scent_Trail`
  decision and the live overlay), `scent-field.json`, `replay-check.log`.
- `captures/senses-graphical/`: `performance.json`, `*-senses{1,2}-olfaction.png`,
  `*-fixture-olfaction.png`, minimum-size and stale captures.
- `captures/ai-debugger-graphical/`: native AI windows, replay captures and logs.
- `captures/scent-headless/`: the headless run's status and evidence files.
- A replayable scenario: `captures/scent-graphical/SOURCE.txt` names the sandbox
  whose `match.replay.jsonl` (under `build/dev/*/generation-1/ai-traces-1/`) records
  the trail, the Orc's smell-driven decisions and the F7 reset; open it with
  `make replay REPLAY=<path>`.

### Manual acceptance steps

1. `make dev_scent P1=archer P2=orc`; press **F8** in the P1 window.
2. Run P1's trainer toward the Orc, walk back; watch the heatmap trail and halo.
3. Open **Olfaction** in the P2 senses window: an anonymous human reading with a
   coarse bearing; the P2 AI window's Search tab shows scent evidence.
4. Wait about 40 s: the reading fades and the Orc explores again.
5. Press **F7**: field and readings clear; restart the launcher: F8 and filters
   return, F6 settings are untouched.
6. For a pure smell tracker, add
   `DEV_QA_SENSES=--qa-senses=client/dev/fixtures/content/blind_tracker.senses.json`.


## Recommended follow-ups for Team Lead review

1. Tune emission/decay on the shipped maps with physical play; the numbers are
   authored starting points.
2. Consider recording the quantized field at a low rate for privileged replay
   if the 128 MiB recording budget allows.
3. Split the weak-evidence budget per sense if scent-driven abandonment should
   not suppress visual cues.
4. Reduce record growth or lift the journal size if rotation frequency becomes
   a QA problem.
