package observations

LOCAL_TERRAIN_SIDE :: 13
LOCAL_TERRAIN_CELLS :: LOCAL_TERRAIN_SIDE * LOCAL_TERRAIN_SIDE

Terrain_State :: enum u8 { Unknown, Clear, Solid }

// A small eye sample, not the arena map. Each byte holds one seen tile's
// ground state, height and stairs flag. Zero always means unknown.
Terrain_Sample :: struct {
    valid: bool,
    origin: [2]int,
    tile_size: f32,
    cells: [LOCAL_TERRAIN_CELLS]u8,
}

terrain_cell :: proc(state: Terrain_State, elevation: u8 = 0, stairs: bool = false) -> u8 {
    if state == .Unknown { return 0 }
    return u8(state) | ((elevation & 3) << 2) | (16 if stairs else 0)
}

terrain_state :: proc(cell: u8) -> Terrain_State { return Terrain_State(cell & 3) }
terrain_elevation :: proc(cell: u8) -> u8 { return (cell >> 2) & 3 }
terrain_has_stairs :: proc(cell: u8) -> bool { return cell & 16 != 0 }
