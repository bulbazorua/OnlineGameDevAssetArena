# Sight geometry: closed cells and the lane sweep

Code: [`server/perception/grid_visibility.odin`](../../server/perception/grid_visibility.odin),
used by `vision_sample` and `vision_fan` in
[`server/perception/vision.odin`](../../server/perception/vision.odin).
Behavior record: [6B.1 focused and peripheral vision](../06g-focused-and-peripheral-vision.md).

## The rule

A sight segment runs from the observer's ground point to the subject's ground point,
in world units. The host bakes one boolean per arena cell (`blocks_vision`) into an
`Opacity_Grid`. The segment is **blocked when any opaque cell's closed square touches
it**. "Closed" means the square includes its four edges and four corners, so:

- a segment running exactly along a wall's edge is blocked on either side of the wall;
- a segment ending exactly on a wall's corner or edge is blocked;
- a segment slipping diagonally between two wall corners that meet at a point is blocked;
- an opaque origin or target cell blocks;
- any endpoint outside the map blocks, while the map's outer boundary line itself is inside.

The rule does not depend on which end the segment starts from. Water and other
walk-blocking terrain that does not set `blocks_vision` never blocks sight. Elevation is
not part of the query, so height alone never occludes.

`segment_reaches_cell` is the exact touch test: a Liang-Barsky clip of the parametric
segment against one closed unit square in cell units. It returns the entry parameter
`t`, which `sight_probe` reports as `reach`, the clear fraction before the first block.
The display fan uses `reach` to shorten its rays.

## Why a lane sweep

The first candidate scanned every cell of the segment's bounding box. That had two
faults that the Team Lead review reproduced:

1. The box was built with `floor` on both ends, so a segment lying exactly on the grid
   line `x = 160` (tile 32) only visited column 5, never column 4 whose closed square
   touches `x = 160`. Wall edges leaked on the right and bottom sides.
2. The box was capped at 70 × 70 cells "for safety", but accepted content (128-cell
   maps, 16-unit tiles, a 64-gameplay-unit range) produces longer boxes. The cap turned
   a clear ray into `Occluded`, inventing cover on an empty map.

The sweep replaces both. It walks the segment lane by lane along the axis it travels
most (columns for a mostly horizontal segment, rows for a mostly vertical one). For each
lane it computes the span the segment covers on the other axis while inside that lane,
then visits only the cells touching that span. Each candidate still goes through the
exact touch test, so the sweep is only an enumeration; it never decides a block itself.

`cells_touching_span(lo, hi)` returns cells `ceil(lo) - 1 .. floor(hi)`. A span that
ends exactly on a grid line therefore includes the cells on both sides of that line,
which is what makes edge and corner touches visible to the enumeration. A tiny slack
(`SWEEP_SLACK`, 1e-7 cells) pads each lane span so floating-point rounding in the lane
interpolation cannot drop a cell the exact test would accept.

Work per segment is at most `lanes × (cells per lane)`. Lanes are bounded by the map side
(`MAX_GRID_SIDE = 128`, enforced by `grid_valid` and by both content readers), and a lane
holds at most about four cells because the minor axis moves at most one cell per lane
plus the two boundary neighbors. The 4,000-segment equivalence test in
`vision_test.odin` compares the sweep to an exhaustive scan of every cell on a
random grid, including coordinates snapped to grid lines and cell centers.

## Supported envelope

| Limit | Value | Enforced by |
| --- | --- | --- |
| Map side | 3–128 cells | `perception.MAX_GRID_SIDE`, `content_parse_arenas`, `ArenaCatalog` |
| Tile size | 16–128 world units | `content_parse_arenas`, `ArenaCatalog` |
| Vision range | Greater than 0 and at most 64 gameplay units (2,048 world units) | `perception.MAX_RANGE_GAMEPLAY_UNITS`, `content_parse_senses`, `SenseCatalog` |

Within this envelope no work limit can masquerade as cover: a query is either invalid
(and reported `Disabled` or blocked because a point lies outside the map) or evaluated
exactly. Measured on the worst corner of the envelope (128 × 128 map, 16-unit tiles,
2,048-unit range, one cell in five opaque), a three-candidate sample costs about 19 µs
and the 65-ray display fan about 0.35 ms on the writer thread. A full serial simulation
tick with both creatures and both trainers near the far end of each other's sight on an
empty 128 × 128 map averages about 6.8 µs (46.8 µs worst), against 1.9 µs on the QA arena.

## Presentation agreement

The display fan and detection share `sight_probe`, so a ray drawn as clipped at a wall
and a subject reported `Occluded` behind it come from the same rule. The fan is coarse
(65 rays); at long ranges neighboring rays are farther apart than a tile, so the fan is a
visual guide, never the detector. The developer reference map draws only real cells,
clamped to the arena, and marks the map edge as a red boundary because outside counts
as opaque.
