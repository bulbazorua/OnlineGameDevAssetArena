extends Polygon2D

@export var jump_height := 12.0
@export var jump_seconds := 0.36


func _init() -> void:
	polygon = PackedVector2Array([Vector2(-1, 0), Vector2(-0.65, -1), Vector2(0.65, -1), Vector2(1, 0), Vector2(0.65, 1), Vector2(-0.65, 1)])
	color = Color(0, 0, 0, 0.45)
	visible = false


func present(active: bool, age_seconds: float, footprint_radius: float) -> float:
	visible = active and age_seconds >= 0 and age_seconds < jump_seconds
	if not visible: return 0.0
	var progress := clampf(age_seconds / maxf(jump_seconds, 0.01), 0, 1)
	var arc := 4 * progress * (1 - progress)
	scale = Vector2(footprint_radius, footprint_radius * 0.3) * (1 - 0.2 * arc)
	modulate.a = 1 - 0.15 * arc
	return jump_height * arc
