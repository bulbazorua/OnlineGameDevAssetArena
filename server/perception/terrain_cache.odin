package perception

import obs "../observations"

// This belongs to one host receptor, never to a brain or another creature.
// The catalog stays alive while it is used; changed ground needs a new revision.
Terrain_Cache :: struct {
    valid: bool,
    pose: obs.Pose,
    profile: obs.Vision_Profile,
    width, height, terrain_count, opacity_count: int,
    tile_size: f32,
    revision: u32,
    terrain_source, opacity_source: rawptr,
    sample: obs.Terrain_Sample,
    builds, hits: u64,
}

@(private)
terrain_cache_matches :: proc(cache: ^Terrain_Cache, query: Vision_Query) -> bool {
    return cache.valid && cache.pose == query.observer.pose && cache.profile == query.profile &&
        cache.width == query.grid.width && cache.height == query.grid.height && cache.tile_size == query.grid.tile_size &&
        cache.revision == query.terrain_revision && cache.terrain_count == len(query.terrain) && cache.opacity_count == len(query.grid.opaque) &&
        cache.terrain_source == rawptr(raw_data(query.terrain)) && cache.opacity_source == rawptr(raw_data(query.grid.opaque))
}

@(private)
vision_terrain_cached :: proc(query: Vision_Query, cache: ^Terrain_Cache) -> obs.Terrain_Sample {
    if cache == nil { return vision_terrain(query) }
    if terrain_cache_matches(cache, query) {
        cache.hits += 1
        return cache.sample
    }
    sample := vision_terrain(query)
    cache^ = {valid = sample.valid, pose = query.observer.pose, profile = query.profile,
        width = query.grid.width, height = query.grid.height, tile_size = query.grid.tile_size,
        revision = query.terrain_revision, terrain_count = len(query.terrain), opacity_count = len(query.grid.opaque),
        terrain_source = rawptr(raw_data(query.terrain)), opacity_source = rawptr(raw_data(query.grid.opaque)),
        sample = sample, builds = cache.builds + 1, hits = cache.hits}
    return sample
}
