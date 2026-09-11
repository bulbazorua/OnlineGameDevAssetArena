# Assignment: correct the 6B.2 olfaction candidate

Repository: `/home/burpazor/Code/Personal/BulbaZorua/OnlineGameDevAssetArena`

Updated **2026-09-11**. Status: **Team Lead review requires corrections**.
Implement R1–R3 below and complete the missing verification. This is the active
coding assignment; return a corrected working candidate for re-review.

## Roles and scope

You are the **coding agent**. The owner manually sends this packet and returns
your report to the **Team Lead**, who independently reviews and tests the work.
Choose the algorithms, internal APIs, data structures and rendering approach.
This packet defines behavior, ownership boundaries and acceptance evidence.

The full feature is already implemented in an uncommitted working tree. Repair
it without restarting the milestone or replacing earlier vision/search work.
The original scope remains in [the archived assignment](06q-olfaction-original-delegation.md).

Keep `docs/delegation.md`, [the Team Lead review](06p-olfaction-team-lead-review.md),
`tests/vision_review/` and `tests/olfaction_review/` Team Lead-owned and unchanged.
Add your own tests and integrate the review harness without weakening its
assertions. Preserve unrelated dirty files. Do not stage or commit.

Follow the instructions for your agent identity: Claude reads `CLAUDE.md` and
must not access `AGENTS.md`; Codex reads `AGENTS.md` and must not access `CLAUDE.md`.
Use generic creature/character/perception names in code. Comments must be simple,
necessary and preferably one line, never more than three consecutive lines.
Keep deeper explanations in `docs/codebase/` and split unclear operations into
readable functions.

## Read first

- [Team Lead findings and independent reproductions](06p-olfaction-team-lead-review.md).
- [Candidate implementation](06n-olfactory-trails.md),
  [handback report](06o-olfaction-coding-agent-report.md) and
  [olfaction deep dive](codebase/olfaction.md).
- [Sensory contract](06j-combat-sensory-system.md),
  [private search](06m-naturalistic-opponent-search.md),
  [live senses windows](06l-live-senses-windows.md) and
  [protocol/version boundaries](protocol.md).
- The live source around each finding and both Team Lead regression harnesses.

Existing perception, AI and host suites pass in both builds (14 / 17 / 60 tests),
the unchanged vision review passes, and fresh graphical scent integration passes.
The new independent regressions still fail. Do not treat another unchanged-suite
pass as sufficient proof of the corrections.

## R1: every crossed tile receives its movement deposit

The review demonstrates an ordinary short diagonal step that crosses an
intermediate cell without depositing there, in either direction. See the exact
positions and source location in the review.

Required outcome:

- Ground actually traversed by confirmed movement receives a continuous trail
  under a documented edge/corner convention. Include very short diagonal
  crossings and fast trainer movement, across the accepted tile-size envelope.
- Untouched cells do not receive movement deposits. Later diffusion remains a
  separate environmental operation; it cannot stand in for missing deposition.
- Keep total emission bounded and preserve stationary sources, blocked movement,
  solid terrain, map limits, teleport/reset and simulation-time behavior.
- Provide regression evidence beyond the literal failing example, including
  both directions and nearby paths that should leave neighboring cells untouched.

Keep this responsibility in the host environmental update. No brain, renderer
or inspector should create a substitute trail.

## R2: freshness must describe the scent actually detected

An undetectably faint fresh human trace currently changes an old detectable
human trail from **Old** to **Very_Recent**, while detected zones, strength and
bearing remain unchanged.

Required outcome:

- Estimated freshness is supported by the detectable evidence represented in
  that reading. A below-detection trace must not independently rejuvenate it.
- Define the behavior for mixed-age deposits, multiple zones and mixed strength
  without identifying sources or implying their current occupancy.
- Preserve meaningful aging, genuinely detectable recent scent, and Unknown
  freshness for receptors that cannot estimate it. Do not hide the defect by
  disabling freshness or changing the test's detection thresholds.
- Check both scent classes, near-threshold cases and the downstream private
  evidence/trace/replay path. Sampling an old trail again must not make it new.

The receptor reports evidence; the brain continues to own its interpretation.
Scent still cannot refresh a visual fix, identify an opponent or trigger the
target-found marker/body hop.

## R3: the local heatmap must be honest about what was sampled

The review's production-generated sample measures zero cells, yet the actual
Godot Olfaction control draws a ring labeled **sampled, no scent**. Its generic
range circle also implies coverage beyond map limits.

Required outcome:

- Distinguish sensor reach, actual sampled coverage, sampled absence and unknown
  space at the nose's advertised coarse resolution. No empty reading may imply
  that every part of the configured range was measured.
- Correctly represent blind regions, map edges, excluded/solid areas, partial
  zones and valid small-range/large-tile profiles. Keep aggregate zones visibly
  coarse; do not invent a precise source trail from them.
- Preserve the information needed for that distinction across sampling,
  scheduled delivery, validation, live presentation and recorded evidence.
  Respect sample/observer/round identity, stale states and separate sense clocks.
- Keep full-field data and privileged audits outside worker inputs and the
  creature-readings page. Do not give a creature an arena map to repair its UI.
- Both native Olfaction pages need rendered evidence for actual coverage,
  sampled-empty areas and unsampled areas. Include zero coverage and partial
  coverage. Maintain readable legends at supported window sizes.

Fixing only the visual clamp does not resolve map/zone coverage. Choose the
smallest consistent contract that represents the real measurement. If that
changes a schema, update its consumers deliberately and keep historical
recordings honest about information they lack.

## Preserve the architecture and accepted behavior

Keep the common perception lifecycle: configuration, independent measurement
schedule, private observation, brain input, diagnostic projection and recording.
Measurement rules remain specific to each sense; private memory and search
remain specific to each creature.

Preserve anonymous Human/Orc blending, the Orc range advantage, independent
emitter/receptor configuration, bounded self-trail handling, vision priority,
private serial/worker equivalence and individual replacement behavior. Keep
six development windows, live senses while decisions are paused, saved F6/F8
filters, F7 clearing, exploration memory, trainer running and the corrected
creature body hop.

Reading rotated journal segments, isolated `--qa-senses` content and explicit
inert shape profiles are accepted decisions. Keep them. Do not add hearing,
pain, advanced learning, individual scent recognition, global pathfinding or
an unrelated framework in this correction.

## Complete the verification

1. Run the independent probes as listed in the review before and after fixing
   the code. Preserve their failing evidence under
   `build/verification/olfaction-review-20260911/initial-failures/`.
   Integrate their normal/debug guarantees into a repeatable Make target and
   the normal check path. Keep the rendered probe explicitly graphical.
2. Extend focused tests for each correction and demonstrate that they catch the
   original failure, then pass on the finished candidate. Preserve existing
   privacy, schedule, lifecycle, replay and vision review guarantees.
3. Restore a strict check of actual serialized journal bytes against the
   advertised record ceiling across rotated segments. The new re-encoded-JSON
   check with a 1,024-byte allowance is weaker than the original guarantee.
   This is a harness correction; no production oversized record was observed.
4. Supply the missing peak-memory measurement for the specified six-window,
   recording-enabled workload. Name the processes, measurement method, duration
   and included/excluded memory. A fixed field-size assertion is not this
   measurement. Use a preserved baseline where practical; disclose unavailable
   comparisons instead of presenting estimates as measurements.
5. Rerun relevant perception/AI/host suites in normal and debug builds, the
   headless and graphical scent/senses/debugger checks, and one final full
   `make check` on the finished tree. Recheck payload limits and p50/p95/max
   delivery-to-display latency if sample size or publication changes. Keep the
   150 ms p95 target and normal production sensor rates.

Use isolated QA settings. Do not alter the owner's saved debug preferences or
authored arenas. Pin logs, captures and a replayable corrected scenario. Separate
synthetic input, rendered inspection, measured performance and physical-input
coverage in the report.

## Handback

Update `docs/06n-olfactory-trails.md`, `docs/06o-olfaction-coding-agent-report.md`
and the relevant deep dives/protocol/workflow documents. Keep roadmap status at
**candidate ready for Team Lead re-review** until the Team Lead accepts it.

Report:

- R1/R2/R3 outcomes and remaining limitations.
- Your changed files and concise architecture/call-flow changes.
- Exact commands, exit codes, original-failure evidence and corrected captures.
- Measured costs, memory, payload sizes, recording duration and outstanding QA.
- Simple owner launch/filter steps for checking the corrected trails and coverage.

Leave this packet, the Team Lead review and both Team Lead harnesses unchanged.
Leave all work uncommitted. The owner will return your report for re-review.
