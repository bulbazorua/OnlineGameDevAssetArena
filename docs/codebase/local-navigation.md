# Local visual movement

## Why the old movement hit visible walls

The eye in [vision.odin](../../server/perception/vision.odin) originally reported
only creatures and trainers. Its opacity grid hid subjects behind walls, but no
terrain evidence reached the creature. The clipped fan in the developer window
was writer-side display geometry, not brain input.

[search_choose_heading](../../server/ai/search_steering.odin) scored eight
directions from private evidence, recent visits, persistence and seeded
exploration. It had no obstacle shape to check. The action resolver attempted the
move; physics blocked or slid the body; search then abandoned the leg. This was
contact-first movement, not a failure to recognize a building's name.

## Ownership and flow

1. Content bakes ground state, elevation and stairs into an immutable byte per tile.
2. The existing eye samples nearby terrain at its existing cadence and pose.
3. Each agent updates its own short-lived terrain memory.
4. Existing search chooses the preferred movement and optional stopping position.
5. Local steering selects a passage and submits the existing Move, Face or Hold intent.
6. The unchanged resolver owns position, facing, turn timing and collision.
7. Confirmed displacement updates local progress; persistent failure invokes existing search recovery.

The host still submits both brains before collecting either result. Brain requests
contain copied observations and self-condition, never an arena pointer.
Godot still displays authoritative movement; it does not steer creatures.

## Visible terrain, not a hidden navigation map

[terrain.odin](../../server/observations/terrain.odin) defines a fixed 13-by-13
sample centered near the eye. A cell is unknown, clear or solid, with a seen
height and stairs flag. The byte encoding keeps the existing worker input budget
below 1 KiB. The sample carries no arena dimensions.

[The terrain receptor](../../server/perception/terrain.odin) uses the same range,
field of view and exact occlusion queries as the eye. It visits tiles rather than
relying on spaced display rays. A post has its own face and corner tests, including
when its center is hidden by its own opaque cell.

Terrain is authored as uniform square cells. Seeing a patch or face identifies
that cell's ground rule and square footprint; it does not disclose the cells
behind it. This is a game geometry approximation, not image recognition.
Walkability and opacity remain separate: water can be visible but unwalkable,
and an opaque material need not be physically solid.

[Private terrain memory](../../server/ai/navigation_memory.odin) retains seen
cells for three seconds by default, even when a later eye sample faces away.
Unknown samples do not overwrite remembered walls. Visible changes do update
memory. Moving the local window preserves overlapping cells; expired or
out-of-window cells are unknown. Resetting an agent clears its memory and maneuver.

## One controller below intent

[Navigation_Runtime](../../server/ai/navigation_types.odin) belongs to one agent.
Its profile starts identically for every creature. Body size and maximum speed
come from the host's own-body constraints. Future movement profiles can tune
acceleration, braking, comfortable clearance and bout length without another
implementation or shared personal memory.

[The passage tests](../../server/ai/navigation_geometry.odin) sweep the circular
footprint against known tile rectangles, including rounded corners. They also
check the resolver's immediate X-then-Y step and seen height transitions.
Solid intersections are hard rejections, not score penalties that a strong goal
can outweigh. Comfortable clearance is a small separate preference, so a safe
parallel path remains attractive.

[The controller](../../server/ai/navigation.odin) compares eight local directions
using the existing preferred direction, clearance, uncertainty and the current
passing commitment. The preferred direction may be continuous; the other choices
use the game's existing eight facings. Ties use a stable creature-local rule, not
new random draws. A short commitment and remembered passing side prevent
near-equal openings from causing left-right chatter. A newly blocked passage can
interrupt that commitment.

Advance follows the selected passage. Turn uses the existing bounded Face action.
Inspect turns or slows when evidence is missing, or stops when no moving passage
is feasible. Inspection never requests privileged geometry: only the normal eye
schedule can supply another observation. Unknown ground is not marked empty;
cautious movement into it may still encounter an unseen obstacle.

Closing urgency uses actual displacement and perceived swept clearance, with
stopping distance and the eye's sampling interval. It is the geometric equivalent
of an approach signal, not raw pixel motion. Standing still produces no closing
urgency, and turning does not manufacture scene expansion.

The present resolver has no momentum and can stop immediately. Local speed ramps
make ordinary acceleration and braking gradual; a protective stop or an in-place
turn can still stop immediately, matching that actual motor capability. Heavy
inertial bodies and wide moving turns would require a separately agreed physics
change, not a claim that the current resolver simulates them.

## Finite approaches and recovery

An optional Move_Approach identifies a stopping position, arrival distance and
preferred clearance. It limits the look-ahead and braking calculation to the
remaining approach rather than extending a ray through the wall beyond a valid
stop. The behavior still supplies the preferred direction; local steering does
not overwrite search's chosen detour with a direct-to-target command.

Pursuit and last-known-position movement use their existing stopping distances.
The same contract can execute a future cover or interaction approach. Selecting
cover, enabling loot and choosing a route remain outside this controller.

[Feedback](../../server/ai/navigation_feedback.odin) compares the commanded step
with actual displacement along the selected passage. Repeated failed steps or a
four-second window without meaningful displacement trigger existing search's
blocked-heading path. Walk preparation is not counted as failed movement.
Progress is physical movement, not monotonically decreasing distance to the goal,
so legitimate detours can move away from it. Concave traps still need search;
this is not a global route planner.

When an extensive-search leg expires, its next persistence preference uses the
body's actual facing, not the heading that local steering had to bend around a
wall. The old heading otherwise kept pulling creatures back into a courtyard.
The first seeded leg, active legs and evidence-driven goals keep their existing
rules. This feedback adds no random draws and does not replace the search goal.

## Keeping sense work bounded

[The terrain cache](../../server/perception/terrain_cache.odin) belongs to one
host vision receptor. It reuses only terrain evidence when the eye pose, profile,
grid identity, dimensions and geometry revision are unchanged. Subject detection,
sample IDs and delivery clocks still run at the existing eye cadence. The cache
and its build/hit counters never enter a brain request.

The catalog must outlive its receptors. Rebuilding arena rules increments the
geometry revision; callers changing fixture cells must use
`content.arena_refresh_rules`. Rebinding a creature clears its receptor cache.
Different creatures do not share observations or caches.

Moving eyes still sample terrain. A conservative range and field-of-view box
check skips only tiles that cannot contribute a visible point. The original
surface tests make the final decision. Boolean visibility stops at the first
confirmed occluder; the developer display fan still requests the nearest hit.

[Olfaction](../../server/perception/olfaction.odin) classifies most compass
sectors with comparisons instead of an angle calculation. Near a sector edge it
uses the previous calculation so rounding stays unchanged. Clearly out-of-range
cells skip the square root, and body-blind cells skip unused bearing work.
Reach, coverage, strength, freshness, field decay and sampling cadence do not
change. No per-sample allocation or new worker is introduced.

Frozen pre-optimization terrain and nose samplers live in
[terrain_optimization_test.odin](../../server/perception/terrain_optimization_test.odin)
and [olfaction_optimization_test.odin](../../server/perception/olfaction_optimization_test.odin).
They compare delivered observations and audits, including field edges, blind
cells, solid cells, map boundaries and sector ties. Separate tests check cache
invalidation, independent ownership, moving subjects and boolean sight parity.

## Diagnostics and compatibility

No new inspector or feature-coupled UI base was introduced. Existing AI trace nodes
show the preferred movement, selected passage, movement mode, passing side,
commanded speed and urgency. Existing JSON records also carry the optional
before.navigation and after.navigation fields: private terrain cells and their
timestamps, candidate directions, hard rejection reasons, uncertainty, pressure,
intended and actual movement, and recovery counts.

These fields are additive to the current diagnostic records. Older recordings
without them remain older evidence, not reconstructed navigation history.
Existing readers allow extra fields; packet bytes, public movement snapshots,
trace node capacity and record-size limits are unchanged.

Diagnostic record views keep serializable values, not typed pointers. Their
history workspace is reused inside the heap-owned diagnostics state, so the
enlarged creature states do not create a large stack array. The queue still
copies gameplay data by value, and encoded fields remain unchanged.

## Checks and evidence

Run the existing package and integration gates:

```sh
odin test server/perception -out:build/perception_tests
odin test server/ai -out:build/ai_tests
odin test server/simulation -debug -out:build/simulation_tests_debug
make check_session check_ai_debugger
make check
```

For comparable release measurements, run the existing serial benchmarks on the
same machine without other gates running:

```sh
odin test server/perception -o:speed -define:ODIN_TEST_THREADS=1 -out:build/perception_speed_tests
odin test server/simulation -o:speed -define:ODIN_TEST_THREADS=1 -out:build/simulation_speed_tests
```

Before/after logs belong in `sense-optimization/` under the evidence directory
below. These measure the present two-creature simulation and bounded sense
envelopes; they do not establish a population limit or guarantee client frame
pacing on every machine.

[Perception tests](../../server/perception/terrain_test.odin) cover visible narrow
posts, hidden terrain, disabled eyes and independent sight/walkability rules.
[Controller tests](../../server/ai/navigation_test.odin) cover passing commitment,
walls, parallel contact, body-sized openings, uncertainty, finite cover approaches,
stationary rotation, closing urgency, persistent traps, private knowledge, height
changes, repeatability and bounded work.

[The resolver scenario](../../server/simulation/navigation_test.odin) compares a
fixed eastward search leg against contact-first movement using the same real
collision resolver. It checks an early turn, no penetration and completion of a
post-passing maneuver. The existing full simulation tests retain real-map search,
serial/threaded parity and allocator-disabled scenarios.

The enclosed-creature fixture supplies fresh eye samples at the configured
cadence and feeds its turns back into facing. It must never move into the known
enclosure and must eventually hand the blockage to search. The separate
stationary-rotation test still checks that an old, unseen wall expires normally;
stale evidence is not kept alive merely to make the enclosure test pass.

Baseline and candidate execution evidence belongs under
`build/verification/local-navigation-20260912/`. Test source is not itself proof
that a gate has passed; use the recorded exit codes and logs.

This first controller handles static authored terrain. It does not add
creature-to-creature collision, infer hidden moving objects, simulate camera
pixels or replace strategic route discovery.

## Biological inspiration

The separation of goal direction, obstacle pressure and collision necessity is a
game-oriented adaptation of [Bertrand, Lindemann and Egelhaaf (2015)](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1004339).
Competition between passages, persistent turns and an escape fallback are
inspired by [Schoepe et al. (2024)](https://pmc.ncbi.nlm.nih.gov/articles/PMC10821932/).
This implementation uses permitted geometric observations, not either paper's
neural simulation.
