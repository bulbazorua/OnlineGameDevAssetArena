extends Control

var record: Dictionary = {}
var event_count := 0


func present(value: Dictionary, count: int) -> void:
	record = value
	event_count = count
	queue_redraw()


func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	if record.is_empty(): return
	var input: Dictionary = record.input
	var anchor := Vector2(input.anchor[0], input.anchor[1])
	var position := Vector2(input.position[0], input.position[1])
	var radius := float(record.config.roam_radius)
	var scale_factor := minf(size.x - 50, size.y - 100) / (radius * 2.3)
	var center := size * 0.5 + Vector2(0, 10)
	var origin := center + (position - anchor) * scale_factor
	var font := ThemeDB.fallback_font
	for x in range(-4, 5):
		var offset := x * radius * scale_factor / 4.0
		draw_line(center + Vector2(offset, -radius * scale_factor), center + Vector2(offset, radius * scale_factor), Color("263342"))
		draw_line(center + Vector2(-radius * scale_factor, offset), center + Vector2(radius * scale_factor, offset), Color("263342"))
	draw_arc(center, radius * scale_factor, 0, TAU, 64, Color("627790"), 1.5, true)
	draw_circle(center, 4, Color("e8c578"))
	draw_string(font, Vector2(16, 24), "SAMPLED SELF STATE  /  tick %d" % int(input.tick), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e4eaf2"))
	draw_string(font, Vector2(16, 46), "Position (%.1f, %.1f)  ·  roam radius %.0f" % [position.x, position.y, radius], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("a6b8cb"))
	for index in mini(event_count, record.nodes.size()):
		var node: Dictionary = record.nodes[index]
		if node.metric != "squared_distance / squared_radius": continue
		var direction := Vector2(node.direction[0], node.direction[1])
		_arrow(origin, origin + direction * 42, Color("75d6a3") if node.status == "Passed" else Color("f18683"), 2)
	var color := Color("58a6ff") if int(record.owner_id) == 1 else Color("ffac62")
	draw_circle(origin, 9, color)
	var angle := int(record.facing) * PI / 4.0
	_arrow(origin, origin + Vector2(sin(angle), -cos(angle)) * 22, Color("e9eff8"), 2)
	for index in mini(event_count, record.nodes.size()):
		var node: Dictionary = record.nodes[index]
		if node.stage == "Decision":
			_arrow(origin, origin + Vector2(node.direction[0], node.direction[1]) * 60, Color("72d0df"), 3)
		if node.stage == "Outcome":
			var after := Vector2(record.position_after[0], record.position_after[1])
			draw_circle(center + (after - anchor) * scale_factor, 13, Color("75d6a3"), false, 2)
	draw_string(font, Vector2(16, size.y - 39), "Cyan: requested direction   Green ring: resolved position", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a6b8cb"))
	draw_string(font, Vector2(16, size.y - 18), "Vision is not implemented. This is not a sensed world map.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e8c578"))


func _arrow(start: Vector2, end: Vector2, color: Color, width: float) -> void:
	if start.is_equal_approx(end): return
	var delta := (end - start).normalized()
	draw_line(start, end, color, width, true)
	draw_line(end, end - delta.rotated(0.5) * 8, color, width, true)
	draw_line(end, end - delta.rotated(-0.5) * 8, color, width, true)


func _background() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("141e2a")
	box.set_corner_radius_all(8)
	return box
