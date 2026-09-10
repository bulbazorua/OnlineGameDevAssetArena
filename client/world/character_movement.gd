class_name CharacterMovement
extends RefCounted

const ArenaCatalog = preload("res://content/arena_catalog.gd")
const SPEED := 120.0
const STEP := 1.0 / 60.0
const LEFT := 1
const RIGHT := 2
const UP := 4
const DOWN := 8


# Keep this fixed-step rule in agreement with server/movement.odin.
static func move(position: Vector2, mask: int, radius: float, arena: ArenaCatalog.ArenaDefinition, catalog: ArenaCatalog) -> Vector2:
	var direction := Vector2(float((mask >> 1) & 1) - float(mask & 1), float((mask >> 3) & 1) - float((mask >> 2) & 1))
	var displacement := direction.normalized() * SPEED * STEP
	var result := position
	var candidate := result + Vector2(displacement.x, 0)
	if catalog.position_is_clear(arena, candidate, radius) and catalog.step_is_allowed(arena, result, candidate):
		result = candidate
	candidate = result + Vector2(0, displacement.y)
	if catalog.position_is_clear(arena, candidate, radius) and catalog.step_is_allowed(arena, result, candidate):
		result = candidate
	return result
