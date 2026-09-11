extends Control

signal region_selected(key: String)

const FRESH := Color("7de2b2")
const FADING := Color("edb96f")
const ENCOUNTER := Color("d8a0f0")
var memory: Dictionary = {}
var selected_key := ""
var _origin := Vector2.ZERO
var _scale := 1.0


func set_memory(value: Dictionary, selection: String) -> void:
	memory = value
	selected_key = selection
	queue_redraw()


func _world_bounds() -> Rect2:
	var cell_size: float = memory.region_size
	var self_point := Vector2(memory.position[0], memory.position[1])
	var corner := (self_point / cell_size).floor() * cell_size
	var bounds := Rect2(corner, Vector2.ONE * cell_size)
	for visit: Dictionary in memory.visits:
		bounds = bounds.merge(Rect2(Vector2(visit.region[0], visit.region[1]) * cell_size, Vector2.ONE * cell_size))
	return bounds.grow(cell_size * 0.75)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101e2c"))
	_draw_compass()
	if memory.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(24, 70), "Waiting for this creature's memory", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a2b3c8"))
		return
	var bounds := _world_bounds()
	var available := size - Vector2(88, 100)
	_scale = minf(available.x / bounds.size.x, available.y / bounds.size.y)
	_origin = size * 0.5 - bounds.get_center() * _scale
	_draw_grid(bounds)
	for visit: Dictionary in memory.visits: _draw_visit(visit)
	var self_point := _origin + Vector2(memory.position[0], memory.position[1]) * _scale
	draw_circle(self_point, 5, Color.WHITE)
	draw_arc(self_point, 8, 0, TAU, 24, Color("101e2c"), 2, true)
	draw_string(ThemeDB.fallback_font, self_point + Vector2(12, 5), "SELF", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	if memory.visits.is_empty(): draw_string(ThemeDB.fallback_font, Vector2(24, 70), "No remembered visits yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a2b3c8"))
	draw_string(ThemeDB.fallback_font, Vector2(20, size.y - 17), "Remembered regions · %.0f × %.0f world units each" % [memory.region_size, memory.region_size], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a2b3c8"))


func _draw_grid(bounds: Rect2) -> void:
	var step: float = memory.region_size * maxf(1, ceilf(maxf(bounds.size.x, bounds.size.y) / memory.region_size / 24))
	for index in 26:
		var x := ceilf(bounds.position.x / step) * step + index * step
		var y := ceilf(bounds.position.y / step) * step + index * step
		if x <= bounds.end.x: draw_line(_origin + Vector2(x, bounds.position.y) * _scale, _origin + Vector2(x, bounds.end.y) * _scale, Color("253849"))
		if y <= bounds.end.y: draw_line(_origin + Vector2(bounds.position.x, y) * _scale, _origin + Vector2(bounds.end.x, y) * _scale, Color("253849"))


func _draw_visit(visit: Dictionary) -> void:
	var region := Rect2(_origin + Vector2(visit.region[0], visit.region[1]) * memory.region_size * _scale, Vector2.ONE * memory.region_size * _scale)
	var tint := FADING.lerp(FRESH, float(visit.strength))
	draw_rect(region, Color(tint, 0.08 + 0.28 * visit.strength))
	draw_rect(region, Color.WHITE if visit.key == selected_key else Color(tint, 0.35 + 0.65 * visit.strength), false, 2 if visit.key == selected_key else 1)
	var point := _origin + Vector2(visit.position[0], visit.position[1]) * _scale
	draw_circle(point, 4, ENCOUNTER if visit.opponent_seen else tint)
	draw_string(ThemeDB.fallback_font, region.position + Vector2(5, 16), str(visit.number), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tint)


func _draw_compass() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(size.x / 2 - 4, 23), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(size.x - 23, size.y / 2), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(size.x / 2 - 4, size.y - 37), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(12, size.y / 2), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)


func _gui_input(event: InputEvent) -> void:
	if memory.is_empty() or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	var cell: Vector2 = (((event.position - _origin) / _scale) / float(memory.region_size)).floor()
	var key := "%d,%d" % [int(cell.x), int(cell.y)]
	for visit: Dictionary in memory.visits:
		if visit.key == key:
			region_selected.emit(key)
			accept_event()
			return
