extends Control

# The nose's own picture: sixteen sampled zones per scent class, drawn exactly at the
# sensor's resolution. Nothing here invents a tile trail or a source position.
const Readings = preload("res://dev/senses/olfaction_readings.gd")
const STRENGTH_ALPHA := {"None": 0.0, "Weak": 0.22, "Medium": 0.48, "Strong": 0.78}
const BLIND_RADIUS_TILES := 0.75
const RANGE_FALLOFF := 0.6
var sample: Dictionary = {}
var rows: Array[Dictionary] = []
var tile_size := 32.0
var selected_number := 0
var show_classes := {"Human": true, "Orc": true}


func set_sample(record: Dictionary, readings: Array[Dictionary], arena_tile_size: float) -> void:
	sample = record.get("olfaction", {})
	rows = readings
	tile_size = arena_tile_size
	queue_redraw()


func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	if sample.is_empty() or sample.get("status") != "Sampled":
		draw_string(font, Vector2(20, 40), "No current nose sample.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a2b3c8"))
		return
	var center := size / 2.0
	var radius := minf(size.x, size.y - 40) * 0.42
	var range_units := float(sample.profile.range)
	var blind := clampf(BLIND_RADIUS_TILES * tile_size / range_units, 0.0, 0.5) * radius
	_draw_sampled_area(center, radius, blind)
	for row: Dictionary in rows:
		if not show_classes.get(row.class, true): continue
		_draw_zones(center, radius, blind, row)
	for row: Dictionary in rows:
		if show_classes.get(row.class, true) and row.bearing_valid: _draw_bearing(center, radius, row)
	draw_circle(center, 6, Color.WHITE)
	draw_string(font, center + Vector2(10, 20), "NOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	_draw_compass(center, radius)
	draw_string(font, Vector2(14, size.y - 16), "Range %.0f units · dark = not sampled · faint ring = sampled, no scent · wedge = sampled zone" % range_units, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("9dabbc"))


func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101e2c")
	style.set_corner_radius_all(8)
	return style


# Everything the nose reached, as a faint ring; the blind body disc stays dark.
func _draw_sampled_area(center: Vector2, radius: float, blind: float) -> void:
	draw_circle(center, radius, Color("18293a"))
	draw_circle(center, blind, Color("0c1420"))
	draw_arc(center, radius, 0, TAU, 96, Color("35506a"), 1.2, true)
	draw_arc(center, radius * 0.5, 0, TAU, 64, Color("2b4056"), 1.0, true)
	draw_arc(center, blind, 0, TAU, 32, Color("2b4056"), 1.0, true)
	for sector in 8:
		var angle := sector * PI / 4.0 - PI / 2.0 - PI / 8.0
		draw_line(center + Vector2.from_angle(angle) * blind, center + Vector2.from_angle(angle) * radius, Color("22364a"), 1.0, true)
	draw_string(ThemeDB.fallback_font, center + Vector2(-38, -radius - 6), "sampled area", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("7f93aa"))


func _draw_zones(center: Vector2, radius: float, blind: float, row: Dictionary) -> void:
	var color := Readings.color_of(row.class)
	for zone in 16:
		var band: String = row.zones[zone]
		if band == "None": continue
		var sector := zone / 2
		var far := zone % 2 == 1
		var inner := radius * 0.5 if far else blind
		var outer := radius if far else radius * 0.5
		var angle := sector * PI / 4.0 - PI / 2.0
		var wedge := PackedVector2Array()
		for step in 13: wedge.append(center + Vector2.from_angle(angle - PI / 8.0 + PI / 4.0 * step / 12.0) * outer)
		for step in 13: wedge.append(center + Vector2.from_angle(angle + PI / 8.0 - PI / 4.0 * step / 12.0) * inner)
		draw_colored_polygon(wedge, Color(color, STRENGTH_ALPHA[band]))
		if int(row.number) == selected_number:
			wedge.append(wedge[0])
			draw_polyline(wedge, Color.WHITE, 1.2, true)


func _draw_bearing(center: Vector2, radius: float, row: Dictionary) -> void:
	var facing := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"].find(row.direction)
	var direction := Vector2.from_angle(facing * PI / 4.0 - PI / 2.0)
	var color := Readings.color_of(row.class)
	var tip := center + direction * radius * 0.9
	draw_line(center, tip, color, 2.5, true)
	draw_line(tip, tip - direction.rotated(0.5) * 10, color, 2.5, true)
	draw_line(tip, tip - direction.rotated(-0.5) * 10, color, 2.5, true)
	var label := "%d · %s ≈ %s" % [int(row.number), row.class, row.direction]
	draw_string(ThemeDB.fallback_font, tip + Vector2(6, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _draw_compass(center: Vector2, radius: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(center.x - 4, 22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(size.x - 24, center.y - 8), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(center.x - 4, size.y - 36), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(14, center.y - 8), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var legend_y := 24
	for scent_class: String in Readings.CLASS_COLORS:
		draw_rect(Rect2(Vector2(size.x - 118, legend_y - 10), Vector2(12, 12)), Readings.color_of(scent_class))
		draw_string(font, Vector2(size.x - 100, legend_y), "%s scent" % scent_class, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c8d3df"))
		legend_y += 18
	draw_string(font, Vector2(size.x - 118, legend_y), "weak · medium · strong", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8ea1b7"))
	var swatch_x := size.x - 118
	for band: String in ["Weak", "Medium", "Strong"]:
		draw_rect(Rect2(Vector2(swatch_x, legend_y + 6), Vector2(20, 8)), Color(Color.WHITE, STRENGTH_ALPHA[band]))
		swatch_x += 24
