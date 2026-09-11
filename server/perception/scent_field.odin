// The shared scent environment: one anonymous concentration per arena cell and
// scent class, deposited by emitters and thinned by simulation time. Like terrain
// it belongs to the world; nothing here knows who left a deposit.
package perception

import obs "../observations"
import "core:math"

// How scent behaves on a cell. Authored per terrain, independent of walking and sight.
Scent_Medium :: enum u8 { Open, Water, Solid }

MAX_GRID_CELLS :: MAX_GRID_SIDE * MAX_GRID_SIDE
// Field updates run every six ticks (10 Hz); deposits happen every tick.
SCENT_STEP_TICKS :: 6
SCENT_HALF_LIFE_TICKS :: 1200      // Open ground keeps scent for a while: half gone after 20 s.
SCENT_WATER_HALF_LIFE_TICKS :: 120 // Water carries scent but loses it fast: half gone after 2 s.
SCENT_SPREAD_SHARE :: f32(0.003)   // Share a cell gives to each open neighbour per step: a faint halo.
SCENT_NEGLIGIBLE :: f32(0.001)     // Below this a cell is empty again, not "almost zero forever".
SCENT_CAP :: f32(1)                // A cell never holds more than a fully saturated trace.
SCENT_EMISSION_PER_SECOND :: f32(1.5)
SCENT_EMISSION_PER_TICK :: SCENT_EMISSION_PER_SECOND / 60
// A move longer than this many tiles in one tick is a teleport: it paints nothing.
SCENT_TELEPORT_TILES :: f32(2)
SCENT_MAX_AGE_STEPS :: u16(65535)
// Longest olfactory range both content readers accept, in gameplay units.
MAX_OLFACTION_RANGE_GAMEPLAY_UNITS :: 32

Scent_Bounds :: struct {
    active: bool,
    minimum, maximum: [2]int, // Inclusive cell corners holding every nonzero cell.
}

// Fixed storage keeps the whole runtime copyable and allocation-free. Levels are
// concentrations; ages count field steps since a cell's newest deposit.
Scent_Field :: struct {
    width, height: int,
    tile_size: f32,
    decay_open, decay_water: f32,
    steps: u32,
    bounds: Scent_Bounds,
    media: [MAX_GRID_CELLS]Scent_Medium,
    levels: [obs.Scent_Class][MAX_GRID_CELLS]f32,
    ages: [obs.Scent_Class][MAX_GRID_CELLS]u16,
}

scent_field_init :: proc(field: ^Scent_Field, width, height: int, tile_size: f32, media: []Scent_Medium) {
    field^ = {}
    if width <= 0 || height <= 0 || width > MAX_GRID_SIDE || height > MAX_GRID_SIDE || len(media) != width * height { return }
    field.width, field.height, field.tile_size = width, height, tile_size
    field.decay_open = f32(math.pow(0.5, f64(SCENT_STEP_TICKS) / f64(SCENT_HALF_LIFE_TICKS)))
    field.decay_water = f32(math.pow(0.5, f64(SCENT_STEP_TICKS) / f64(SCENT_WATER_HALF_LIFE_TICKS)))
    copy(field.media[:len(media)], media)
}

scent_field_valid :: proc(field: ^Scent_Field) -> bool {
    return field.width > 0 && field.height > 0 && field.width <= MAX_GRID_SIDE && field.height <= MAX_GRID_SIDE &&
        field.tile_size > 0 && !math.is_nan(field.tile_size) && !math.is_inf(field.tile_size)
}

scent_field_cell_of :: proc(field: ^Scent_Field, point: obs.Vector) -> [2]int {
    return {int(math.floor(point.x / field.tile_size)), int(math.floor(point.y / field.tile_size))}
}

scent_field_contains :: proc(field: ^Scent_Field, cell: [2]int) -> bool {
    return cell.x >= 0 && cell.y >= 0 && cell.x < field.width && cell.y < field.height
}

scent_field_medium :: proc(field: ^Scent_Field, cell: [2]int) -> Scent_Medium {
    if !scent_field_contains(field, cell) { return .Solid }
    return field.media[cell.y * field.width + cell.x]
}

scent_field_level :: proc(field: ^Scent_Field, class: obs.Scent_Class, cell: [2]int) -> f32 {
    if !scent_field_contains(field, cell) { return 0 }
    return field.levels[class][cell.y * field.width + cell.x]
}

// Ticks since the newest deposit on a cell, or the saturated maximum.
scent_field_age_ticks :: proc(field: ^Scent_Field, class: obs.Scent_Class, cell: [2]int) -> u32 {
    if !scent_field_contains(field, cell) { return u32(SCENT_MAX_AGE_STEPS) * SCENT_STEP_TICKS }
    return u32(field.ages[class][cell.y * field.width + cell.x]) * SCENT_STEP_TICKS
}

@(private = "file")
scent_bounds_include :: proc(bounds: ^Scent_Bounds, cell: [2]int) {
    if !bounds.active {
        bounds^ = {true, cell, cell}
        return
    }
    bounds.minimum = {min(bounds.minimum.x, cell.x), min(bounds.minimum.y, cell.y)}
    bounds.maximum = {max(bounds.maximum.x, cell.x), max(bounds.maximum.y, cell.y)}
}

// Add scent to one cell. Solid cells and cells outside the map take nothing.
scent_field_deposit :: proc(field: ^Scent_Field, class: obs.Scent_Class, cell: [2]int, amount: f32) {
    if amount <= 0 || !scent_field_valid(field) || scent_field_medium(field, cell) == .Solid { return }
    index := cell.y * field.width + cell.x
    field.levels[class][index] = min(SCENT_CAP, field.levels[class][index] + amount)
    field.ages[class][index] = 0
    scent_bounds_include(&field.bounds, cell)
}

// A step of at most two tiles crosses only a few cells; this bound just keeps the
// walk finite if rounding ever misbehaves.
SCENT_SEGMENT_MAX_CELLS :: 16

// How the walk meets grid lines on one axis: the segment fraction at the next
// line, the fraction between lines, and the cell step direction.
@(private = "file")
Scent_Axis_Walk :: struct {
    next, spacing: f32,
    step: int,
}

// A point exactly on a grid line belongs to the cell with the higher index.
@(private = "file")
scent_axis_walk :: proc(origin, delta, tile_size: f32) -> (walk: Scent_Axis_Walk) {
    walk.next, walk.spacing = math.INF_F32, math.INF_F32
    if delta == 0 { return }
    walk.step = 1 if delta > 0 else -1
    line := math.floor(origin / tile_size) + (1 if delta > 0 else 0)
    walk.next = (line * tile_size - origin) / delta
    walk.spacing = tile_size / abs(delta)
    return
}

// Spread one tick of emission over the ground actually crossed between two
// confirmed positions. Each crossed cell takes the share of the path inside it;
// a teleport-sized jump paints nothing. A corner is crossed diagonally.
scent_field_deposit_segment :: proc(field: ^Scent_Field, class: obs.Scent_Class, from, to: obs.Vector, amount: f32) {
    if amount <= 0 || !scent_field_valid(field) || !obs.vector_finite(from) || !obs.vector_finite(to) { return }
    delta := to - from
    length := math.sqrt(delta.x * delta.x + delta.y * delta.y)
    if length > SCENT_TELEPORT_TILES * field.tile_size { return }
    cell := scent_field_cell_of(field, from)
    if length == 0 {
        scent_field_deposit(field, class, cell, amount)
        return
    }
    x := scent_axis_walk(from.x, delta.x, field.tile_size)
    y := scent_axis_walk(from.y, delta.y, field.tile_size)
    covered: f32
    for _ in 0..<SCENT_SEGMENT_MAX_CELLS {
        boundary := min(x.next, y.next)
        if boundary >= 1 {
            scent_field_deposit(field, class, cell, amount * (1 - covered))
            return
        }
        scent_field_deposit(field, class, cell, amount * (boundary - covered))
        covered = boundary
        if x.next <= boundary { cell.x += x.step; x.next += x.spacing }
        if y.next <= boundary { cell.y += y.step; y.next += y.spacing }
    }
}

@(private = "file")
scent_decay_for :: proc(field: ^Scent_Field, medium: Scent_Medium) -> f32 {
    return field.decay_water if medium == .Water else field.decay_open
}

// Where a cell's scent comes from after one step: what it kept plus what flowed in
// from its open neighbours. Solid cells and the map edge exchange nothing.
@(private = "file")
Scent_Flow :: struct {
    level: f32,
    age: u16, // Age of the largest contribution; deposits are always the freshest.
}

// The open neighbours of one cell, found once and shared by every class.
@(private = "file")
Scent_Neighbours :: struct {
    indices: [4]int,
    count: int,
}

@(private = "file")
scent_open_neighbours :: proc(field: ^Scent_Field, cell: [2]int) -> (result: Scent_Neighbours) {
    for offset in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
        neighbour := cell + offset
        if scent_field_medium(field, neighbour) == .Solid { continue }
        result.indices[result.count] = neighbour.y * field.width + neighbour.x
        result.count += 1
    }
    return
}

@(private = "file")
scent_step_cell :: proc(field: ^Scent_Field, class: obs.Scent_Class, index: int, neighbours: Scent_Neighbours, decay: f32) -> Scent_Flow {
    own := field.levels[class][index]
    flow := Scent_Flow{age = field.ages[class][index]}
    dominant := own
    for slot in 0..<neighbours.count {
        neighbour_index := neighbours.indices[slot]
        inflow := field.levels[class][neighbour_index] * SCENT_SPREAD_SHARE
        flow.level += inflow
        if inflow > dominant { dominant, flow.age = inflow, field.ages[class][neighbour_index] }
    }
    flow.level += own * (1 - SCENT_SPREAD_SHARE * f32(neighbours.count))
    flow.level *= decay
    if flow.level < SCENT_NEGLIGIBLE { return {} }
    flow.age = min(SCENT_MAX_AGE_STEPS - 1, flow.age) + 1
    return flow
}

// One field step: every class spreads to open neighbours and thins by its
// medium's half-life. Work stays inside the box that currently holds scent.
scent_field_advance :: proc(field: ^Scent_Field) {
    if !scent_field_valid(field) || !field.bounds.active { return }
    field.steps += 1
    low := [2]int{max(0, field.bounds.minimum.x - 1), max(0, field.bounds.minimum.y - 1)}
    high := [2]int{min(field.width - 1, field.bounds.maximum.x + 1), min(field.height - 1, field.bounds.maximum.y + 1)}
    next_bounds: Scent_Bounds
    // Only cells inside the box are written and read back, so skip zeroing the rest.
    scratch_levels: [obs.Scent_Class][MAX_GRID_CELLS]f32 = ---
    scratch_ages: [obs.Scent_Class][MAX_GRID_CELLS]u16 = ---
    for y in low.y..=high.y {
        for x in low.x..=high.x {
            index := y * field.width + x
            medium := field.media[index]
            if medium == .Solid { continue }
            neighbours := scent_open_neighbours(field, {x, y})
            decay := scent_decay_for(field, medium)
            for class in obs.Scent_Class {
                flow := scent_step_cell(field, class, index, neighbours, decay)
                scratch_levels[class][index], scratch_ages[class][index] = flow.level, flow.age
                if flow.level > 0 { scent_bounds_include(&next_bounds, {x, y}) }
            }
        }
    }
    for y in low.y..=high.y {
        for x in low.x..=high.x {
            index := y * field.width + x
            if field.media[index] == .Solid { continue }
            for class in obs.Scent_Class {
                field.levels[class][index], field.ages[class][index] = scratch_levels[class][index], scratch_ages[class][index]
            }
        }
    }
    field.bounds = next_bounds
}

// Everything gone: a new round or a cleared arena starts from clean ground.
scent_field_clear :: proc(field: ^Scent_Field) {
    if !field.bounds.active { return }
    for class in obs.Scent_Class {
        for index in 0..<field.width * field.height { field.levels[class][index], field.ages[class][index] = 0, 0 }
    }
    field.bounds = {}
}

// Total scent of one class across the map; a cheap conservation probe for tests and QA.
scent_field_total :: proc(field: ^Scent_Field, class: obs.Scent_Class) -> f32 {
    total: f32
    if !field.bounds.active { return 0 }
    for y in field.bounds.minimum.y..=field.bounds.maximum.y {
        for x in field.bounds.minimum.x..=field.bounds.maximum.x { total += field.levels[class][y * field.width + x] }
    }
    return total
}
