package ai

import obs "../observations"

@(private)
navigation_memory_index :: proc(memory: ^Navigation_Memory, cell: [2]int) -> int {
    local := cell - memory.origin
    if local.x < 0 || local.y < 0 || local.x >= obs.LOCAL_TERRAIN_SIDE || local.y >= obs.LOCAL_TERRAIN_SIDE { return -1 }
    return local.y * obs.LOCAL_TERRAIN_SIDE + local.x
}

@(private)
navigation_known_cell :: proc(nav: ^Navigation_Runtime, cell: [2]int, tick: u32) -> u8 {
    if !nav.memory.valid { return 0 }
    index := navigation_memory_index(&nav.memory, cell)
    if index < 0 || tick - nav.memory.seen_tick[index] >= nav.profile.memory_ticks { return 0 }
    return nav.memory.cells[index]
}

@(private)
navigation_observe :: proc(nav: ^Navigation_Runtime, ctx: Decision_Context) {
    eye := ctx.senses.vision
    sample := eye.terrain
    if !ctx.senses.vision_is_new || eye.status != .Sampled || !sample.valid { return }
    if eye.observer != ctx.entity_id || eye.round_id != ctx.round_id { return }
    memory := &nav.memory
    if memory.valid && memory.sample_id == eye.sample_id { return }
    if !memory.valid || memory.origin != sample.origin || memory.tile_size != sample.tile_size {
        previous := memory^
        memory^ = {valid = true, origin = sample.origin, tile_size = sample.tile_size}
        if previous.valid && previous.tile_size == sample.tile_size {
            for y in 0..<obs.LOCAL_TERRAIN_SIDE {
                for x in 0..<obs.LOCAL_TERRAIN_SIDE {
                    index := navigation_memory_index(&previous, sample.origin + [2]int{x, y})
                    if index < 0 { continue }
                    destination := y * obs.LOCAL_TERRAIN_SIDE + x
                    memory.cells[destination] = previous.cells[index]
                    memory.seen_tick[destination] = previous.seen_tick[index]
                }
            }
        }
    }
    memory.sample_id = eye.sample_id
    for cell, index in sample.cells {
        if obs.terrain_state(cell) == .Unknown { continue }
        memory.cells[index], memory.seen_tick[index] = cell, eye.sample_tick
    }
}
