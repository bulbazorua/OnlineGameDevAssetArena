# Composite naturalistic opponent search

Status: implemented MVP; verification results are recorded below. Search is now the normal battle controller. The stationary Observe controller remains an explicit vision regression fixture, selected with `tools/dev_session.py --observe-only` or the development host's `--dev-observe-only` flag.

## Play and inspect

```sh
make dev_vision P1=archer P2=orc
make dev_arena P1=archer P2=orc ARENA=tiny_swords_village SEED=42
```

The first command puts opponents close enough for quick vision and acquisition QA. The normal maps start them far apart: discovery can take time and is not guaranteed by a navigation service.

To repeat a search manually, open **F4 → Reset search [F7]**, or press **F7** in either player window. The host starts a fresh search round in the current arena, clears both creatures' memories, visits, action state and target markers, and moves their trainers nearby so the player cameras follow. Character choices, open windows, logs and saved F6 settings are retained. The normal 1.5-second summon pause gives you a moment before movement resumes.

Reset positions use connected, walkable ground with valid footprints. Creatures start at least 1.5 times the larger vision range plus two footprint radii apart; the other trainer is also outside sight range. In the starter vision QA fixture, positions are `(48, 48)` and `(720, 400)`: about 759 units apart versus 256-unit vision. This is a host-only spawn check; creatures receive no map, route or opponent location. If connected space is too small for a safe spread, the button reports that and leaves the match untouched. Reset is available only to players on a local debug host running the search controller.

Press **F6**, or open **F4 → Search / foraging [F6]**, in a player window. Search diagnostics start **off**. The switch saves immediately for that player window, including an explicit off value, and restores on the next launch. P1 and P2 settings are independent. The corresponding AI inspector's **Search** tab uses the same setting. Saved preferences live in Godot's `user://dev/search-p1.cfg` and `search-p2.cfg`, outside the repository and outside temporary launcher generations. Automated checks override the preferences directory to avoid changing the owner's settings.

There are still six default windows: two game clients, two AI inspectors, and two senses windows. Each senses window has current receptor readings and a separate **Exploration memory** tab showing only its own creature's remembered visits. The memory tab works independently of F6: click a region or table row to inspect its age, strength, last occupied position and whether an opponent was seen on that visit. Fresh regions are green, fading ones amber, and encounter dots purple. Blank areas are unvisited or forgotten, not confirmed empty. Search decisions and their history remain in the search display and AI inspector. Search diagnostics require development telemetry, normally enabled by `AI_DEBUG=1`. Audience clients cannot read this live private feed. Normal clients and release builds do not enable these debug overlays.

In the arena, the overlay draws each creature's recent visits, chosen heading, blocked directions, a remembered target position when available, and the expanding local search area. These are beliefs and proposed movement, not a route or an omniscient map. The scrollable **Search P1 / Search P2** panel shows:

- Current state, transition reason, evidence type, confidence and original age.
- Visible or remembered target, cue bearing, investigation center and radius.
- Chosen heading, leg deadline, relocation and abandonment counters.
- All eight direction scores: continuity, random exploration, evidence, locality, visit penalty and blocked-movement penalty. Green marks the chosen direction. Scores retain the tick at which they were evaluated.
- Private visit positions, ages, strengths, memory limits and retention.
- Requested action and confirmed host result, including blocked movement.
- Repeated-cue cooldown and the creature's private random-stream state.

The AI inspector retains the branching trace and a frozen Search tab for the selected decision. The arena display continues live while a trace is paused. Feed failure is labelled stale; changing a display never changes the creature's decisions.

## Behavior and information boundaries

```text
private observations + own position/action feedback + private memory
    → choose a search state
    → score eight local headings when needed
    → commit one movement leg
    → request an action
    → host enforces movement and returns the actual result
```

Each runtime creature owns its search profile, bounded visit history, visual memory, evidence, random generator, blocked-direction memory and search state. Workers receive these by value. They cannot query the map, opponent state, another creature's memory, developer audit or renderer. Both workers consume observations from the same frozen world phase before the host resolves either action. Their random streams derive from the scenario seed, round and entity identity, so identical definitions can behave differently while a repeated scenario remains reproducible.

The current arena has two opposing creatures. A focused `Creature` sighting can become a target; a `Trainer` sighting cannot. Future teams need a perception-safe relationship contract before this rule expands beyond one opponent. An anonymous peripheral cue remains anonymous and carries no coordinates. The brain's 0.45 initial cue confidence is an authored interpretation weight, not an additional receptor measurement.

| State | Evidence | Behavior |
| --- | --- | --- |
| Extensive search | No useful opponent evidence | Correlated random walk; hold a heading across ticks and prefer locally less-recently-visited regions. |
| Investigate (scent) | A remembered directional scent reading, after own-trail zones are explained away | Bias movement toward the coarse smelled bearing with a weaker pull than a visual cue; see [olfactory trails](06n-olfactory-trails.md). |
| Intensive search (scent) | Scent present around the nose with no usable bearing | Local search around the sampling position; fading scent hands over to the local-search budget. |
| Long relocation | Extensive search, sometimes more likely near previously visited regions | Pick a new private random heading and attempt a longer leg. This is a bounded mixture of run lengths, not a measured Lévy distribution. |
| Investigate | Current or briefly remembered directional cue | Bias movement toward the coarse bearing; do not invent a target position. |
| Last known position | A disappeared focused opponent, remembered for three seconds | Approach the fixed position from the last actual sighting. |
| Intensive search | Reached the remembered position, expired directional cue, or a remaining local hypothesis | Shorter runs and more turns, with a growing area around the evidence center. |
| Pursue | Current focused opponent | Move toward its sampled position; stop at the observation distance and face it. Combat is not implemented by this change. |

Fresh focused evidence can interrupt any state. Losing it never moves the remembered opponent using hidden world coordinates. A local hypothesis expires; recently visited ground is not permanently empty. The visit penalty is a preference, not a ban, and records only ground the creature itself visited.

Repeated weak cues and smells share one investigation budget. Without acquiring an opponent, eight seconds of investigation ends in abandonment and a fifteen-second weak-evidence cooldown. This prevents repeatedly seeing an anonymous trainer cue from trapping a creature forever. Focused opponent sightings always override this cooldown. A relocation can change the broad heading to break repeated perimeter circuits.

Walking remains host-authoritative at 64 world units/second with existing first-step preparation. The old 128-unit spawn leash is removed for searching. Physical terrain and arena edges remain enforced. A blocked movement result discourages the attempted local direction temporarily; the brain receives no tile lookup, obstacle map, A*, waypoint graph, or shortest route. It can take inefficient routes, revisit places or fail to find an opponent within a particular time limit.

## Equal initial memory, individual ownership

Both creatures receive the same default profile, stored separately in each agent:

| Setting | Initial value |
| --- | --- |
| Recent visit capacity | 16 regions |
| Region size | 64 world units |
| Visit retention | 60 seconds, linear decay |
| Focused position retention | 3 seconds from the original sighting |
| Peripheral bearing retention | 0.5 seconds from the original cue |
| Local evidence / investigation budget | 8 seconds |
| Blocked-direction retention | 3 seconds, cleared sooner after leaving that local area |
| Extensive / intensive / relocation leg | 1.6 / 0.6 / 5 seconds |
| Intensive radius | 48 to 144 world units |
| Last-position arrival / pursuit stopping distance | 24 / 40 world units |

Memory accuracy is currently the precision already allowed by vision. There is no learned encounter-location preference, learned terrain value, opponent habit model, mood modifier or cross-round learning yet. Replacing one runtime creature resets only that creature. A new round resets both. Persistent player-owned learning needs a separate individual identity/storage contract; it must not attach knowledge to a reused player slot.

## Target-found pixel marker

A newly focused opponent produces a one-second exclamation bubble above the observing creature. Reacquisition after a meaningful sight gap can produce another bubble; repeatedly reading the same sample does not retrigger it. Cues, trainers and guesses do not produce an acquisition.

The host publishes only the alert's active flag and acquisition tick. Clients, delayed audiences and replay use those presentation fields. They do not recompute acquisition from global positions or read private debug files to display the marker.

The default art is DustDFG's **Pixel Art Emotes**, licensed CC0, with the original license and [source record](../client/assets/pixel_art_emotes/SOURCE.md). Change **`client/presentation/target_acquired.tres`** to replace the texture or atlas region. The renderer exposes marker scale and head gap separately. AI and protocol code do not depend on the image.

## Telemetry and replay

Protocol **10** appends two five-byte alert records to active session/world packets (148 / 131 bytes). Restart the host and clients together. Replay accepts historical protocol-9 recordings through an explicit decoder; old files do not acquire invented alerts.

Trace and replay envelope **3** record private search state. Existing schema-1 wander and schema-2 vision readers remain available. The trace history retains 80 recent records per creature, with a 48 KiB per-record ceiling and the existing 4 MiB snapshot reader cap. The latest-only `search.json` has a separate 32 KiB limit and follows the live development publication cadence. It contains own beliefs and confirmed actions, not host candidate audits. `senses.json` remains unchanged.

Journals still rotate at 8 MiB with three retained old segments. Replay still has a 128 MiB cap and reports when recording stops. Search increases record size, so long searches can outlast a recording; use the nearby QA arena for short manual reproduction. World frames, acquisition timing and stored decisions are replayed; this feature does not promise portable deterministic simulation reruns across platforms or executable versions. Existing daily cleanup and ignored build/log directories remain in effect.

## Verification and manual acceptance

Automated coverage includes privacy under hidden-world changes, private histories, bounded decay and tick wrap, stable headings, relocation, blocked feedback, weak-cue abandonment, focused-only acquisition, dedicated-worker/serial equivalence, trace loss, individual replacement and round reset. Deterministic long simulations also exercise searching beyond the previous leash and encountering opponents on all four shipped maps.

`make check_search` checks the private exploration-memory projection, decay, tick wrap, selection and lifecycle clearing, then launches the real host and six roles. The integration validates public acquisitions against delivered focused evidence, opens both memory tabs while F6 is off, compares their displayed visits to each owner's recorded private state, toggles F6 through synthetic input, clicks the reset button, checks fresh memories and separated spawns, restarts three times to check saved on/off values, and checks recorded alert rendering and seeks across the reset round. Use `python3 tests/search_check.py --graphical` for native-window and screenshot evidence. The full existing suite still includes the stationary vision regressions through the explicit Observe QA controller.

Initial search MVP verified on 2026-09-11:

| Check | Result |
| --- | --- |
| Full `make check` | Passed, exit 0. |
| AI / host suites | 13 AI tests; 48 host tests, including private search and dedicated-worker equivalence. Host suites passed in normal and debug builds. |
| Final replacement lifecycle | Passed with an active marker injected before replacement: only the replaced creature's memory and marker clear. |
| Final graphical search harness | Passed: six native windows, rendered arena/Search-tab captures, focused-evidence acquisition, three launches and independent saved toggles. |
| Alert protocol and replay | Passed: distinct alert/tick fields, rejection of malformed/future/expired alerts, historical protocol-9 recording compatibility, backward/forward marker seeks. |
| Trace record bound | Fully populated search histories and scores produced a 37,034-byte record under the 49,152-byte ceiling; oversize rejection passed. |

The final targeted checks cover the display freshness, marker lifecycle and wire checks completed during the broader suite. Logs and inspected captures are pinned under [the review evidence directory](../build/verification/opponent-search-20260911-064622/). The graphical harness used Archer versus Archer to exercise different individual behavior with equal definitions; the manual launcher accepts Archer versus Orc as usual.

With seed 42, the deterministic simulations first acquired an opponent at these ticks; these are scenario results, not search-time guarantees:

| Map | Creature 1 | Creature 2 |
| --- | ---: | ---: |
| Meadow crossing | 1,729 | 1,729 |
| Sandbar | 2,047 | 2,047 |
| Stone garden | 7,117 | 7,117 |
| Tiny Swords village | 6,043 | 6,121 |
| Nearby vision QA | 97 | 133 |

The **reset-button follow-up** passed 52 host tests in both normal and debug builds, the content/connection/movement/audience-delay checks, and the physical-collider/sense-overlay checks. The final graphical search harness clicked the real button, confirmed both clients changed round and resumed exploration, verified six windows remained open, preserved saved F6 settings through restart, and replayed the reset boundary. It also asserts that the new round immediately removes old search beliefs from the live display. Inspected screenshots and logs are pinned in [reset review evidence](../build/verification/search-reset-20260911-070629/). These were targeted follow-up checks; the full-suite result above belongs to the initial search MVP.

Physical keyboard and mouse acceptance remains a manual check: launch `make dev_vision`, see each creature independently acquire the other, press F6, inspect both search panels and the AI Search tabs, restart, and confirm your settings return. In each senses window, select **Exploration memory**, click a remembered region, then press **F7** in a player window and watch both histories clear and begin growing separately. The Vision tab continues to show only current readings.

## Later roadmap

1. Olfaction is implemented in [6B.2](06n-olfactory-trails.md): presence-only scent feeds intensive search and a smelled bearing feeds investigation without becoming a position. Add hearing, tactile/terrain and pain observations through their own sensory contracts and live panels.
2. Add individual encounter outcomes and encounter-location memory, learned only from that creature's observations.
3. Add learned terrain preferences and opponent behavior hypotheses, including mistaken beliefs and forgetting.
4. Vary capacities, retention, spatial precision and learning rates per creature, without altering the privacy boundary.
5. Add personality/species exploration preferences and mood-dependent strategy evaluation above the sensory layer.

Better memory and experience must improve choices from private evidence. They must never unlock hidden opponent coordinates.
