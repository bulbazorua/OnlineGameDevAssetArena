# Delegation: shared dev arena overview and visible scent trails

Status: **READY FOR CODING AGENT. NOT IMPLEMENTED OR ACCEPTED.**

The server refactor and its R1 correction are complete. Keep their source intact.
Historical packet: [server refactor R1](server-refactor-r1-delegation.md).
Acceptance: [independent R1 review](server-refactor-r1-team-lead-review.md).

## 1. Assignment and working arrangement

Add an arena-scale scent-trail view to the existing senses inspector. Extract the
common dev UI parts so Vision, Olfaction, and Exploration memory feel like views
of the same tool, not three unrelated interfaces.

This explicitly includes the local Vision and Olfaction radars: both must use
one shared radar UI component, not merely matching colors or copied helpers.
The root `AGENTS.md` now makes consistent, reusable dev UI a permanent rule.

For this assignment and future dev UI work, check for an existing component
that displays similar data or provides a similar visual structure before
creating a new widget. Reuse its presentation base, not its feature-specific
data ownership or behavior. If the existing widget is tightly coupled, extract
the small common UI base first; do not make the new feature depend on the old
feature's internals.

The coding agent implements this packet. The Team Lead independently reviews
the changes and verification before acceptance. Hand back through the owner;
do not start another agent or a follow-on refactor.

This is a developer-UI feature and a bounded client-side cleanup, not new
olfaction mechanics, shared creature knowledge, or another server refactor.

Follow the root `AGENTS.md`. Do not access `CLAUDE.md`. Preserve unrelated dirty
work. Do not stage, commit, reset, or revert existing changes.

## 2. Source-grounded diagnosis

The Team Lead inspected these current client responsibilities:

| Existing code | What it actually does | Consequence for this assignment |
| --- | --- | --- |
| `client/dev/scent_feed.gd`: `read_snapshot`, `validate`, `level`, `age_seconds` | Reads the bounded, identity-checked host publication, including cell levels and ages for Human and Orc scent. | The trail data already exists. Reuse this reader, not a new network message or simulated trail history. |
| `client/dev/scent_overlay.gd`: `_matches_world`, `_repaint`, `_draw_ranges` | F8 draws the privileged field under actors, caches its cell image, and labels sampled nose reach separately. | Share the field-to-image presentation where useful instead of creating a second interpretation of the same cells. Preserve F8 behavior and settings. |
| `client/dev/senses/senses_window.gd`: `_build_spatial`, `_build_readings`, `_build_olfaction` | Builds parallel vision/nose layouts, controls, tables, status text, and selection plumbing. | Extract the repeated page structure. Do not add a third large construction branch here. |
| `client/dev/senses/exploration_memory_map.gd`: `_world_bounds`, `_draw`, `_gui_input` | Fits the view around self and remembered regions; owns its own compass, grid, scale, and hit testing. | It is not currently a fixed arena overview. A common arena frame must stop the scale changing just because visits appear or disappear. |
| `client/dev/senses/exploration_memory_panel.gd`: `update_source`, `_refresh_status`, `_set_memory` | Owns the search feed, lifecycle matching, frozen stale ages, and map/list selection. | Keep this domain ownership while replacing reusable presentation parts. |
| `client/dev/senses/exploration_memory.gd`: `matches`, `project` | Projects only the selected creature's remembered visits, excluding target truth. | Do not expand the projection to obtain map markers or scent information. |
| `client/dev/senses/vision_sensor_view.gd` and `olfaction_sensor_view.gd` | Draw local sensor views with different geometry but repeated framing. Nose coverage distinguishes measured, partial, and unknown zones. | Extract one shared radar component for both real consumers. Keep their different evidence meanings in separate drawing layers. |
| `client/content/arena_catalog.gd`: `ArenaDefinition` | Supplies map identity, dimensions, tile size, and coordinate conversion. | Pass the required arena geometry to the view; do not make it depend on the gameplay arena node or entire game state. |

The missing feature is a convenient arena-scale view in the inspector, not
missing scent simulation. Existing class colors already agree between the nose
readings and F8; preserve them.

## 3. User-visible result

Within the existing senses window:

1. Vision, Olfaction, and Exploration memory use the same arena-overview frame.
2. Olfaction makes the real trailing scent visible across the arena.
3. Titles, source labels, freshness/status placement, filters, selection styling,
   legends, and details placement follow one layout.
4. Existing local vision and nose views remain available through a consistently
   placed, clearly named view control. Do not force a small nose sample to become
   unreadable just because the full arena is large.
5. Unimplemented senses remain honestly unimplemented. Do not invent readings,
   add another inspector window, or build placeholder layer implementations.

Use the current dev UI visual language. This is consistency work, not a new
theme or typography redesign.

### Shared arena frame

Use a north-up frame with a stable world origin and aspect ratio. Full-arena
bounds come from the matching catalog definition, not the currently visible
observations, scent cells, or memory visits.

Use the same canvas footprint and framing behavior across the three pages.
At the same window size, the same world position must land at the same overview
position, regardless of which page is selected. Resizing must preserve this
relationship and keep labels, legends, and detail controls readable.

Start with an arena outline and neutral coordinate grid. In private views,
label that outline as developer reference, not remembered terrain. Do not add
hidden walls, unobserved bodies, or an omniscient terrain underlay to private
memory or sensor layers.

Keep navigation small. Full-arena fit is the required default. If zoom/pan or
an explicit close fit is needed for readability, implement it once, visibly
label the mode, and retain the overview camera across tabs. Do not add separate
camera controls or automatic refitting rules to each sense.

### Shared local radar component

Refactor the existing Vision and Olfaction local views onto the same radar
component. It owns the shared background, padding, plot layout, compass,
range-guide presentation, and consistent legend/selection styling. Both actual
radar views must consume it; a new unused widget or a shared palette beside two
independent radar frames does not satisfy this requirement.

Keep the actual sensor layers separate. Vision owns its focused geometry,
observed markers, and approximate peripheral sectors. Olfaction owns its
measured/partial/unknown coverage, body blind disc, class-strength wedges, and
coarse bearings. Reuse small drawing primitives when their meanings really
match, but do not force different sensor data into one misleading model.

Use the same layout and coordinate conventions while respecting each sample's
actual range and direction encoding. Vision's observer-relative sectors must
not accidentally rotate the nose's world-direction zones. Legends must fit at
the supported sizes, including when a hidden page has not been laid out yet.

The arena overview and the local radar are distinct reusable controls: one
frames the whole arena, the other frames a sensor's local reach. Do not combine
them into a giant widget that polls feeds or branches on every sense.

### Scent trails

The arena scent view displays the validated host field from `scent.json).
It must visibly say **Host scent field / developer-only world data**. It is not
what the selected creature knows.

- Render published occupied cells, including the wake behind moving emitters.
- Keep Human and Orc class colors and filters consistent with the existing UI.
- Color means scent class, never player identity. Two emitters of the same class
  cannot be separated into personal trails from this publication.
- Use a stable level scale. Do not normalize every frame to its current maximum
  and make a faint field appear strong.
- Make strength and age inspectable for a selected or hovered cell, separately
  for each class present there. Explain the units and quantization.
- Confirm the existing age encoding before labeling it: the reviewed publisher
  encodes whole seconds since the newest deposit, capped at 255. A capped value
  must not be presented as an exact uncapped age.
- Let the published field determine decay and clearing. Do not draw a polyline
  through actor positions, interpolate invented deposits, run a second decay
  simulation, or accumulate an unbounded client-side trail.
- A zero quantized cell means no published level, not proof of physically exact
  zero concentration or that a creature measured empty ground.
- A self/nose marker, if shown, comes from a matching delivered sample and is
  labeled with that sample's timing. It is not an emitter-identity oracle.

Preserve the current nose detail, class readings, uncertainty, coverage, and
selection behavior. Keep nose-sample status separate from host-field status:
a fresh field never makes an old nose sample look live.

### Vision and memory layers

The Vision overview uses only the delivered sample and existing sight geometry.
Focused observations may show their observed positions. Peripheral cues remain
approximate sectors/bands; never turn them into exact target dots. Anchor the
layer to the sampled pose, not a more recent hidden actor position.

The Memory overview uses only the existing projected private visits and self
position. Preserve region numbers, age/strength, encounter markers, and linked
map/list selection. Blank means unvisited or forgotten, not confirmed empty.
Region size and field-cell size are different concepts even though both use
the same world-to-view transform.

## 4. Ownership and proposed structure

Use composition and a small API. These are responsibility boundaries, not a
requirement to create one file for every row.

| Owner | Responsibility | Must not own |
| --- | --- | --- |
| Shared arena control, for example `client/dev/ui/arena_overview.gd` | Bounds, transforms, clipping, frame/grid/compass, shared navigation, pointer-to-world conversion, and consistent frame chrome. | File polling, owner lookup, scent decoding, memory projection, or sense-specific truth. |
| Shared radar control, for example `client/dev/ui/sensor_radar.gd` | Common local plot layout, background, compass, range-guide presentation, and styling used by both Vision and Olfaction. | Sensor sampling, coverage interpretation, bearing inference, or a sense-name switch containing all drawing logic. |
| Shared sense-page layout, near `client/dev/senses/` | Common title/status/filter/view/list/details arrangement and reusable selection presentation. | All sense logic in a large mode switch or a universal mutable context. |
| Vision, olfaction, and memory adapters | Prepare their own display data, legends, uncertainty, and selection meaning. | Another copy of the arena camera or common page layout. |
| Existing validated feeds and page controllers | Polling cadence, run/content/world matching, lifecycle, and source-specific freshness. | Drawing or changing authoritative data. |
| Shared scent-field presentation, only if extracted | Stable class palette and cell-image construction used by F8 and the minimap. | Feed ownership, networking, decay, or creature inference. |
| `senses_window.gd` | Window binding, page wiring, polling coordination, selected tab, and existing development status output. | New per-sense drawing algorithms or duplicated page construction. |

Dependency direction: the window composes domain pages; domain pages use shared
controls and their own data projections. The shared arena control never imports
a specific sense or reaches back into the window.

The same boundary applies to the shared radar and page layout. Shared controls
receive narrow display inputs and emit interaction signals. Each feature keeps
its own data, state, validation, polling, interpretation, and unique details in
its adapter or controller. Reusing a UI base must not require features to read
or modify each other's state.

Expose only the operations consumers need. Use clear names, focused functions,
and GDScript's existing internal-helper conventions. No global event bus, plugin
registry, generic dashboard schema, deep inheritance tree, or all-purpose
`utils` file.

Code comments must be simple and at most three physical lines. Explain deeper
ownership and flow in `docs/codebase/dev-arena-overview.md`, not comment essays.

## 5. Lifecycle, privacy, and runtime constraints

Keep existing debug/session binding and release restrictions. Do not expose the
host field in ordinary gameplay, audience rendering, client requests, or AI input.

Match run, content fingerprint, active round, map, dimensions, and tile size
before combining data with arena geometry. For private markers also match the
selected owner and current entity. Never fall back to another owner's record.

Handle missing files, malformed snapshots, publication stalls, inactive worlds,
round/map changes, and creature replacement explicitly. Retained last-good data
must say STALE or DISCONNECTED and never be presented as a live trail for a new
round. Clear obsolete selections and private markers on identity changes.
Replacing a creature does not itself authorize erasing the shared field; show
what the host publishes for the current world.

Keep private memory ages frozen when its source is stale. Do not use the scent
publication clock to age memory or validate vision. Each source keeps its own
clock even when its status badge uses the same UI component.

Polling and image work must remain bounded. Reuse the existing reader limits,
throttle field reads rather than reading at every draw, and rebuild field images
only when their publication or display inputs change. Avoid one reader per
layer, per-cell UI nodes, repeated full-grid work on idle frames, and large
decoded fields in periodic status JSON. New diagnostic counters should be small.

Keep both inspector instances independent. Switching tabs or changing minimap
filters must not toggle F8, rewrite its saved options, modify another window,
or change the server. Replay must never borrow the current live scent field
for a recorded frame.

## 6. Scope and staged implementation

Before editing, confirm the actual current callers, fixtures, and launch paths.
Identify existing components with similar presentation, and explain which base
will be reused or extracted. A new separate widget needs a concrete reason why
the existing presentation cannot serve it without inappropriate coupling.
Record a pre-edit source snapshot/manifests that preserve the working tree,
including existing uncommitted changes; HEAD alone is not the baseline.

Work in these bounded stages:

1. Define the shared frame and minimal page/layer contracts. Migrate Memory to
   prove the common arena transform while preserving its private projection,
   selection, lifecycle, and stale-age behavior.
2. Add the Olfaction arena field using the existing validated publication.
   Reuse field presentation with F8 if duplication would otherwise be introduced.
3. Adopt the same frame and page structure for Vision and Olfaction. Refactor
   both local sensor views onto the shared radar component, preserving their
   sense-specific geometry and keeping the three data meanings separate.
4. Add focused verification, run the existing affected gates, and write the
   ownership/usage document and handback.

Expected source scope is `client/dev/`, focused UI tests, and documentation.
Small Makefile changes are allowed only to add normal discovery of new tests.
Read catalog definitions as inputs; do not change content or catalog semantics.

No server source, wire protocol, publication schema, AI/perception algorithm,
scent tuning, memory configuration, new replay format, or unrelated asset/runtime
refactor is authorized. Stop and explain if a genuine blocker requires one.
Do not weaken feed validation or existing tests to make the UI migration pass.

## 7. Verification required for handback

Baseline and candidate evidence must be distinguished. Save commands, tool
versions, exits, source identity, logs, and rendered captures under a fresh
`build/verification/dev-arena-overview-<timestamp>/` with `.keep-logs`.

### Focused checks to add or extend

- Verify world/view coordinate round trips, rectangular arenas, resize, clipping,
  edge cells, and consistent placement across all three overview consumers.
- Exercise both real consumers of the shared radar. Cover its common plot,
  compass and legend layout, different sensor ranges, vision-relative versus
  nose-world directions, selection styling, and hidden-page sizing.
- Compare a known field fixture's rendered cell positions and class intensities
  with independently expected values. Do not only compare two counters produced
  by the same new drawing code.
- Cover empty fields, both classes overlapping, individual filters, capped ages,
  invalid dimensions/tile size, stale/missing publications, and round/map changes.
- Preserve private memory projection assertions, bounded visits, tick wrap,
  no source mutation, selection, frozen stale ages, and lifecycle clearing in
  `tests/exploration_memory_check.gd`.
- Prove that privileged field data cannot add private readings, remembered
  regions, exact peripheral targets, or scent-source identities.
- Preserve zero/partial/full nose-coverage rendering. An unmeasured zone must
  never become a sampled-empty fill after moving common UI code.
- Cover hidden-page updates, switching view modes, independent inspector filters,
  close/reopen/reload behavior, and linked selection after layout changes.
- Add a real moving-emitter scenario showing a trail behind its current position
  and its subsequent decay as published by the host.

Existing tests that reach controls directly may need mechanical adapter/layout
updates. List each such change and preserve the assertion's behavioral meaning;
do not remove checks just because a private UI field moved.

### Existing gates and rendered evidence

Confirm the current Makefile entry points before using them. The reviewed
Makefile exposes `make check_scent`, `make check_search`,
`make check_senses_windows`, and `make check_vision_review`.
Run those affected gates and the final `make check`, including normal discovery
of any new tests. Record exact test totals and any pre-existing failures.

Run `tests/scent_check.py --graphical` and
`tests/senses_windows_check.py --graphical` with the repository's usual tool
arguments. Extend the graphical drivers to actually visit the new views and
controls; launching an unchanged driver alone is not proof of the minimap.

Provide matched-window screenshots of Vision, Olfaction, and Memory at 1000x700
and 1200x800, plus a rectangular arena. Show the same arena frame across pages,
a visible scent wake, readable legends/details, local sensor mode, and an honest
stale state. Include the existing F8 overlay in a comparison with the minimap.
For local mode, provide paired Vision/Olfaction radar captures at both supported
window sizes and identify the shared component they instantiate. Similar-looking
screenshots alone do not prove that the duplicated implementation was removed.
If a display is unavailable, report rendered checks as blocked, not passed.

Use existing display/read/update metrics for a representative before/after run
with both inspectors and a large supported arena. Include evidence that repeated
unchanged frames do not rebuild the heatmap, and that memory/read time remain
bounded. Do not claim server performance improvement from a UI change.

Automated rendering is not physical keyboard/mouse testing. Label those coverage
limits honestly. The Team Lead will independently review and test the handback.

## 8. Deliverables and acceptance

Deliver small, reviewable changes and:

- `docs/codebase/dev-arena-overview.md`: component ownership, data flow, adding
  another existing-data layer, coordinate rules, status/knowledge distinctions,
  and how to launch and inspect the views.
- Targeted updates to current olfaction/search documentation if their UI
  descriptions change. Do not rewrite historical server-refactor reports.
- `docs/dev-arena-overview-coding-agent-report.md`: baseline/candidate identity,
  changed files, actual shared API/consumers including both radar views,
  intentional UI changes, test
  modifications, command exits, evidence paths, rendered coverage, performance
  observations, and anything not verified.

Mark the handback **READY FOR INDEPENDENT REVIEW**, never accepted. Leave all
changes unstaged and uncommitted. You may append one handback link to this packet;
do not rewrite its scope.

Acceptance means a developer can immediately compare the three views, see the
published scent trail, distinguish world truth from personal knowledge, and
trace a UI issue through a small owning component. It does not mean creating
more folders or making every sense render the same kind of information.


Handback: [coding agent report](dev-arena-overview-coding-agent-report.md) — READY FOR INDEPENDENT REVIEW, not accepted.
