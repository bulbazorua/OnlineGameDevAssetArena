class_name AssetScale
extends RefCounted

const WORLD_UNITS_PER_GAMEPLAY_UNIT := 32.0


static func factor(reference_pixels: float, gameplay_size: float) -> float:
	assert(is_finite(reference_pixels) and reference_pixels > 0)
	assert(is_finite(gameplay_size) and gameplay_size > 0)
	return gameplay_size * WORLD_UNITS_PER_GAMEPLAY_UNIT / reference_pixels


static func for_grid(native_tile_pixels: float, world_tile_size: float) -> float:
	return factor(native_tile_pixels, world_tile_size / WORLD_UNITS_PER_GAMEPLAY_UNIT)
