# Completed assignment: live senses windows and vision filters

Repository: `/home/burpazor/Code/Personal/BulbaZorua/OnlineGameDevAssetArena`

Updated **2026-09-11**. Milestone: **6B.1.1 — implementation delivered**.
At the owner's request, the Team Lead temporarily acted as implementer. The
[live-window record](06l-live-senses-windows.md) describes the delivered six-window
setup, verification and remaining limits. Independent review and owner physical
input remain separate from the implementer's automated checks.

The original assignment below is retained as the architectural acceptance
baseline. **Do not restart implementation from this packet.** Use it to review
the delivered feature; obtain a new owner assignment before taking the next
sense or roadmap milestone.

## Roles and authority

You are the **coding agent**. Choose the implementation and any necessary
refactoring, then return a reviewable candidate and evidence to the owner.
The **Team Lead** owns architectural requirements, independent review and
acceptance testing. The **owner** copies this handoff to the coding agent and
returns its report. Keep `docs/delegation.md` Team Lead-owned.

Algorithms, data structures, internal APIs, file layout and presentation technique
are your responsibility. Complete the authorized slice; explain material tradeoffs
and requirement conflicts. This document specifies outcomes and boundaries, not
an implementation recipe. Do not commit unless separately requested.

Read guidance applicable to your identity: Codex reads `AGENTS.md` and must not
access `CLAUDE.md`; Claude reads `CLAUDE.md` and must not access `AGENTS.md`.
Preserve unrelated edits and drafts.

## Read first

- [6B.1 implementation](06g-focused-and-peripheral-vision.md): current vision,
  observations, private memory, action authority and limitations.
- [Team Lead review and re-review](06i-vision-team-lead-review.md): closed R1–R3,
  early-pause coverage, independent proof and remaining limits.
- [Combat sensory system](06j-combat-sensory-system.md): five-sense roadmap and
  the owner's clarified live-monitor expectations.
- [Decision debugger](06d-ai-debugger-harness.md), [QA replay](06e-qa-replay-and-trace-browsing.md)
  and [development workflow](03f-dev-workflow.md): behavior to preserve.
- [Development filters](03e-dev-overlay.md) and [roadmap](plan.md).

Only vision exists today. Hearing, olfaction and tactile/terrain follow at 6B.2–6B.4;
pain activates with real damage at 6C. Projectiles and observed projectile motion
remain later combat work. Inspect live source and existing checks before editing.

## What the owner needs

Provide **one dedicated native Godot senses window per creature**. Each is separate
from the playable client and the existing decision debugger. Two creatures should
have two independently bound senses windows alongside their two decision windows.

The window is a **live sensor monitor for manual QA**. It shows what the creature
currently detects, using a spatial view and a readable list of current values:

| Reading | Expected presentation |
| --- | --- |
| Focused trainer or opponent | Observed position `(x, y)`, visible kind/state and freshness, only when that evidence is available |
| Peripheral contact | Approximate direction sector and range band, with no exact subject marker or identity |
| Projectile, when implemented later | Observed position and supported motion, such as speed `100 world units/s` and direction; unknown motion stays unknown |
| Hearing, when implemented later | Sound type and approximate bearing/range; a direction vector is not an exact emitter position |
| Other future senses | Their current permitted readings, with precision and status visible |

Give the supported readings clear labels, units and spatial correspondence.
Use generic code names and developer titles such as `Character P1 · Senses`.
Follow existing `character` terminology, with creature/agent/sense/perception names
where useful. MoPock is conversational/design shorthand; do not introduce it into
identifiers, modules, filenames, APIs, schemas or diagnostic roles. Update the
legacy branded inspector titles to the generic form while preserving role detection.

## Keep the senses window focused

The senses window must have **no event log, stack trace, decision tree, historical
timeline, memory/interpretation panel or replay/trace-stepping controls**, including
hidden tabs containing them. Those remain available in the decision debugger and
QA replay tool. Do not remove their underlying capture or inspection capability.

Show current detections and status. Lost visual subjects leave this list at the
next delivered sample. Do not display an old memory as a live subject or a ghost
tracking its hidden position. Retained samples keep their original timestamp and
pose; stale or disconnected data must be visibly marked.

Future hearing/pain events may appear briefly as current detections for their
specified sensory lifetime. This is not a growing event history. Future scent can
be currently detected even when the source has left; label its measured freshness.

A freeze/resume control for inspecting the current display is optional. If present,
label the frozen state and keep the simulation running. Pausing or closing the
separate decision debugger must never freeze the senses monitor.

## Knowledge and rendering boundaries

- Render the creature's actual delivered observations. Do not reconstruct its
  knowledge by filtering a complete client snapshot or querying hidden world state.
- Focus may show observed detail. Periphery must remain coarse throughout the
  readout and spatial view. Unknown identity, velocity or action stays unknown.
- No exact speed or future trajectory may come from hidden projectile state.
  Any later motion estimate must use permitted evidence and be labelled as an estimate.
- Show the observer and focused/peripheral cone geometry with range and sample age.
  At displayed subjects, classification and occlusion must agree with production
  sensing. Approximate coverage artwork cannot create additional detections.
- Privileged reference maps, rejected candidates and hidden-state explanations
  stay in the existing host-diagnostics views outside the live senses window.
- Keep raw observations, private memory, interpretation and decisions separate.
  A monitor never runs a second brain, resamples the world or changes an action.
- Preserve per-creature identities and private value inputs, including two
  creatures sharing one definition. Keep both existing dedicated decision workers
  and the current authoritative action/sampling order.

Prepare an understandable place for all five senses. Only Vision has live data in
this slice; other selectors must say **Not implemented**. Do not invent no-sound,
no-scent, safe-ground or no-pain readings, or scaffold unused sensor implementations.

## Vision in the development Filters surface

Preserve the implemented **Senses** group with vision-cone visibility, distinct focused/peripheral
fields and independent observer selection. These are presentation controls,
independent of the current collider controls. Preserve collider filtering, camera
input, window-local settings and the normal game UI.

The arena overlay and senses window must refer to the same observer, profile,
sampled pose, range and occlusion. Make sample age clear when the displayed game
world is newer than the sensor data. In an audience window, use evidence matching
its delayed frame or show it as unavailable; never overlay future live knowledge.
Private sensory data must not enter ordinary player/audience packets.

The senses spatial view should show vision by default when a valid sample exists.
Document the arena filter defaults and how the owner can toggle each creature.
Filters must never enable/disable a production sense, change its sampling schedule,
or alter physics or decisions.

## Launch, lifecycle and performance

These existing development flows should open the senses windows after this slice:

```sh
make dev_vision P1=archer P2=orc
make dev_arena P1=archer P2=orc ARENA=tiny_swords_village
```

Allow explicit selection of optional diagnostic windows; document the final launch
controls. Preserve development-only gating, independent readiness and closure,
reload/relaunch generation binding, failed-launch reporting and cleanup. A window
closed by the owner stays closed through that session's reloads. Normal/release
runs expose neither these windows nor private diagnostic exports.

Live monitoring follows sensor deliveries, regardless of which decision is being
inspected elsewhere. Keep source time, delivery time and display freshness distinct.
With the current 10 Hz profile, target **p95 delivery-to-display delay <= 150 ms**
in the two-creature QA workload. This is an acceptance target, not an existing
performance claim. Do not make the sensor run faster just to satisfy a display test.

Measure p50/p95/max delivery/display delay, update gaps, writer cost, queue drops,
recording size and existing inspector browsing latency with both players, both
decision windows, both senses windows and recording active. Preserve responsive
browsing and bounded memory/queues/history. Slow readers, filters and closing
windows must not block the simulation or change its results.

The current telemetry has an approximately 100-second recording horizon and
roughly 100 ms publishing cost per 250 ms cycle. Address the live display's needs
without duplicating full decision-tree storage for each additional window. Keep
Git ignores, daily pruning, pinned recordings and explicit truncation/stop status.

Recorded sensory evidence must remain inspectable in the existing QA replay tool
at its original precision and time. Old recordings missing that evidence show it
as unavailable. The dedicated senses window itself stays a live monitor.

## Acceptance and verification

| Scenario | Required proof |
| --- | --- |
| Native windows | Two senses windows coexist with two decision windows and both clients; each identifies the correct creature, including same-definition instances |
| Focus / periphery | Focused positions match delivered data; peripheral cues never display exact hidden positions, identity or detailed actions |
| Loss / cover | Subjects disappear from current readings when a fresh sample loses sight; any last-seen memory is inspected separately in the decision debugger |
| Geometry / filters | Default range, all facings, water/cover, corrected wall edges/corners and supported range extremes agree with production; filter changes have no gameplay effect |
| Live independence | Readings advance while the decision debugger is paused or closed; stale/disconnected and any optional frozen display are unmistakable |
| Window purpose | The senses window contains current readings and their spatial view, with no trace/log/history/memory/interpretation UI |
| Lifecycle | Independent close, restart/rebind, round reset, visual reload, code/content relaunch and cleanup preserve ownership; no previous occupant's evidence appears |
| Isolation | Diagnostics on/off and slow-reader runs preserve production observations and actions; no hidden world lookup reaches a brain or the current-readings view |
| Replay / audience | Existing replay retains actual consumed evidence and age; audience overlays never borrow a later live frame |
| Responsiveness | Measured live latency meets the target with the complete dev setup; readable labels and bounded lists avoid overlap and scrolling lag |
| Future senses | Unsupported statuses are honest; no fabricated hearing, scent, terrain, pain or projectile data |

Preserve `make check_vision_review` with unchanged guarantees. Run the relevant
suites, full `make check`, and headless plus graphical integration against the
finished tree. Extend the verification harness to cover the new acceptance cases;
leave evidence and commands the Team Lead can rerun. Distinguish physical mouse/
keyboard coverage from synthetic input. Include captures of the actual native
windows and their current readings, not just a successful scene import.

## Scope and report

Implement the live windows, vision-filter integration and the bounded diagnostic
support/refactoring necessary to make them correct and responsive. Do not add the
remaining senses, combat, pursuit, anatomy, moods, learning, persistent pet storage,
a new decision scheduler or deterministic re-simulation in this checkpoint.

Apply the owner's hard code-clarity rules: clear names and traceable control flow;
comments only where necessary, plain ELI5 language, one line preferred and three
lines maximum. Put deep explanations in `docs/codebase/` and refactor confusing
code into focused operations instead of explaining it with long comments.

Return an owner report describing behavior, architectural boundaries, meaningful
deviations, test commands and exit codes, native captures, measured costs, manual
QA steps and remaining limitations. Update the implementation/workflow/roadmap
documents for the finished slice. Keep this handoff unchanged, changes uncommitted,
and final acceptance pending Team Lead review and owner feedback.
