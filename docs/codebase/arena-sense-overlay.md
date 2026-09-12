# How the arena draws a creature's vision

The brain's input already contains a private eye sample. The arena needs a picture
of that same sample, without loading hundreds of decisions into every game window.

## Data path and ownership

1. Production sensing builds the filtered sample and the existing brain consumes
   it. Neither sensing nor decision scheduling changed for this overlay.
2. The existing telemetry queue transfers a value record to the host's writer.
   `attach_fan` in `server/diagnostics/record.odin` computes/caches display geometry there using that sample's
   pose and profile. The writer already does this for debugger and replay records.
3. `server/diagnostics/senses.odin` projects the latest writer-owned record for each owner
   into a small snapshot. Only identity, source tick, vision and its display fan
   survive. Serialization and atomic replacement happen on the writer thread.
4. `tools/dev_session.py` supplies the current trace directory/run binding to
   player windows. Audience windows receive no such binding.
5. `client/dev/sense_feed.gd` reads at most 32 KiB, validates identity and typed
   vision data, and retains only the latest two records. It shares the vision
   validator with the existing trace reader, not its history-loading workflow.
6. `client/dev/sense_overlay.gd` matches the record to the current displayed round,
   map and creature. It withholds future deliveries and caches geometry by sample.
   The world snapshot supplies identity/time checks, not a new sensory query.
7. `client/dev/vision_cone_geometry.gd` splits the host fan into focus and the two
   peripheral sectors. When a field boundary falls between rays, it intersects
   the boundary with their connecting edge. Fully collapsed fields draw nothing.
8. `client/ui/debug_overlay.*` owns window-local checkboxes and hotkeys. Physical
   categories continue to belong exclusively to `CollisionOverlay`.

The source sample's coordinates are world coordinates. The overlay draws them in
the arena, so the existing camera transform applies naturally. It never moves a
cone onto a predicted sprite pose. The source age explains any visible difference.

## Timing and failure behavior

The live-window extension publishes on fresh samples with a 50 ms heartbeat, alongside the
existing 250 ms full-history snapshot cadence. Both use the same writer, so large
history serialization can still delay a small publication. No new work is placed
on the simulation or either brain thread.

The local UI reads this small file every 100 ms. This is a bounded synchronous
file read/parse, not a guaranteed disk-latency bound. No accumulating history or
extra reader thread is added. Graphical checks measured roughly 0.2 ms per read
for a roughly 6 KiB two-creature snapshot on this PC; this is an individual local
measurement, not an end-to-end latency percentile or a larger-battle benchmark.

Publication time is a freshness signal, never a replacement sample timestamp.
Repeatedly reading an unchanged file does not refresh it. After 750 ms without
a new publication, or a read/validation error, retained cones are marked stale
and dimmed. A stalled world feed uses the arena's existing 500 ms threshold.

Missing or mismatched identities are not drawn. Returning to the lobby clears
cached readings, and normal launcher relaunches create new clients with a fresh
run/directory binding. The arena never displays live private data in an audience
view; matching delayed sensory playback remains future work.

The live snapshot has no log history of its own and stays under the existing
development-directory cleanup policy. Decision journals and QA replay remain the
historical record. The [dedicated senses windows](live-senses-inspector.md) share this bounded
projection, adding lifecycle validation and original-delivery timing in schema 2.
That document describes their current-reading UI and measured latency path.
