# Archived 6B.2 implementation assignment

Preserved on 2026-09-11 before Team Lead correction review. The assignment below
is historical; [delegation.md](delegation.md) contains the current correction
packet and [the review](06p-olfaction-team-lead-review.md) records the findings.

---

# Assignment: olfactory trails, private sensing and live heatmaps

Repository: `/home/burpazor/Code/Personal/BulbaZorua/OnlineGameDevAssetArena`

Updated **2026-09-11**. Milestone **6B.2**. Status: **ready for implementation;
not implemented or accepted yet**. This is the active coding assignment.
It replaces the [completed live-senses assignment](06l-completed-senses-delegation.md).

## Roles and authority

You are the **coding agent**. Implement the complete slice below, including
necessary refactoring, diagnostics and verification. Choose algorithms, data
structures, internal APIs, file layout and rendering technique. This packet
specifies behavior, architecture boundaries and acceptance evidence, not an
implementation recipe. Return a working candidate, not another proposal.

The owner manually sends this packet to you and returns your report to the
**Team Lead**, who independently reviews the source, runs checks and records
acceptance or corrections. Keep `docs/delegation.md` Team Lead-owned. Do not
commit, stage or overwrite unrelated work. The working tree already contains
substantial uncommitted features and documents; record your own changed files.

Follow the instructions for your agent identity: Claude reads `CLAUDE.md` and
must not access `AGENTS.md`; Codex reads `AGENTS.md` and must not access `CLAUDE.md`.
Use generic character, creature, sense and perception terminology in code.
**MoPock is conversational shorthand, not an identifier or schema name.**

## Read first and establish the baseline

- [Combat sensory contract](06j-combat-sensory-system.md), especially olfaction.
- [Current search behavior](06m-naturalistic-opponent-search.md) and
  [search architecture](codebase/opponent-search.md).
- [Live senses windows](06l-live-senses-windows.md), including the later
  **Exploration memory** addition; [arena sense filters](06k-arena-sense-overlay.md).
- [Vision implementation](06g-focused-and-peripheral-vision.md) and
  [Team Lead regression review](06i-vision-team-lead-review.md).
- [Trainer running and corrected creature surprise hop](05c-trainer-running-and-target-alert.md).
- [Debugger](06d-ai-debugger-harness.md), [replay](06e-qa-replay-and-trace-browsing.md),
  [workflow](03f-dev-workflow.md), [protocol](protocol.md) and [roadmap](plan.md).

Read the live source before choosing the changes. Current public protocol is 11;
older implementation records describe their historical protocol versions.
Vision, private search, six development windows, exploration-memory inspection,
F6 saved search settings, F7 reset, trainer running and the body hop already work.
Olfaction is currently an unavailable panel. Do not restart earlier assignments.

Reference project, read-only:
`/home/burpazor/Code/Personal/BurpazorTechnologies/2dRpgGameEngine`.
Inspect `game/creature_scent.odin`, `game/creature_scent_draw.odin`,
`game/creature_olfaction.odin` and the food-scent field as useful references.
The reference creature plumes follow live emitters and include individual scent
identity. This assignment requires persistent trails and anonymous scent classes.
Borrow useful presentation ideas; do not copy those different knowledge rules,
its local A* planner, or its comment style into this repository.

## Required player-visible result

A creature walks through the arena and leaves a scent trail. Another creature
can detect a nearby remnant after the source has gone, investigate the general
direction, lose a fading trail, search locally and eventually resume exploring.
It can follow the wrong human scent. Once its own vision confirms an opponent,
existing pursuit and the creature's surprise hop work as before.

Both existing Senses windows gain a useful live **Olfaction** page. The arena
also has a development scent heatmap and smell-range filters for manual QA.
This feature runs in normal simulation; opening a debugger is not what enables
emission, sensing or search behavior.

## Scent sources and environmental trails

- Emit scent on ground actually occupied or traversed by a configured emitter.
  Movement must leave a continuous trail across crossed tiles, including trainer
  running. Failed movement must not deposit on the attempted destination.
- Deposits remain where they were left after the source moves away. Allow local
  spread and gradual dissipation to a finite negligible/empty state. This is a
  bounded, tunable gameplay approximation of smell.
- Stationary living sources should continue contributing locally at a bounded
  rate. This supports current human trainers and future standing bystanders.
  Do not accumulate unbounded concentration or an ever-growing trail history.
- Simulation time controls emission, propagation and decay. Rendering rate,
  connection count, inspector polling and paused replay cannot change the field.
- Specify and test propagation at solid structures, map edges, open passages
  and water. Walking and vision blockage are not automatically scent rules.
  Scent may be detectable without visual LOS under the chosen propagation rules;
  use explicit terrain behavior, not a hidden straight bearing to an emitter.
- Emission and receptor ability are independent configuration. An emitter can
  lack a nose; a future scentless robot can still have a chemical sensor.

| Source / receptor | Initial contract |
| --- | --- |
| Archer | Generic human scent; ordinary human olfactory range |
| Orc | Generic orc scent; strictly larger olfactory range than human characters |
| Current human trainers | Generic human scent, capable of confusing a searching creature; no trainer AI receptor is required |
| Lancer / Warrior | Same human scent and ordinary human range when admitted later; do not implement their missing art or add them to selection in this slice |
| Future robot | Emission can be disabled independently of sensing; demonstrate with a QA configuration without adding a robot asset |
| Existing shape fixtures | Retain valid, explicitly documented source/receptor settings; do not infer scent from their display color |

Choose and document sensible initial range, emission, decay and sampling values.
Demonstrate the Orc advantage with otherwise equivalent test conditions. Preserve
existing equal memory settings; greater smell reach must not grant a better map.
No unique smell signatures or opponent-specific recognition in this checkpoint.

## Privacy and the olfactory observation contract

The scent field is **shared physical environment**, like terrain. It is not shared
creature knowledge. Each creature samples it independently and owns its own
observations, retained evidence, interpretation and search history.

Permitted information is coarse: recognized scent class, strength, approximate
bearing when supported, and uncertain freshness where the model supports it.
Presence with no usable direction is a valid reading. If freshness cannot be
estimated from permitted evidence, report it as unknown; concentration alone is
not a guaranteed age or a count of emitters.

Do not deliver emitter entity IDs, owner/player IDs, faction, confirmed hostility,
exact source coordinates, source action, velocity, route or private state. An
observation identifier identifies the observation, not the hidden emitter.
Own sampled pose and sampling locations are allowed; they are not source fixes.
Do not turn a coarse direction/range into a fabricated exact target point.

Human scents blend as human scent. Two sources with the same class cannot become
individually distinguishable through colors, separate rows, ordering, labels or
hidden IDs. A trainer/bystander can mislead the searcher. Identifying it requires
other permitted evidence; the sensor must not silently remove non-opponents.

Handle self-scent explicitly. A self-only trail must not trap the creature in
endless investigation. Document the chosen handling and its limitations. Do not
solve this by excluding all human scent from humans, all orc scent from orcs, or
by granting individual recognition of otherwise indistinguishable sources.
Mistakes and temporary false leads are acceptable; permanent self-chasing is not.

Retained readings keep their sample time and identity. A newly sampled old trail
is current evidence of scent, not proof that its source recently stood there.
Neither operation updates a last-seen visual position or confirms an opponent.

## A consistent perception architecture

Refactor the shared responsibilities that are currently tied to vision, while
preserving vision's precision, schedules and reviewed geometry. Organize all
senses around the same readable lifecycle:

**configuration → scheduled measurement → private observation → brain input →
diagnostic projection / recorded evidence**.

Share the lifecycle and naming conventions. Keep vision and olfaction measurement
rules distinct, and keep environmental scent updates separate from the nose that
samples them. The brain owns interpretation and behavior; the renderer displays
system-owned data. Avoid both copied end-to-end pipelines and a large unused
framework for future senses.

Areas to inspect, not a prescribed new file layout:

| Current area | Responsibility to preserve or generalize |
| --- | --- |
| `server/senses.odin`, `server/battle.odin` | Vision-specific receptor storage/binding, sampling orchestration and lifecycle |
| `server/observations/`, `server/perception/` | Data-only brain contracts versus host measurement logic |
| `server/content_senses.odin`, `client/content/sense_catalog.gd`, shared content | Validated capabilities, independent emission/reception and matching content fingerprints |
| `server/ai/search_evidence.odin` and related search modules | Typed sensory evidence, private retention and existing search-state authority |
| `server/brain_workers.odin` | Independent workers with private copied values |
| `server/dev_senses.odin`, `server/dev_ai_debug.odin`, `server/dev_replay.odin` | Bounded live exports, causal traces and recording |
| `client/dev/sense_feed.gd`, `client/dev/senses/`, `client/dev/sense_overlay.gd` | Validated latest readings, per-sense presentation and filters |
| `client/dev/ai/` | Decision inspection and replay readers without live-data substitution |

Every sense needs coherent observer/round binding, capability status, sample/event
identity, original source time, delivery time and precision. Unsupported,
disabled, waiting, sampled-empty, retained and stale must remain distinguishable.
Each receptor can run on its own schedule; combining senses must not refresh an
older sample's clock. A fresh empty smell sample clears current detection.

Both workers consume permitted observations from one defined frozen world phase.
They must never receive the scent field, map, host audit, emitter registry or a
callback that queries them. Adding smell must not turn the current dedicated
threads into shared mutable cognition or give either creature an ordering advantage.

## Search integration and decision ownership

Feed smell into the existing composite search controller. The sensor must not
move a creature, select an opponent or introduce a competing movement controller.

| Evidence / condition | Required behavior |
| --- | --- |
| No useful sensory evidence | Existing extensive exploration and relocation |
| Local scent presence, no useful bearing | Intensive local search can begin around the observer's evidence area |
| Directional scent | Investigation biased toward the coarse cue; no global route or exact hidden target |
| Conflicting or repeated weak evidence | Explicit, bounded arbitration and abandonment; no permanent loop or frame-by-frame direction jitter |
| Trail weakens, vanishes or becomes stale | Private retention ages out, then broader exploration resumes |
| Fresh focused opponent sighting | Existing confirmed acquisition and pursuit take priority |
| Opponent leaves sight | Fixed visual memory and uncertain smell can coexist; scent cannot move or refresh the old visual fix |

Keep evidence provenance when vision/periphery and olfaction disagree. Do not
flatten them into one perfect opponent record. No A*, global pathfinding, future
trajectory knowledge or access to another creature's memory. Smell-only detection
must not set the public target-acquired flag or trigger the exclamation/body hop.

## Debugging surfaces and heatmap honesty

Keep the default six windows. Add olfaction to the two existing Senses windows;
no additional standalone window is needed. Preserve Vision, the owner-requested
**Exploration memory** tab, and independent decision-debugger windows. Older text
forbidding every memory panel is superseded by that specific existing tab.

The Olfaction page shows the selected creature's actual delivered local readings:

- A live heatmap of the permitted sampled areas, detector extent, scent-class
  legend, and clear weak/strong or no-direction readings.
- Readable class, approximate bearing, strength, original age/status and supported
  freshness. Colors distinguish **scent classes**, not individual emitters.
- Unknown/unsampled areas that look different from sampled absence. If the
  observation is sector-based, the display cannot invent a precise tiled trail.
  Label any visual interpolation as an estimate.
- Correct owner, entity, round and sample binding, including identical creatures.
  A paused decision tree must not pause this live view.

The full arena field is a separate **host diagnostic** heatmap for checking where
scent was deposited, spread and faded. Keep it outside the creature-readings page
and clearly label it as privileged world data. It must render the actual field,
not generate a separate illustrative trail or query current emitter positions to
fake old deposits. Allow filtering by scent class and each observer's smell range.

Group these controls under **Senses / Olfaction**, independently of vision fields
and physical colliders. Keep the ground and actors readable with a restrained
heatmap opacity and a legend. Save the new debug on/off/filter settings per
window, like existing search settings; diagnostic toggles never change gameplay.
Preserve existing saved settings when adding the controls. Normal/release runs
must not open inspectors or export private diagnostics.

Do not add logs, stack traces, decision trees or replay controls to the Olfaction
page. Those belong in the existing decision debugger/replay tool. There, explain
which smell observation influenced a search transition, which alternatives were
considered, and the resulting requested/confirmed action.

## Lifecycle, recording and cost

A new round/map/F7 search reset clears the field and both creatures' private
olfactory state. Reset placement itself must not paint a teleport trail. New
emitters begin under the documented spawn/summon rule.

Replacing one creature resets only its receptor and mind. Other creatures keep
their own state. Old environmental deposits remain and fade naturally within
that round; they must not transfer an old creature's private memory to its
replacement. Switching off an emitter stops new deposits, not past decay.

Record the olfactory evidence actually delivered and used, with its original
precision and time. Pause and backward/forward seek must reproduce those readings
and the associated search decision. Historical recordings without smell data
show unavailable. A privileged full-field replay, if provided, needs recorded
field state; otherwise explicitly mark it unavailable. Never read the live field
while showing an old frame. Audience diagnostics use matching delayed evidence
or report unavailable; public player/audience packets must not carry private scent
observations or the host field.

Version changed schemas deliberately, update validators/readers and retain the
existing historical recordings where supported. Bound field storage, samples,
queues, live payloads, histories and update cost for every accepted content profile.
Do not silently truncate valid sensing to fit a display or an undeclared work cap.
Keep rotation, recording-stop status, Git ignores, daily cleanup and pinned evidence.

Measure the existing baseline and the finished candidate with two players, two
AI windows, two Senses windows and recording enabled. Report field-update and
sampling cost, host tick cost, publishing/reading/rendering cost, p50/p95/max
sample-delivery-to-display latency, queue drops, peak memory, bytes per record
and recording duration before the cap. Target p95 delivery-to-display delay at
or below 150 ms for this QA workload without increasing production sensor rates
to disguise display lag. Slow readers, closed windows and disabled diagnostics
must not block simulation or change observations/actions.

## Acceptance evidence

| Case | Required proof |
| --- | --- |
| Persistent trail | A moving source leaves an inspectable trail behind; a stationary observer can still detect it after the source leaves; removal stops emission while old scent fades |
| Deposition and time | Turning, tile crossings, fast trainer movement, blocked steps and frame-rate changes preserve the documented simulation-time behavior; no teleport trail on reset |
| Propagation | Decay/spread, corners, arena limits, water and solid structures follow explicit rules; smell can support investigation when vision lacks a sighting |
| Generic human smell | Two same-class humans and a human trainer yield anonymous category evidence; no source identity, enemy label or individual heatmap color |
| Hidden-world invariance | With identical own state and local scent-field history, change hidden emitter identity, position and private state: observations, memory and actions stay equal until permitted sensory evidence actually differs |
| Orc reach / scentless source | Orc detects a controlled trail outside ordinary human reach; a configured scentless source adds nothing; emission and receptor enablement are independent |
| Self-scent | A self-only case eventually explores again; another same-class source remains detectable without free individual recognition |
| Search / acquisition | Smell drives real intensive search/investigation and eventual abandonment; focused vision interrupts appropriately; smell-only cases never trigger target acquisition or the body hop |
| Independent observers | Same-definition instances retain separate schedules, samples, memory and search histories; serial and dedicated-worker runs agree under the same inputs |
| Rendered diagnostics | Both native Olfaction pages and the host field heatmap show actual data, readable legends and different scopes; expired trails disappear and unknown areas remain unknown |
| Controls and lifecycle | Saved filters survive restart, existing F6 settings survive, F7 clears the round, individual replacement preserves the other mind, stale/disconnected displays and independent closure/reload remain correct |
| Replay / audience | Recorded smell and decisions survive pause/seek/reset without borrowing live data; older files are honest about unavailable smell and delayed viewers see no future evidence |
| Regression / cost | Vision boundary guarantees, exploration memory, trainer running and the corrected creature body hop remain working; finished-tree profiling and bounded-data checks accompany the report |

Provide focused, reproducible QA scenarios for a fading trail, an Orc-only detection
range, an ambiguous human source and a scentless source. Reuse the existing
launcher/fixture pattern without changing the owner's authored arena or saved
preferences for automated checks. Include exact manual launch/filter steps.

Run relevant perception, AI and host suites in normal/debug builds, preserve
`make check_vision_review` guarantees, and run **one final full `make check`** on the
finished tree. Extend the integration harness for the new feature and run it both
headless and graphical. Validate actual rendered heatmaps and search behavior,
not just scene import, data existence or a node's visible flag. Supply captures
and a short recorded scenario that the Team Lead can inspect. Distinguish synthetic
input from physical keyboard/mouse testing; do not claim owner acceptance.

## Scope, code clarity and handback

Deliver the production scent field, anonymous olfactory sensing, search integration,
shared perception refactoring, live/debug heatmaps and supporting replay/QA in
this assignment. Do not add hearing, tactile, pain, combat, blood/food systems,
wind/weather simulation, advanced learning, persistent pet storage, new character
art or a replacement AI scheduler. Future bystanders are an extension point;
use existing trainers or isolated fixtures for ambiguity QA.

Use self-explanatory names and focused operations. Comments are only for necessary
non-obvious code, in plain ELI5 language: one line preferred, three physical lines
maximum. Put deeper explanations in `docs/codebase/`. Refactor hard-to-follow code
instead of adding long comments. Do not perform unrelated cleanup.

Create `docs/06n-olfactory-trails.md` as the implementation record and
`docs/06o-olfaction-coding-agent-report.md` as the owner handback. Update affected
roadmap, workflow, protocol and structure documents to match the finished code.
The report must include:

- Delivered behavior, controls and initial tuning, including terrain, self-scent,
  stationary emission and ambiguity rules.
- Architecture/refactoring decisions and a concise ownership/call-flow map.
- Your changed files, material deviations and remaining limitations.
- Exact test commands, exit codes, measured costs and pinned evidence paths.
- Native captures, a replayable QA scenario and simple manual acceptance steps.
- Recommended follow-ups for Team Lead review, without rewriting this packet.

Leave changes uncommitted and this file unchanged. The owner will return your
report for independent Team Lead review before acceptance.
