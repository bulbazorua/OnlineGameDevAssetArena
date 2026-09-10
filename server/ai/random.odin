package ai

// Explicit xorshift32 stream. Integer wrap is intentional; no global RNG.
Random_State :: struct { value: u32 }
random_seed :: proc(seed, round, entity: u32) -> Random_State {
    value := seed ~ (round * 0x9e3779b9) ~ (entity * 0x85ebca6b)
    value = (value ~ (value >> 16)) * 0x7feb352d
    value = (value ~ (value >> 15)) * 0x846ca68b
    value = value ~ (value >> 16)
    if value == 0 { value = 0xa341316c }
    return {value}
}
random_next :: proc(state: ^Random_State) -> u32 {
    x := state.value
    x = x ~ (x << 13)
    x = x ~ (x >> 17)
    x = x ~ (x << 5)
    state.value = x
    return x
}
// Bounded constant work, inclusive range. Tiny modulo bias is acceptable for wandering.
random_range :: proc(state: ^Random_State, minimum, maximum: u32) -> u32 {
    assert(maximum >= minimum && maximum - minimum < 0x7fffffff)
    return minimum + random_next(state) % (maximum - minimum + 1)
}
