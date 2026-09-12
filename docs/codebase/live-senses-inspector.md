# Live senses inspector: ownership, timing and lifecycle

The senses inspector answers "what did this creature just sense?" The decision
debugger answers "what did it do with that evidence?" They are different native
Godot processes. Their polling, selection, drawing and window lifetimes do not
control the simulation or one another.

The senses window also has a separate **Exploration memory** page answering
"where does this creature remember visiting?" It uses the existing private
search feed, independently of F6. It does not add history to Vision or introduce
a decision/event browser. See [the memory display flow](opponent-search.md#live-exploration-memory-display)
for its owner filter, simulation-clock aging and lifecycle checks.

## Host to window

1. Production sensing creates a bounded `observations.Vision_Sample`. The host
   copies it into the observer's decision context. No new sensing query is added
   for the inspector.
2. The existing diagnostic queue carries the consumed context by value to its
   writer thread. The writer caches the display fan and the original enqueue
   time by round, observer and sample. Repeated decisions using that sample do
   not reset its delivery clock. If the first record was dropped, time is unknown.
3. World-capture jobs also carry a small lifecycle record: active, round, map and
   two entity bindings. The writer updates it even if replay has reached its size
   limit. `sense_debug_collect` excludes old-round and replaced-entity records,
   and produces no readings in the lobby. It never exposes world positions.
4. `server/diagnostics/senses.odin` publishes `senses.json`, now schema 4, with the current
   projection and timing. It writes a temporary file, checks the 32 KiB ceiling
   and replaces the previous file. Consumers can miss publications without
   making a backlog. The shared queue's existing drop count remains authoritative.
5. `client/dev/sense_feed.gd` validates the envelope, run, fingerprint, lifecycle,
   bounded lists, observer and vision geometry before accepting it. Re-reading
   the same publication does not refresh its freshness timer. The class has no
   journal loading, memory lookup or world query.
6. `client/dev/senses/senses_window.gd` selects its assigned owner and passes only
   that record to the presentation. `vision_readings.gd` constructs current rows
   from focused sightings and coarse cues, with no fields copied from previous
   samples. The view and details consume those rows. Public appearance names
   come from content using a supplied appearance ID, never an unseen entity ID.
7. `vision_sensor_view.gd` uses the same `vision_cone_geometry.gd` as the arena.
   It draws sampled positions and approximate cue wedges, without terrain,
   host rejection candidates, brain state, memory or predicted movement.
8. Since the dev arena overview slice, the window only binds and wires pages:
   `vision_page.gd`, `olfaction_page.gd` and `exploration_memory_panel.gd` all
   extend `sense_page.gd` (one layout) and each instantiates the shared
   `client/dev/ui/arena_overview.gd` frame with its own layer, while the two
   local radar views instantiate `client/dev/ui/sensor_radar.gd`. Ownership,
   coordinate rules and the field's separate clock are in
   [the shared frames](dev-arena-overview.md).

The display fan is a diagnostic approximation of cover, while production
visibility still tests subjects exactly. Do not turn that fan into a new sensor
or feed it back into decision logic.

## Clocks and budget

The sensor keeps its authored 10 Hz schedule. The writer publishes when a fresh
sample arrives, with a 50 ms heartbeat for lifecycle/freshness. Senses windows
poll at 25 ms; operating-system scheduling and existing full-history writes can
delay either operation. The single writer remains the owner of history, replay,
fan caches and live projection. This avoids sharing mutable writer buffers with
another thread, and does not add filesystem work to the simulation tick.

`origin_unix_us` maps the host's monotonic diagnostic clock to the local system
clock. `delivered_us` is the original `queued_us` of the decision consuming the
new sample, relative to that origin. A retained sample keeps that first value.
`display_metrics.gd` measures to a rendered frame, once per newly displayed
sample. It stores up to 256 delay and update-gap values, not old observations.
The status file exposes distributions and high-water read/update costs for QA.
These are local process-to-render timings, not physical monitor scanout latency.
Headless results exercise scheduling but do not prove pixels or native windows.

The displayed sample age includes the source-to-delivery tick difference plus
elapsed time since delivery. The tick rate is the existing fixed 60 Hz protocol
contract. Clock adjustment can distort diagnostic age/delay; negative delays are
counted as clock errors and unavailable ages remain labeled. Gameplay uses only
its existing simulation clocks. Recordings keep the existing trace/replay formats.

No fresh publication for 750 ms, or an invalid read, produces **STALE**. Three
seconds without a fresh publication produces **DISCONNECTED**. Last valid rows
may remain for inspection under that explicit status and dimmed geometry; they
are not presented as live. A valid lifecycle reset clears them immediately.
An unchanged sampled observation is also stale after 750 ms (or three sampling
intervals for a slower profile), even if publication heartbeats keep arriving.

## Process lifetime and future senses

`tools/dev_session.py` keeps one optional companion registry and distinguishes
`ai1/ai2` from `senses1/senses2` in its status metadata. Launch requires `--dev`,
the companion role, an owner, absolute local directories and the current run.
The scene rejects an unbound or non-debug launch. Release hosts reject telemetry.
The scene is not attached to ordinary game clients or audience clients.

Closing an optional companion removes only its process from readiness/reload
waits. Its slot stays closed across subsequent generations of that launcher run.
A code/content change stages and validates a fresh project, then reopens each
remaining window with a new run identity. Visual-only changes acknowledge the
generation without resetting the match. Senses drawings use geometry and labels,
so they validate resource notifications without recreating an arena or connection.

Olfaction now uses this boundary: `obs.Scent_Sample` travels in the same
records with its own delivery clock and its zone coverage, `olfaction_readings.gd`
projects current rows and coverage counts, and `olfaction_sensor_view.gd` draws
measured, partly measured and unknown zones apart ([deep dive](olfaction.md)).
Future senses get their own typed observations and a presentation adapter at
the same boundary. Hearing events need explicit freshness and identity rules; a
current empty vision array cannot serve as their default. Do not add an
event-history pane to accommodate them. Diagnostic history stays in the decision
debugger and recording tools.
