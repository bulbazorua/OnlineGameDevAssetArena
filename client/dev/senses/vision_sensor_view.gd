extends Control

const Geometry = preload("res://dev/vision_cone_geometry.gd")
const Reader = preload("res://dev/ai/trace_reader.gd")
const FOCUS := Color("62d9ff")
const PERIPHERAL := Color("ffb454")
var sample: Dictionary = {}
var rows: Array[Dictionary] = []
var shape: Dictionary = {}
var selected_number := 0
var show_focus := true
var show_periphery := true


func set_sample(record: Dictionary, readings: Array[Dictionary]) -> void:
	sample = record.get("vision", {})
	rows = readings
	shape = {}
	if sample.get("status") == "Sampled": shape = Geometry.build(sample, record.sight_fan)
	queue_redraw()


func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	if shape.is_empty(): return
	var center := size / 2.0
	var compass_size := size - Vector2(0, 40)
	var radius := minf(compass_size.x, compass_size.y) * 0.42
	var scale_factor: float = radius / float(sample.profile.range)
	_draw_grid(center, radius)
	if show_focus: _draw_field(shape.focus, center, scale_factor, FOCUS)
	if show_periphery:
		_draw_field(shape.left, center, scale_factor, PERIPHERAL)
		_draw_field(shape.right, center, scale_factor, PERIPHERAL)
	for row: Dictionary in rows:
		if row.quality == "Focused" and show_focus:
			var point := Vector2(row.position[0], row.position[1])
			_draw_marker(center + (point - shape.center) * scale_factor, row)
		elif row.quality == "Peripheral" and show_periphery:
			_draw_cue(center, radius, row)
	draw_circle(center, 7, Color.WHITE)
	var forward := Vector2.from_angle(Reader.facing_index(sample.pose.facing) * PI / 4.0 - PI / 2.0)
	draw_line(center, center + forward * 25, Color.WHITE, 2, true)
	draw_string(ThemeDB.fallback_font, center + Vector2(12, 22), "SELF", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)


func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101e2c")
	style.set_corner_radius_all(8)
	return style


func _draw_grid(center: Vector2, radius: float) -> void:
	var color := Color("27394b")
	draw_line(Vector2(center.x, 18), Vector2(center.x, size.y - 18), color)
	draw_line(Vector2(18, center.y), Vector2(size.x - 18, center.y), color)
	draw_arc(center, radius, 0, TAU, 96, color, 1, true)
	draw_arc(center, radius * 0.5, 0, TAU, 64, color, 1, true)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(center.x - 4, 22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(size.x - 24, center.y - 8), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(center.x - 4, size.y - 36), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(14, center.y - 8), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(14, size.y - 16), "Range %.1f world units  ·  blank = unknown" % float(sample.profile.range), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("9dabbc"))


func _draw_field(points: PackedVector2Array, center: Vector2, scale_factor: float, color: Color) -> void:
	if points.size() < 3: return
	var outline := PackedVector2Array()
	for point in points: outline.append(center + point * scale_factor)
	outline.append(outline[0])
	draw_polyline(outline, Color(color, 0.2), 1.2, true)


func _draw_marker(point: Vector2, row: Dictionary) -> void:
	draw_circle(point, 6, FOCUS)
	if int(row.number) == selected_number: draw_arc(point, 10, 0, TAU, 24, Color.WHITE, 2, true)
	_number(point + Vector2(9, -9), int(row.number), FOCUS)


func _draw_cue(center: Vector2, radius: float, row: Dictionary) -> void:
	var bearing := (Reader.facing_index(sample.pose.facing) + int(row.sector)) % 8
	var angle := bearing * PI / 4.0 - PI / 2.0
	var near: bool = row.band == "Near"
	var inner := 0.0 if near else radius * 0.5
	var outer := radius * 0.5 if near else radius
	var wedge := PackedVector2Array()
	for step in 13: wedge.append(center + Vector2.from_angle(angle - PI / 8.0 + PI / 4.0 * step / 12.0) * outer)
	for step in 13: wedge.append(center + Vector2.from_angle(angle + PI / 8.0 - PI / 4.0 * step / 12.0) * inner)
	draw_colored_polygon(wedge, Color(PERIPHERAL, 0.12))
	wedge.append(wedge[0])
	draw_polyline(wedge, PERIPHERAL if int(row.number) != selected_number else Color.WHITE, 1.5, true)
	_number(center + Vector2.from_angle(angle) * (outer + 16), int(row.number), PERIPHERAL)


func _number(point: Vector2, number: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, point + Vector2(1, 1), str(number), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
	draw_string(ThemeDB.fallback_font, point, str(number), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
