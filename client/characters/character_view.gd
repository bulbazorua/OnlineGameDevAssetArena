class_name CharacterView
extends Node2D

const CharacterVisual = preload("res://characters/character_visual.gd")
const PLAYER_COLORS := [Color("e0e7f2"), Color("58a6ff"), Color("ffac62")]
var visual: CharacterVisual
var player_id := 0
var radius := 24.0
var is_local := false


func configure(character_visual: CharacterVisual, owner_id := 0, display_radius := 24.0) -> void:
	visual = character_visual
	player_id = owner_id
	radius = display_radius
	queue_redraw()


func _draw() -> void:
	if visual == null:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color("52617a"), 2.0, true)
		return
	var color: Color = PLAYER_COLORS[player_id]
	var points := PackedVector2Array()
	match visual.placeholder_kind:
		CharacterVisual.PlaceholderKind.CIRCLE:
			draw_circle(Vector2.ZERO, radius, color, true, -1.0, true)
		CharacterVisual.PlaceholderKind.SQUARE:
			points = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
		CharacterVisual.PlaceholderKind.TRIANGLE:
			points = PackedVector2Array([Vector2(0, -1.2), Vector2(1.1, 0.9), Vector2(-1.1, 0.9)])
		CharacterVisual.PlaceholderKind.DIAMOND:
			points = PackedVector2Array([Vector2(0, -1.3), Vector2(1, 0), Vector2(0, 1.3), Vector2(-1, 0)])
	if not points.is_empty():
		for index in points.size():
			points[index] *= radius * 0.85
		draw_colored_polygon(points, color)
		points.append(points[0])
		draw_polyline(points, color.lightened(0.25), 1.0, true)

	if is_local:
		draw_arc(Vector2.ZERO, radius + 4, 0, TAU, 48, Color(1, 1, 1, 0.8), 1.2, true)
