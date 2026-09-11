# Dedicated live senses windows

Implemented **2026-09-11** for checkpoint **6B.1.1**. This extends the
[arena vision overlay](06k-arena-sense-overlay.md) with one native Godot senses
window for each creature. Native integration and the full `make check` pass (exit 0).
This is an implementation record, not an independent Team Lead acceptance report.

## Open the six windows

```sh
make dev_vision P1=archer P2=orc
make dev_arena P1=archer P2=orc ARENA=tiny_swords_village
```

With the defaults, both commands open **two playable clients, two AI decision
debuggers and two senses windows**. An audience adds more windows only when
requested. Native titles identify Character P1/P2, its definition and the window's
purpose. Mirror matches still have separate entity/owner bindings.

`SENSE_DEBUG=0` hides the senses windows while retaining the AI debuggers.
`AI_DEBUG=0` disables both kinds by default; `SENSE_DEBUG` inherits its value.
`AI_DEBUG=0 SENSE_DEBUG=1` requests only the two senses companions and still
enables the local feed and recording. Normal gameplay does not launch companions.

Closing either senses window leaves the other windows and battle running. It
stays closed through visual refreshes and code/content relaunches within that
launcher run. Restart the launcher to reopen it. A failed companion launch is
reported explicitly without stopping the playable clients.

## What the senses window shows

Vision opens by default. The left view shows self at the **sampled** pose, with
cyan focused and amber peripheral outlines at 20% opacity. The outlines share
the arena's clipped geometry. Focused markers are numbered dots; coarse cues
are numbered direction/range wedges. The coordinate guides are a reference,
not a battlefield terrain map. Blank space means unknown.

The right table contains only **current detections**. A focused row reports the
permitted public appearance and subject handle with its observed coordinates.
Selecting it shows observed distance, facing and idle/walk state. A peripheral
row says unknown presence, approximate compass direction and near/far band;
it never acquires an exact dot, identity or action from a hidden-world lookup.
Selection follows a still-present subject while its details update. Losing the
reading removes its row and selected details on the next delivered sample.

Self coordinates, sampled facing, profile, source tick, delivery tick and sample
age remain visible. **LIVE**, **STALE**, **DISCONNECTED**, waiting, disabled and
unsupported are distinct. Stale retained geometry is dimmed. There is no world
position interpolation or memory ghost in the Vision tab. There is no event log,
stack trace, decision graph, journal loader, timeline or replay control in this
window. Pausing a decision
debugger does not pause the senses window.

**Olfaction** is now a live page: the delivered nose sample drawn as sixteen
sampled zones per scent class, with strength, freshness and a coarse bearing on
its own delivery clock; see [olfactory trails](06n-olfactory-trails.md).
Hearing, Tactile / terrain and Pain each have a selector with an honest
**Not implemented** message. Projectiles, hazards and combat states remain later
features. Their future adapters must supply typed, permitted observations under
the [combat sensory contract](06j-combat-sensory-system.md).

Arena **F4** still groups senses separately from physical colliders. **F5** toggles
arena cones and **F3** toggles physical colliders. The new window's focused and
peripheral controls affect its spatial drawing only; they do not change sensing.

## Exploration memory

Open **Exploration memory** in either senses window to inspect that creature's
remembered visits. This page updates even when the arena's F6 search overlay is
off. It shows a north-up map, the creature's own recorded position, remembered
regions and a matching table. Click a square or table row for its last occupied
position, visit age and decay time left. Green means fresh, amber means fading,
and a purple dot means an opponent was seen on that visit.

These are places the creature actually occupied and still remembers, not a map
of everything it has ever seen. A marked region does not mean every point inside
it was searched. Blank space may be unvisited or forgotten; it does not prove an
opponent is absent. The initial search profile keeps up to 16 regions of 64 × 64
world units for 60 seconds. The panel reads these limits from each creature's
profile rather than assuming every creature will always have identical memory.

The page uses only the assigned creature's private search history. It adds no
terrain map, hidden opponent position, inferred path, or other creature's
history. Memory is separate from current Vision readings. Ages use simulation
ticks and freeze under an explicit stale/disconnected label when updates stop.
Replacing a creature clears its display; a fresh round or **Reset search [F7]**
clears both. Decision history remains in the AI debugger.

## Boundaries and limits

The shared local feed is now schema 3 (schema 2 added lifecycle identity and
delivery timing; schema 3 adds the nose sample, its own delivery time and the
owner's emitter), still bounded to **32 KiB** and atomically replaced. It does not add a network packet or modify the brain's input,
vision profile, decision schedule, memory, action rules or replay schema.

The writer publishes on newly consumed samples and targets a 50 ms heartbeat;
the senses windows poll every 25 ms. The arena keeps its existing 100 ms poll.
Full-history serialization still shares the writer, so these are scheduling
targets, not hard deadlines. UI measurement keeps at most 256 timing values,
while each Vision page displays one current sample and at most six rows. Its bounded
feed reader retains the shared projection's latest two records. The separate
memory page polls the existing 32 KiB `search.json` every 100 ms, projects only
its owner and updates at most 16 visit rows in place. It does not load journals
or add host publications. Search and senses lifecycle identities must agree
before memory is shown.
The existing host queue and dropped-record counters remain bounded and visible
in the AI debugger. The newest snapshot can skip intervening deliveries when a
reader is slow; it is not an event stream.

Delivery/display latency uses the host's first brain-input enqueue timestamp for
that sample and the senses window's post-draw callback. It includes the worker,
writer queue, serialization, file polling and drawing. A local wall-clock origin
allows comparison between processes; system-clock changes can distort it.
Missing original delivery times remain unavailable. These diagnostic clocks do
not drive simulation. See the [ownership and timing deep dive](codebase/live-senses-inspector.md).

## Verification

```sh
make check_senses_windows
python3 tests/senses_windows_check.py --graphical
make check
```

The new integration check launches the complete setup with two same-definition
creatures and recording. It compares displayed focused facts and delivery time
against real consumed-input journals. Controlled UI fixtures verify loss of
focused detail, anonymous peripheral cues, empty samples and round changes;
their captures are explicitly named `fixture-*`. A stopped copy of a live feed
verifies stale/disconnected labels and recovery. The real launcher then exercises
independent closure, visual refresh, fresh-generation binding, a real round end,
failed companion startup and cleanup. Native window enumeration must find exactly
six owned windows. The graphical path measures delivery/display p50/p95/max and
update gaps, with a **p95 <= 150 ms** requirement for this two-creature setup.

Three additional host tests cover lifecycle filtering, original delivery timing
and the projection's size ceiling. The existing vision boundary/range/lifecycle
regressions remain unchanged. Input in automated checks is synthetic; physical
keyboard/mouse QA belongs to the owner.

Full `make check` passed on **2026-09-11** (exit 0), including 44 host tests in
both normal and debug builds, the unchanged 3 + 3 Team Lead regressions, the
headless senses lifecycle check and the development reload suite. Its output is
`build/verification/live-senses-implementation/full-check.log`.

Native verification on **2026-09-11** passed with exactly six owned windows.
Inspected captures cover both live views, a minimum-size view, peripheral
uncertainty and stale state. Measured after recovery with all six windows and
recording active:

| Measurement | P1 | P2 |
| --- | --- | --- |
| Newly displayed samples | 81 | 84 |
| Delivery-to-display p50 / p95 / max | 29.6 / 95.9 / 96.5 ms | 46.3 / 113.0 / 146.2 ms |
| Update gap p50 / p95 / max | 100.0 / 167.1 / 200.4 ms | 100.0 / 167.3 / 200.9 ms |
| Maximum local read / update work | 0.70 / 0.80 ms | 0.77 / 0.83 ms |

Both meet the 150 ms p95 target on this PC. The writer reported zero drops,
99.0 ms full-history publication work and a 31.3 MiB recording at measurement.
That existing history-writing cost and the 128 MiB replay limit remain growth
constraints. These measurements do not establish a hard deadline or performance
for larger battles. Headless checks verify advancing readings and lifecycle;
they do not report rendered latency because Godot emits no rendered frames there.

Pinned logs and inspected captures are in
`build/verification/live-senses-implementation/`. The native source run is
`build/verification/senses-windows-20260911-054433-284286/`.
Its `performance.json` contains the raw distributions and cost counters;
`six-native-windows.txt` records the owned native windows. Routine test runs
remain eligible for daily log cleanup; only selected evidence is pinned.

The existing debugger/replay integration also passed graphically with both new
senses windows plus its extra delayed-audience window. Timeline selection p95
was 3.21 ms for P1 and 3.15 ms for P2; 15 visible rows were drawn. That run is
`build/verification/ai-debugger-20260911-054935-295115/`, with its result copied to
`live-senses-implementation/debugger-graphical.log`.

### Exploration-memory follow-up — 2026-09-11

`make check_search` passed on the finished tree (exit 0), including the private
projection/panel checks: owner filtering, copied visit data,
bounded entries, decay and tick wrap, stable selection, frozen stale ages and
clearing on replacement or round change. The native search integration passed
with six windows, synthetic map/row clicks, both memory tabs available with F6
off, and displayed visits compared to each creature's private journal. It also
checked fresh memory after the reset button, independent saved F6 settings
through three launches, and replay across reset.

The existing headless senses integration passed its uncertainty, loss,
stale recovery, pause independence, close, reload and lifecycle checks. Inspected
captures show both live memory maps and minimum-size layouts. Selected logs,
displayed data and captures are pinned in
[exploration-memory evidence](../build/verification/exploration-memory-20260911/).
These are targeted follow-up results; the earlier full-suite result belongs to
the original senses-window implementation. Physical mouse/keyboard QA remains
manual.
