# Dev arena overview: shared frames for the senses inspector

The senses inspector (`client/dev/senses/senses_window.gd`) shows three kinds of
information on one arena picture: what an eye sampled, what the host's scent
field holds, and what a creature remembers. They are three different truths, so
they stay in three separate layers, but they share one frame so a developer can
compare them without re-reading a new layout on every page.

## Components and ownership

| Component | Owns | Never owns |
| --- | --- | --- |
| `client/dev/ui/dev_ui_style.gd` | The dev palette, legend wrapping and fitting, and the marks every canvas draws the same way: numbers, selection rings, self markers, compass letters, 45° wedges. | Any sense data. |
| `client/dev/ui/arena_overview.gd` | The north-up whole-arena frame: bounds from a catalog definition, the world-to-view transform, outline, grid, compass, corner coordinates, title, status badge, fit label, legend strip, and pointer-to-world signals. Layers are full-rect children drawn between its background and its chrome. | File polling, feeds, memory projection, scent decoding, or any sense-specific truth. |
| `client/dev/ui/sensor_radar.gd` | The local-reach frame: plot circle from the control size and legend height, guide rings, outer ring label, self marker, compass letters, crosshair and legend strip. Both real sensor views instantiate it. | Sampling, coverage meaning, bearing inference. |
| `client/dev/senses/sense_page.gd` | One page layout: summary and freshness lines, view switch, filter row, canvas slot, readout line, list title, note, table, details. Shared static formatting for coordinates and sample age. | Sense logic; it knows no sense. |
| `client/dev/senses/vision_page.gd` | The Vision page: rows from one delivered eye sample, filters, selection, its radar view and its arena layer. | Another camera or layout copy. |
| `client/dev/senses/olfaction_page.gd` | The Olfaction page: nose rows, the radar view, and the host field on the arena: its own `scent_feed.gd` reader, 100 ms throttle, world/arena matching, field clock, cell readout and pinned-cell details. | Vision or memory data. |
| `client/dev/senses/exploration_memory_panel.gd` | The Exploration memory page: the search feed, lifecycle matching, frozen stale ages, linked map/list selection. | Any world query. |
| `client/dev/senses/vision_arena_layer.gd` | Draws the sampled sight fan, focused markers and approximate cue wedges at the sampled pose. | A newer hidden position. |
| `client/dev/senses/scent_field_layer.gd` | Draws the field texture, hovered and pinned cells, and the nose reach ring from the delivered sample. | Emitter positions or identities. |
| `client/dev/senses/exploration_memory_layer.gd` | Draws remembered regions, last positions, self and selection; answers which remembered region contains a world point. | Terrain or truth. |
| `client/dev/senses/vision_sensor_view.gd`, `olfaction_sensor_view.gd` | The local radar views: their own data and the meaning of every mark, drawn on a plot layer inside a `sensor_radar.gd` they instantiate. | Each other's data. |
| `client/dev/scent_field_image.gd` | One image of the published field, one pixel per cell, on a fixed alpha ramp; rebuilt only when the field tick or the class filter changes. Used by the F8 overlay and the minimap. | Feed ownership, decay, inference. |

Dependency direction: the window composes pages; pages instantiate the shared
frames and add their own layers; frames never import a sense or reach back into
the window. Shared controls take small display inputs (an arena definition, a
range, legend lines, a badge) and emit interaction signals (`pointer_moved`,
`pointer_left`, `pointer_pressed`); the page interprets them.

## Data flow

1. `senses_window.gd` polls `senses.json` every 25 ms through `sense_feed.gd`,
   looks up the catalog arena for the bound world's map, and hands the same
   definition to every page (`set_arena`). It passes the owner's record to the
   Vision and Olfaction pages, and the world to the memory panel and to the
   Olfaction page's field reader.
2. The Vision page builds rows with `vision_readings.gd`, gives the record to
   its radar view (`vision_sensor_view.gd`) and to `vision_arena_layer.gd` with
   the sight shape from `vision_cone_geometry.gd`. Both pictures anchor to the
   sampled pose and range.
3. The Olfaction page gives the nose rows to its radar view. Separately, it reads
   `scent.json` at most every 100 ms with its own `scent_feed.gd`, decides whether
   the field belongs to this world (active round, round id, map id, width, height
   and tile size against the catalog definition), and only then asks the shared
   painter for an image and gives it to `scent_field_layer.gd`. The nose ring on
   the same layer comes from the delivered sample and carries the sample number.
4. The memory panel keeps its search feed, owner matching and stale-age freezing;
   `exploration_memory_layer.gd` draws the projection through the frame's
   transform and answers region hits for clicks.

Adding another existing-data layer means: a page that owns the data and its
feed, a layer `Control` with a `frame` property that draws through
`frame.world_to_view`, `overview.add_layer(layer)`, and legend lines that fit
three lines at 400 px. Do not add polling to the frame, do not branch on the
sense inside the frame, and do not let one page read another page's state.

## Coordinate rules

- The frame fits the whole arena, aspect kept, centred in the plot rectangle
  left after the title line, compass padding and a legend strip of exactly
  three lines. World (0, 0) is the outline's top-left corner; north is up.
- Every page uses the same layout rows with fixed heights and column minimums
  wider than their content, so at the same window size all three frames have
  the same rectangle and put a world point at the same pixel. Resizing keeps
  that relationship because it is recomputed from size alone.
- `cell_of(world)` floors by the catalog tile size and returns `NO_CELL` outside
  the arena; `cell_rect(cell)` is where that cell lands on screen. Region size in
  memory and field cell size are different units that share the transform.
- Radar plots scale their outer ring to the sensor's own range. Vision cue
  sectors are counted from the sampled facing (`cue_angle`), nose zones point
  in world directions (`sector_angle`); the shared frame never rotates either.
- There is no zoom or pan. The fit label says "Fit: whole arena"; the local
  radar is the close view when a small nose reach would be unreadable.

## Status and knowledge

- The window's status line, each page's freshness line and each frame's badge
  come from that source's own clock: the eye sample, the nose sample, the host
  field publication and the search feed each go LIVE, STALE (750 ms) and
  DISCONNECTED (3 s) on their own. A fresh field never makes an old nose sample
  look live, and the scent clock never ages memory.
- The field frame is titled "HOST SCENT FIELD · developer-only world data, not
  what this creature knows" in the privileged colour. Private frames say their
  outline and grid are a developer reference, not remembered terrain.
- A field for another round, map or size is never drawn; the badge names the
  reason. A stalled or invalid publication keeps the last matching field dimmed
  under STALE or DISCONNECTED; a missing file is named. Identity changes clear
  the pinned cell. Replacing a creature does not erase the shared field.
- Cell readout: level is the published 0–255 of the saturation cap on a fixed
  scale (never normalised to the frame's maximum); age is whole seconds since
  the newest deposit, capped at 255 and shown as "≥ 255 s (capped)"; a zero
  level says "no published level", not measured-empty ground. Colour is the
  scent class, never who left it.
- The minimap filters are page-local. They save nothing and never touch the F8
  overlay's saved preferences or another window.

## Launching and inspecting

`make dev_scent P1=archer P2=orc` opens the scent QA arena with both senses
windows. Each window has Vision, Olfaction and Exploration memory pages; the
"Arena overview" and "Local sensor" buttons switch the canvas. On Olfaction,
hover a cell for the readout line and click it to pin its numbers under the
reading details. Press F8 in a player window to compare the arena heatmap with
the minimap: both draw the same painter image. The status file
`senses<owner>.json` carries `scent_field` (status, reason, tick, painted cells,
polls, rebuilds, read time), `views` and `overview_legends_fit`.

Checks: `make check_arena_overview` runs `tests/dev_arena_overview_check.gd`
(transforms, same footprint on all pages, both radar consumers, the painter
against independently computed colours, field lifecycle, privacy, view modes,
linked selection) and `tests/dev_arena_overview_render_check.gd` (the real pages
and radars rendered at both window sizes with pixel probes; needs a display).
`tests/senses_window_driver.gd` visits every view of every page in the live
window, and `tests/scent_check.py` follows a real moving emitter, its wake and
its published decay, and compares the minimap cell count with the publication.
