// Bounded planar sight tests over an immutable opacity grid supplied by the host.
// This package is privileged geometry: it sees true positions and terrain. Its
// output boundary is the observations package, never a world reference.
package perception

import obs "../observations"
import "core:math"

// Row-major sight-blocking cells. Built once per arena by the host; never mutated
// by perception. Walkability is a separate property and is not consulted here.
Opacity_Grid :: struct {
    width, height: int,
    tile_size: f32,
    opaque: []bool,
}

// Largest map side both content readers accept. One sight test walks at most this
// many lanes, so work stays small at every accepted range and tile size.
MAX_GRID_SIDE :: 128

// Tiny padding, in cells, around each lane span so rounding cannot skip a cell that
// the exact touch test would accept.
@(private)
SWEEP_SLACK :: 1e-7

grid_valid :: proc(grid: Opacity_Grid) -> bool {
    return grid.width > 0 && grid.height > 0 && grid.width <= MAX_GRID_SIDE && grid.height <= MAX_GRID_SIDE &&
        grid.tile_size > 0 && !math.is_nan(grid.tile_size) && !math.is_inf(grid.tile_size) &&
        len(grid.opaque) == grid.width * grid.height
}

grid_cell_of :: proc(grid: Opacity_Grid, point: obs.Vector) -> [2]int {
    return {int(math.floor(point.x / grid.tile_size)), int(math.floor(point.y / grid.tile_size))}
}

// Outside the map counts as opaque.
grid_cell_opaque :: proc(grid: Opacity_Grid, cell: [2]int) -> bool {
    if cell.x < 0 || cell.y < 0 || cell.x >= grid.width || cell.y >= grid.height { return true }
    return grid.opaque[cell.y * grid.width + cell.x]
}

grid_contains_point :: proc(grid: Opacity_Grid, point: obs.Vector) -> bool {
    if !obs.vector_finite(point) { return false }
    return point.x >= 0 && point.y >= 0 && point.x <= f32(grid.width) * grid.tile_size && point.y <= f32(grid.height) * grid.tile_size
}

// Liang-Barsky clip of the parametric segment a + t*d, t in [0,1], against the
// closed unit square at (cx, cy). Touching an edge or a corner counts as inside.
@(private)
segment_reaches_cell :: proc(ax, ay, dx, dy, cx, cy: f64) -> (entry: f64, touches: bool) {
    t0, t1 := 0.0, 1.0
    clip :: proc(p, q: f64, t0, t1: ^f64) -> bool {
        if p == 0 { return q >= 0 }
        t := q / p
        if p < 0 {
            if t > t1^ { return false }
            if t > t0^ { t0^ = t }
        } else {
            if t < t0^ { return false }
            if t < t1^ { t1^ = t }
        }
        return true
    }
    if !clip(-dx, ax - cx, &t0, &t1) { return 0, false }
    if !clip(dx, cx + 1 - ax, &t0, &t1) { return 0, false }
    if !clip(-dy, ay - cy, &t0, &t1) { return 0, false }
    if !clip(dy, cy + 1 - ay, &t0, &t1) { return 0, false }
    return t0, t0 <= t1
}

// Cells whose closed square touches the closed span [lo, hi] along one axis. A span
// ending exactly on a grid line touches the cells on both sides of that line.
@(private)
cells_touching_span :: proc(lo, hi: f64, count: int) -> (first, last: int) {
    return clamp(int(math.ceil(lo)) - 1, 0, count - 1), clamp(int(math.floor(hi)), 0, count - 1)
}

// Minor-axis span the segment covers while it is inside one lane of the major axis.
@(private)
segment_extent_in_lane :: proc(a, d: [2]f64, major, lane: int) -> (lo, hi: f64) {
    minor := 1 - major
    if d[major] == 0 { return a[minor] - SWEEP_SLACK, a[minor] + SWEEP_SLACK }
    enter := clamp((f64(lane) - a[major]) / d[major], 0, 1)
    leave := clamp((f64(lane + 1) - a[major]) / d[major], 0, 1)
    at_enter := a[minor] + d[minor] * enter
    at_leave := a[minor] + d[minor] * leave
    return min(at_enter, at_leave) - SWEEP_SLACK, max(at_enter, at_leave) + SWEEP_SLACK
}

// Supercover test: every opaque cell whose closed square touches the segment blocks
// it, including corner-only and edge-aligned touches, opaque origin or target cells
// and endpoints outside the map. `reach` is the clear fraction before the first block.
sight_probe :: proc(grid: Opacity_Grid, from, to: obs.Vector) -> (clear: bool, reach: f32) {
    if !grid_valid(grid) || !grid_contains_point(grid, from) || !grid_contains_point(grid, to) { return false, 0 }
    tile := f64(grid.tile_size)
    a := [2]f64{f64(from.x) / tile, f64(from.y) / tile}
    b := [2]f64{f64(to.x) / tile, f64(to.y) / tile}
    d := b - a
    // Walk lane by lane along the axis the segment travels most. Each lane holds only
    // the few cells the segment can touch there, so work grows with length, not map area.
    major := 0 if abs(d.x) >= abs(d.y) else 1
    minor := 1 - major
    sides := [2]int{grid.width, grid.height}
    clear = true
    nearest := 1.0
    first_lane, last_lane := cells_touching_span(min(a[major], b[major]), max(a[major], b[major]), sides[major])
    for lane in first_lane..=last_lane {
        lo, hi := segment_extent_in_lane(a, d, major, lane)
        first, last := cells_touching_span(lo, hi, sides[minor])
        for across in first..=last {
            cell: [2]int
            cell[major], cell[minor] = lane, across
            if !grid.opaque[cell.y * grid.width + cell.x] { continue }
            entry, touches := segment_reaches_cell(a.x, a.y, d.x, d.y, f64(cell.x), f64(cell.y))
            if !touches { continue }
            clear = false
            nearest = min(nearest, entry)
        }
    }
    return clear, f32(nearest)
}

line_of_sight :: proc(grid: Opacity_Grid, from, to: obs.Vector) -> bool {
    clear, _ := sight_probe(grid, from, to)
    return clear
}
