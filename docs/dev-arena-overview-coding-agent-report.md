# Coding agent report: shared dev arena overview and visible scent trails

Status: **READY FOR INDEPENDENT REVIEW. NOT ACCEPTED.** All changes are unstaged
and uncommitted. Packet: [delegation](delegation.md). Deep dive:
[dev arena overview](codebase/dev-arena-overview.md).

## 1. Baseline and candidate identity

| Item | Value |
| --- | --- |
| HEAD at start | `570d669` (see `baseline/git-head.txt`) |
| Baseline | The dirty working tree before any edit, copied to `build/verification/dev-arena-overview-20260911T213944Z/baseline/source/` (client without caches, server, tests, tools, docs, Makefile). `baseline/source-manifest.sha256` (603 files) and `baseline/working-tree-manifest.sha256` identify it; `git-status.txt`, `git-untracked.txt` and the two diff patches record the pre-existing uncommitted state (`AGENTS.md`, `docs/delegation.md`, `docs/server-refactor-r1-team-lead-review.md`, untracked `docs/server-refactor-r1-delegation.md`, and the untracked `server/simulation/` package). |
| Candidate | The working tree after this assignment; `candidate/source-manifest-at-launch.sha256` hashes `client/dev`, `client/ui/debug_overlay.gd`, `tests`, `tools` and `Makefile` exactly as the final gate run saw them, and `candidate/source-manifest-final.sha256` hashes them at handback (they must be identical). |
| Tools | Godot 4.6.stable.official.89cea1439, Python 3.12.3, Odin dev-2026-03-nightly, display `:0` (see `baseline/environment.txt`). The machine clock reads 2026-09-11 evening UTC while the packet is dated 2026-09-12. |

Baseline gates were run from the preserved copy, not from HEAD, so that the
"before" numbers describe exactly the tree this work started from.

## 2. Changed files

New:

- `client/dev/ui/dev_ui_style.gd` — dev palette, legend wrap/fit, shared marks (numbers, selection ring, self marker, compass, 45° wedge), title trimming.
- `client/dev/ui/arena_overview.gd` — the shared whole-arena frame.
- `client/dev/ui/sensor_radar.gd` — the shared local radar frame.
- `client/dev/scent_field_image.gd` — the field painter shared by F8 and the minimap.
- `client/dev/senses/sense_page.gd` — one page layout for every sense.
- `client/dev/senses/vision_page.gd`, `olfaction_page.gd` — page controllers (rows, filters, selection, radar view, arena layer; the olfaction page also owns the host-field reader, clock, cell readout and pinned-cell details).
- `client/dev/senses/vision_arena_layer.gd`, `scent_field_layer.gd`, `exploration_memory_layer.gd` — arena layers.
- `tests/dev_arena_overview_check.gd`, `tests/dev_arena_overview_render_check.gd`, `tests/dev_arena_fixtures.gd` — new checks and their shared fixtures.
- `docs/codebase/dev-arena-overview.md`, this report. Godot `.uid` files for every new script.

Modified:

- `client/dev/senses/senses_window.gd` — binds, wires the three pages, keeps polling, clocks, tab selection and status output; no page construction or drawing left.
- `client/dev/senses/vision_sensor_view.gd`, `olfaction_sensor_view.gd` — now instantiate `sensor_radar.gd` and draw their marks on a plot layer inside it; public API (`set_sample`, `plot_geometry`, `legend_fits`, `coverage_counts`, `zone_coverage`, colour constants, `selected_number`, filter flags) unchanged.
- `client/dev/senses/exploration_memory_panel.gd` — extends the shared page, draws through `exploration_memory_layer.gd` on the shared frame; feed, matching, frozen ages, selection and `debug_state` unchanged (plus `legend_fits`).
- `client/dev/scent_overlay.gd` — F8 uses the shared painter; diagnostics gain `rebuilds`.
- `Makefile` — `check_arena_overview` target, in `check`.
- `tests/senses_window_driver.gd`, `tests/senses_windows_check.py`, `tests/scent_check.py`, `tests/exploration_memory_check.gd` — see section 5.
- Docs: `docs/codebase/live-senses-inspector.md`, `olfaction.md`, `opponent-search.md`, `docs/06l-live-senses-windows.md`, `docs/06n-olfactory-trails.md`, `docs/project-structure.md` (targeted paragraphs only).

Removed: `client/dev/senses/exploration_memory_map.gd` (+ `.uid`), replaced by the layer on the shared frame.

Untouched: server, protocol, publication schema, feeds' validation (`sense_feed.gd`, `scent_feed.gd`, `search_feed.gd`), AI, content, catalog, replay, `tests/olfaction_review/`, `tests/vision_review/`, `tests/olfaction_coverage/`.

## 3. Shared API and its consumers

`arena_overview.gd` (Control): `set_arena(definition) -> bool`, `has_arena()`,
`world_bounds()`, `plot_rect()`, `arena_rect()`, `scale_factor()`,
`world_to_view(point)`, `view_to_world(point)`, `contains_world(point)`,
`cell_of(world) -> Vector2i` (`NO_CELL` outside), `cell_rect(cell)`,
`add_layer(layer)` (sets the layer's `frame` property), `redraw_layers()`,
`set_badge(text, live)`, `legend_fits()`, `grid_step_cells()`; properties
`title`, `title_color`, `fit_label`, `legend_lines`, `legend_swatches`; signals
`pointer_moved(world)`, `pointer_left`, `pointer_pressed(world)`. Consumers:
`vision_page.gd` (+ `vision_arena_layer.gd`), `olfaction_page.gd`
(+ `scent_field_layer.gd`), `exploration_memory_panel.gd`
(+ `exploration_memory_layer.gd`).

`sensor_radar.gd` (Control): `add_layer(layer)`, `plot_geometry()` (center,
radius, wrapped legend, legend height), `pixels_per_unit()`,
`polar_to_view(angle, distance_units)`, `legend_fits()`, `legend_width()`,
`wrapped_legend()`, `redraw_layers()`; properties `range_units`, `guide_rings`,
`outer_ring_label`, `self_label`, `self_facing`, `show_self`, `empty_text`,
`legend_lines`, `legend_swatches`. Consumers: `vision_sensor_view.gd` (`radar`
child, `PlotLayer` draws through `_draw_plot`) and `olfaction_sensor_view.gd`
(same; adds the blind disc to `plot_geometry` and its own class legend). The
checks assert `view.radar.get_script() == sensor_radar.gd` for both.

`sense_page.gd` (VBoxContainer): `build_layout(list_heading, columns, widths)`,
`add_filter(text, color, callback)`, `set_view(mode, control)`,
`select_view(mode)`, `view_control(mode)`, static `coordinates(point)` and
`sample_age_text(...)`; fields `summary`, `timing`, `filters`, `views`,
`readout`, `list_title`, `note`, `table`, `details`, `view_mode`,
`view_buttons`; signal `view_changed(mode)`. Subclasses: the three pages.

`scent_field_image.gd` (RefCounted): `repaint(feed, show) -> bool`,
`cell_color(levels)`, `clear()`, static `content_key(feed, show)`; fields
`texture`, `image`, `painted_cells`, `rebuilds`, `floor_alpha`, `max_alpha`.
Consumers: `scent_overlay.gd` (F8, default ramp 0.06 + 0.42·level) and
`olfaction_page.gd` (minimap, ramp 0.18 + 0.82·level over the dark ground).
Both ramps are fixed functions of the published level; nothing is normalised to
the current maximum.

## 4. Intentional UI changes

- Every page now has the same rows: summary line, freshness line, view buttons
  (Arena overview / Local sensor), filter row, canvas, readout line; and on the
  right the list title, note, table and details. Column widths no longer depend
  on page content (two fixed-height control rows narrower than the column
  minimum; a fixed HBox split instead of a draggable HSplitContainer, so the
  canvas footprint is identical on every page at a given window size).
- Arena overview is the default view on Vision and Olfaction; the local radars
  remain one click away and keep their previous content. Exploration memory has
  the arena view only.
- The Olfaction arena view shows the host field ("HOST SCENT FIELD ·
  developer-only world data, not what this creature knows", privileged colour),
  the nose reach ring labelled with the sample number, a hover readout and a
  pinned-cell block under the reading details with per-class level and age and
  the unit note. The field has its own badge (LIVE / STALE / DISCONNECTED /
  WAITING with reason) separate from the nose sample status, which also appears
  in the window status line as "host field <status>".
- Private frames say "outline = developer reference, not remembered terrain" in
  their legend and readout; the frame draws the catalog outline, a neutral grid,
  corner coordinates, compass letters and "Fit: whole arena · <arena> W×H cells ·
  T units per cell". No zoom or pan was added (full fit is readable on every
  supported arena; the local radar is the close view).
- Legends moved into a fixed three-line strip inside each arena frame (so the
  footprint is stable); the radar keeps its dynamic strip. The memory summary
  became one line; memory's legend label under the table was removed in favour
  of the frame legend. The memory panel's status line is now the page's
  freshness line and the frame badge.
- Vision arena layer draws the sampled sight sectors as outlines only (a
  wall-clipped sector can be concave, which a fill cannot triangulate) plus
  focused dots and cue wedges anchored at the sampled pose. Radar cue numbers
  now sit inside the wedge and the nose bearing label sits higher, so neither
  covers a compass letter.
- F8 overlay: no visible change; it draws the shared painter's image and rebuilds
  it only when the field tick or filters change (previously on every new
  publication time).
- Status file additions: `scent_field` (status, reason, matches, published_us,
  field tick, round, size, painted cells, rebuilds, polls, read time, error,
  selected cell, filters, legend fit, view), `views`, `overview_legends_fit`,
  and `legend_fits` inside `exploration_memory`.

## 5. Test modifications

Mechanical updates that keep each assertion's meaning (a field moved to the page
that now owns it):

- `tests/exploration_memory_check.gd`: `panel._details` → `panel.details`,
  `panel._table` → `panel.table`. Everything else, including `_set_memory`,
  `_select_region`, `_map.selected_key`, `_refresh_status(now)` and the frozen
  stale age assertions, is unchanged.
- `tests/senses_window_driver.gd`: `app._vision_layout` / `_scent_layout` →
  `app._vision_page` / `_scent_page` (visibility), `app._table` / `_details` →
  `app._vision_page.table` / `.details`, `app._select_reading()` /
  `_selected_reference` → `app._vision_page.select_reading()` /
  `.selected_reference`, `app._scent_table` / `_scent_details` / `_scent_empty` /
  `_scent_pose` / `_scent_timing` / `_select_scent_reading()` →
  `app._scent_page.table` / `.details` / `.note` / `.summary` / `.timing` /
  `.select_reading()`, `app._memory._table` → `app._memory.table`, the memory map
  click now goes through `app._memory.overview.world_to_view(center)`.
  `app._vision` and `app._scent` still name the two radar views.
- New driver coverage: `_check_arena_views` (same frame and world placement on
  all three pages, legends fit, live host field with cells, pinning the nose's
  own cell and reading its own class level and age, captures of every view at
  1200×800 and at the 1000×700 minimum), local-view captures on the Olfaction
  page, field STALE/DISCONNECTED under a frozen directory with a capture, field
  recovery, and "no field for an inactive world" during the round reset
  fixture. `capture_only` now captures every view of every page.
- `tests/senses_windows_check.py`: `check_arena_overview` (legends fit, arena
  default view, live matching field, `rebuilds <= polls`, bounded read time);
  the initial wait also requires a live host field; graphical runs require the
  new capture files; `performance.json` records the field counters.
- `tests/scent_check.py`: follows the trainer while it lays the trail, then reads
  the published field under the walked cells (the wake behind the current
  position), asserts a strictly lower level at the strongest walked cell at
  least three tiles from the trainer after 12 s (decay as published), compares
  both senses windows' minimap cell counts with the publication, and waits for
  the new captures; writes `moving-emitter-trail.json`.
- New: `tests/dev_arena_overview_check.gd` (headless, 150 checks; failures are
  counted and exit 1, unlike a bare `assert` which a headless script survives),
  `tests/dev_arena_overview_render_check.gd` (graphical, 48 pixel probes at both
  window sizes on the rectangular 30×16 arena plus both radars at 400×350) and
  `tests/dev_arena_fixtures.gd`. Run by `make check_arena_overview`, which is in
  `make check`.

No existing assertion was removed or weakened. `tests/olfaction_review/`,
`tests/olfaction_coverage/` and `tests/vision_review/` are untouched and pass.

## 6. Commands and exits

All commands ran from the repository root on display `:0`. Logs are under
`build/verification/dev-arena-overview-20260911T213944Z/` (`E` below); step
timestamps and exits are in `<E>/*/logs/steps.txt` and `<E>/*/exit-codes.txt`.

Baseline (from `E/baseline/source`, the preserved pre-edit tree; `run-baseline.sh`):

| Command | Exit |
| --- | --- |
| `make check_senses_windows` | 0 |
| `python3 tests/senses_windows_check.py --graphical` | 0 |
| `make check_search` | 0 |
| `make check_scent` | 0 |
| `python3 tests/scent_check.py --graphical` | 0 |
| `make check_vision_review` | 0 |
| `tools/measure_peak_memory.py --arena meadow_crossing --seconds 45` | 1 with a relative `--output` (the tool's wrapper path must be absolute), then 0 in `run-baseline-memory.sh` |

Candidate (working tree; `E/candidate/run-candidate.sh`, third attempt; the two
earlier attempts were stopped by me and are kept under `candidate/attempt1/`
and `candidate/attempt2/`: attempt 1 failed `check_scent` because the vision
arena layer filled wall-clipped sight sectors and Godot logged triangulation
errors, fixed by drawing outlines only; attempt 2 was stopped to batch the
title-trimming and radar label placement fixes):

| Command | Exit |
| --- | --- |
| `make check_arena_overview` (new: headless 150 checks + rendered probe, 48 pixel probes) | 0 |
| `make check_search` (`exploration_memory_check.gd` + `search_check.py`) | 0 |
| `make check_scent` (olfaction review probes + `scent_check.py`) | 0 |
| `python3 tests/scent_check.py --graphical` | **1** (first run) — the decay probe picked walked cell (26, 8) where a human body stood, so its level stayed 252; test-only fix: the probe now ignores walked cells within three tiles of any body at both reads |
| `make check_senses_windows` | 0 |
| `python3 tests/senses_windows_check.py --graphical` | 0 |
| `make check_vision_review` | 0 |
| `tools/measure_peak_memory.py --arena meadow_crossing --seconds 45 --label candidate` | 0 |
| `make check` (full, 9 min 29 s) | 0 — 14 Odin suites / 181 tests all successful, 44 Godot/Python PASS lines, no `SCRIPT ERROR` or `Traceback`; this run already used the corrected `scent_check.py` |
| `make check_scent` (rerun after the probe fix) | 0 |
| `python3 tests/scent_check.py --graphical` (rerun after the probe fix) | 0 |

Pre-existing failures: none. `candidate/source-manifest-final.sha256` differs
from `source-manifest-at-launch.sha256` only in `tests/scent_check.py` (the
probe fix above); every client script is byte-identical across the whole
candidate run. The headless check reports its own count (150) and the render
probe its own (48); both exit non-zero on any failed check.

## 7. Evidence paths

Under `build/verification/dev-arena-overview-20260911T213944Z/` (has `.keep-logs`):

- `baseline/`: `environment.txt`, `git-head.txt`, `git-status.txt`,
  `git-untracked.txt`, `git-diff-unstaged.patch`, `git-diff-staged.patch`,
  `source/` (pre-edit tree), `source-manifest.sha256`,
  `working-tree-manifest.sha256`, `run-baseline.sh`, `run-baseline-memory.sh`,
  `logs/` (one log per gate, `steps.txt`), `exit-codes.txt`,
  `memory-meadow/baseline.json|.md`. The baseline graphical sandboxes live under
  `baseline/source/build/verification/` (`senses-windows-20260912-054121-390308`
  with `performance.json`, `scent-20260912-054453-*`).
- `candidate/`: `run-candidate.sh`, `logs/` (`check_arena_overview.log`,
  `check_search.log`, `check_scent.log`, `scent_graphical.log` (failed run),
  `check_senses_windows.log`, `senses_windows_graphical.log`,
  `check_vision_review.log`, `peak_memory_meadow.log`, `check_full.log`,
  `check_scent_rerun.log`, `scent_graphical_rerun.log`, `steps.txt`),
  `exit-codes.txt`, `source-manifest-at-launch.sha256`,
  `source-manifest-final.sha256`, `attempt1/`, `attempt2/`.
- `candidate/render/`: the rendered probe's captures and `render-results.json`
  (every probe with its actual and expected colour); `render-final/` is the copy
  made after the last run.
- `candidate/captures/<gate>/<sandbox>/<session>/`: every PNG and status JSON
  from the graphical and headless sandboxes (65 PNGs), plus
  `captures/highlights/` (30 named captures, see section 8).
- `candidate/moving-emitter-trail-headless.json` and
  `moving-emitter-trail-graphical.json`: the trainer path samples, the walked
  cells with their published Human levels, the decay cell before and after, and
  both windows' minimap counters.
- `candidate/senses-windows-graphical-performance.json`,
  `candidate/memory-meadow/candidate.json|.md`.
- The live gate sandboxes themselves remain under `build/verification/`
  (`senses-windows-20260912-062803-445810`, `scent-20260912-063942-471804`,
  `scent-20260912-062557-442024`, `search-*`) until log cleanup; the copies in
  `candidate/captures/` are the durable evidence.

## 8. Rendered coverage

Real window (both senses windows, `tests/senses_window_driver.gd`, graphical
`senses_windows_check.py`, Vision Range (QA) 24×14): `senses{1,2}-live.png`
(Vision arena, 1200×800), `-live-minimum.png` (1000×700), `-vision-local[-minimum].png`
(Vision radar), `-olfaction[-minimum].png` (host field on the arena),
`-olfaction-local[-minimum].png` (nose radar), `-olfaction-pinned.png` (a cell
pinned with its level and age), `-olfaction-arena-stale.png` (frozen directory:
"STALE · scent readings are not current · host field STALE", dimmed field),
`-memory[-minimum].png` (Exploration memory on the same frame), `-stale.png`,
`-fixture-*.png`, `-unsupported.png`. The same frame rectangle is asserted
equal across the three pages in the driver at both sizes.

Real window with a real moving emitter (`scent_check.py --graphical`, Scent
Trail (QA) 30×16, rectangular): `senses{1,2}-olfaction.png` show the trainer's
wake across the arena (29 of 29 walked cells at least two tiles behind the
trainer held a published Human level; the current cell held 252) and the orc's
own trail, `senses{1,2}-olfaction-local.png`, `-live.png`, `-vision-local.png`,
`-memory.png`; `p1-scent-heatmap.png` is the F8 overlay in the player window for
the comparison (both draw the shared painter's image; F8 reported 223 cells and
both minimaps 223 for the same publication).

Rendered probe (`dev_arena_overview_render_check.gd`, fixture field on the
rectangular arena): `page-{vision,olfaction,memory}-arena-{1200x800,1000x700}.png`,
`page-{vision,olfaction}-local-*.png`, `radar-{vision,olfaction}-400x350.png`
with `render-results.json`; probes cover a saturated cell, an overlapping
two-class cell, an orc cell, two wake cells, empty ground, the frame padding,
the self and focused markers on the arena and on the radar, the memory region
fill, blank memory ground, unknown / measured-empty / scented nose zones, and
placement equality across the three pages at both sizes.

`captures/highlights/` gathers the named copies: `scent-trail-arena-senses{1,2}-olfaction-1200x800.png`,
`scent-trail-f8-heatmap-p1-for-comparison.png`, `scent-trail-arena-senses2-{vision,memory}-1200x800.png`,
`vision-range-senses1-*.png` (all views at both sizes, pinned, stale) and the
probe renders. Coverage limit: automated rendering and synthetic input, not
physical keyboard or mouse use.

## 9. Performance observations

Display latency (graphical `senses_windows_check.py`, Vision Range, p95 target ≤ 150 ms):

| Window | Baseline p50 / p95 / max (ms) | Candidate p50 / p95 / max (ms) |
| --- | --- | --- |
| senses1 vision | 52.8 / 86.2 / 119.5 | 24.9 / 91.4 / 107.9 |
| senses2 vision | 36.4 / 102.5 / 104.7 | 41.4 / 107.8 / 124.6 |
| senses1 olfaction | 52.7 / 86.3 / 185.9 | 25.2 / 92.1 / 107.4 |
| senses2 olfaction | 36.4 / 102.5 / 219.7 | 42.0 / 75.5 / 191.6 |

Inspector costs (status file high-water marks, microseconds):

| Run | Baseline read / update | Candidate read / update | Candidate field read max, polls, rebuilds, cells |
| --- | --- | --- | --- |
| Vision Range, senses1 | 580 / 1096 | 611 / 1853 | 147, 269, 186, 30 |
| Vision Range, senses2 | 592 / 954 | 617 / 1940 | 97, 260, 177, 30 |
| Meadow Crossing 60×28, senses1 (45 s) | 1908 / 2424 | 1564 / 5012 | 291, 413, 332, 176 |
| Meadow Crossing 60×28, senses2 (45 s) | 2766 / 3123 | 624 / 4987 | 321, 409, 329, 176 |

The senses feed read cost is unchanged. The worst-case poll update roughly
doubled because the poll now also reads the field (bounded by the existing
96 KiB reader, at most every 100 ms) and rebuilds the 60×28 image when the
field tick changes; that rebuild is a per-cell `Image.set_pixel` loop and is
the largest new cost (about 5 ms worst case on the big arena, inside a 25 ms
poll). Rebuilds stay below polls in every run; in a live match the field steps
every 6 ticks while bodies emit, so most publications do carry a new tick. The
headless check proves republished identical ticks and repeated polls do not
rebuild. Peak memory (Meadow Crossing, 45 s, `measure_peak_memory.py`):

| Process | Baseline VmHWM / Pss (KiB) | Candidate VmHWM / Pss (KiB) |
| --- | --- | --- |
| senses1 | 211,964 / 117,907 | 214,396 / 120,394 |
| senses2 | 211,952 / 117,927 | 218,720 / 124,631 |
| sum of all seven | 2,929,064 / 2,358,798 | 2,943,700 / 2,376,055 |

Each senses window grew by 2–7 MB (the field reader's decoded layers, the
painter's image and texture, and the extra page controls). No server change
was made and no server performance claim is made.

## 10. Not verified, limits and decisions

- Automated rendering is not physical keyboard and mouse testing. Clicks in the
  graphical drivers are synthetic events; hover readouts were exercised through
  the page's pointer handlers in the headless check and by synthetic clicks in
  the driver, not by a physical mouse.
- The three-page footprint equality is proven at the two supported window sizes
  in the headless check, the render probe and the live driver; other sizes
  follow the same size-only computation but were not captured.
- Zoom/pan was not implemented (the packet allows omitting it when full fit is
  readable); a 128×128 arena at the minimum window gives about 3 px per cell,
  which is visible as a heatmap but not inspectable without the readout.
- The user-draggable split between canvas and table was replaced by a fixed
  ratio so that the canvas footprint cannot diverge between pages.
- The field minimap uses a brighter fixed alpha ramp than F8 because it draws
  over dark ground; both ramps are stable functions of the published level and
  the same image builder. Per-cell numbers are shown for the pinned cell, so the
  ramp never hides a faint level.
- Rebuild counts in a live run are close to poll counts because the host field
  really changes every step while bodies emit; the "no rebuild on unchanged
  frames" property is proven by the headless check (republished identical ticks
  and repeated polls keep `rebuilds` constant) and by the counters staying
  `rebuilds <= polls`.
- Godot's headless `ImageTexture.get_image()` is unreliable after `set_image`;
  the checks read the painter's CPU `image` instead.
- No server performance claim is made; only inspector read/update costs and
  process memory are reported.
