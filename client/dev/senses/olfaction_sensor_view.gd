extends Control

# The nose's own picture at the sensor's resolution: what each of its sixteen zones
# measured, then the scent found there. Dark ground is unknown, never "no scent".
const Readings = preload("res://dev/senses/olfaction_readings.gd")
const STRENGTH_ALPHA := {"None": 0.0, "Weak": 0.22, "Medium": 0.48, "Strong": 0.78}
const BLIND_RADIUS_TILES := 0.75
const UNKNOWN := Color("101e2c")
const MEASURED := Color("18293a")
const STRIPE := Color("243a50")
const OUTLINE := Color("2b4056")
const REACH := Color("35506a")
const LEGEND_FONT_SIZE := 11
const LEGEND_LINE_HEIGHT := 15.0
const MIN_SUPPORTED_WIDTH := 400.0
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


func coverage_counts() -> Dictionary:
	return Readings.coverage_counts(sample)


# The coverage word of one zone; a sample recorded without coverage says so.
func zone_coverage(zone: int) -> String:
	var coverage = sample.get("coverage")
	if not coverage is Array or coverage.size() != 16: return "Unrecorded"
	return str(coverage[zone])


func legend_lines() -> Array[String]:
	var range_units := float(sample.get("profile", {}).get("range", 0))
	return ["Reach %.0f world units = outer ring · %s" % [range_units, Readings.coverage_summary(sample)],
		"dark = not measured, unknown · inner disc = own body cells, never measured · faint = measured, no scent · striped = partly measured (solid or off-map ground inside)",
		"wedge = scent in a measured zone (weak / medium / strong) · arrow = coarse bearing, never a position"]


# Every legend line must fit the control; the driver checks this at the minimum window size.
func legend_fits() -> bool:
	var font := ThemeDB.fallback_font
	for line in _wrapped_legend(font):
		if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE).x > _legend_width() - 20: return false
	return true


# A hidden page has no layout yet; the legend then wraps at the supported minimum width.
func _legend_width() -> float:
	return size.x if size.x >= MIN_SUPPORTED_WIDTH else MIN_SUPPORTED_WIDTH


# Where the picture sits: the legend takes the bottom, the compass ring the rest.
# Probes read this so their pixel checks follow the same geometry as the drawing.
func plot_geometry() -> Dictionary:
	var legend := _wrapped_legend(ThemeDB.fallback_font)
	var legend_height := legend.size() * LEGEND_LINE_HEIGHT + 12
	var plot := Rect2(Vector2(0, 24), Vector2(size.x, size.y - legend_height - 24))
	var radius := minf(plot.size.x, plot.size.y) * 0.42
	var range_units := maxf(float(sample.get("profile", {}).get("range", 1)), 1.0)
	return {"center": plot.get_center(), "radius": radius, "blind": clampf(BLIND_RADIUS_TILES * tile_size / range_units, 0.0, 1.0) * radius,
		"legend": legend, "legend_height": legend_height}


func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	if sample.is_empty() or sample.get("status") != "Sampled":
		draw_string(font, Vector2(20, 40), "No current nose sample.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a2b3c8"))
		return
	var geometry := plot_geometry()
	var legend: Array[String] = geometry.legend
	var legend_height: float = geometry.legend_height
	var center: Vector2 = geometry.center
	var radius: float = geometry.radius
	var blind: float = geometry.blind
	_draw_coverage(center, radius, blind)
	for row: Dictionary in rows:
		if show_classes.get(row.class, true): _draw_zones(center, radius, blind, row)
	for row: Dictionary in rows:
		if show_classes.get(row.class, true) and row.bearing_valid: _draw_bearing(center, radius, row)
	_draw_reach(center, radius, blind)
	draw_circle(center, 6, Color.WHITE)
	draw_string(font, center + Vector2(10, 20), "NOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	_draw_compass(center, radius)
	_draw_legend(legend, font, size.y - legend_height + LEGEND_LINE_HEIGHT)


func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UNKNOWN
	style.set_corner_radius_all(8)
	return style


# Inner and outer radius of one zone's band; the body's blind disc eats the inside.
func _band_radii(zone: int, radius: float, blind: float) -> Vector2:
	if zone % 2 == 1: return Vector2(maxf(radius * 0.5, blind), radius)
	return Vector2(blind, radius * 0.5)


func _sector_angle(zone: int) -> float:
	return (zone / 2) * PI / 4.0 - PI / 2.0


func _wedge(center: Vector2, inner: float, outer: float, zone: int) -> PackedVector2Array:
	var angle := _sector_angle(zone)
	var wedge := PackedVector2Array()
	for step in 13: wedge.append(center + Vector2.from_angle(angle - PI / 8.0 + PI / 4.0 * step / 12.0) * outer)
	for step in 13: wedge.append(center + Vector2.from_angle(angle + PI / 8.0 - PI / 4.0 * step / 12.0) * inner)
	return wedge


# Only measured ground gets a fill: solid faint for fully measured zones, stripes for
# partly measured ones. Unmeasured zones stay as dark as the background.
func _draw_coverage(center: Vector2, radius: float, blind: float) -> void:
	for zone in 16:
		var word := zone_coverage(zone)
		var band := _band_radii(zone, radius, blind)
		if band.y <= band.x or word not in ["Sampled", "Partial"]: continue
		var wedge := _wedge(center, band.x, band.y, zone)
		if word == "Sampled":
			draw_colored_polygon(wedge, MEASURED)
		else:
			var angle := _sector_angle(zone)
			var ring := band.x + 3.0
			while ring < band.y:
				draw_arc(center, ring, angle - PI / 8.0, angle + PI / 8.0, 10, STRIPE, 2.0, true)
				ring += 6.0
		wedge.append(wedge[0])
		draw_polyline(wedge, OUTLINE, 1.0, true)


func _draw_zones(center: Vector2, radius: float, blind: float, row: Dictionary) -> void:
	var color := Readings.color_of(row.class)
	for zone in 16:
		var band: String = row.zones[zone]
		var radii := _band_radii(zone, radius, blind)
		if band == "None" or radii.y <= radii.x: continue
		var wedge := _wedge(center, radii.x, radii.y, zone)
		draw_colored_polygon(wedge, Color(color, STRENGTH_ALPHA[band]))
		if int(row.number) == selected_number:
			wedge.append(wedge[0])
			draw_polyline(wedge, Color.WHITE, 1.2, true)


# The sensor's reach as an outline only: reach is not coverage.
func _draw_reach(center: Vector2, radius: float, blind: float) -> void:
	draw_arc(center, radius, 0, TAU, 96, REACH, 1.2, true)
	if blind < radius * 0.5: draw_arc(center, radius * 0.5, 0, TAU, 64, OUTLINE, 1.0, true)
	if blind > 0 and blind < radius: draw_arc(center, blind, 0, TAU, 32, OUTLINE, 1.0, true)
	draw_string(ThemeDB.fallback_font, center + Vector2(-14, -radius - 6), "reach", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("7f93aa"))


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
	draw_string(font, Vector2(center.x - 4, center.y - radius - 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(center.x + radius + 8, center.y + 5), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(center.x - 4, center.y + radius + 18), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(center.x - radius - 18, center.y + 5), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var legend_y := 24
	var legend_x := size.x - 134
	for scent_class: String in Readings.CLASS_COLORS:
		draw_rect(Rect2(Vector2(legend_x, legend_y - 10), Vector2(12, 12)), Readings.color_of(scent_class))
		draw_string(font, Vector2(legend_x + 18, legend_y), "%s scent" % scent_class, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c8d3df"))
		legend_y += 18
	draw_string(font, Vector2(legend_x, legend_y), "weak · medium · strong", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8ea1b7"))
	var swatch_x := legend_x
	for band: String in ["Weak", "Medium", "Strong"]:
		draw_rect(Rect2(Vector2(swatch_x, legend_y + 6), Vector2(20, 8)), Color(Color.WHITE, STRENGTH_ALPHA[band]))
		swatch_x += 24


# Greedy wrap on the " · " separators so the legend stays readable at narrow widths.
func _wrapped_legend(font: Font) -> Array[String]:
	var wrapped: Array[String] = []
	var limit := _legend_width() - 20
	for line in legend_lines():
		var current := ""
		for part in line.split(" · "):
			var candidate := part if current.is_empty() else current + " · " + part
			if not current.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE).x > limit:
				wrapped.append(current)
				current = part
			else:
				current = candidate
		wrapped.append(current)
	return wrapped


func _draw_legend(lines: Array[String], font: Font, first_baseline: float) -> void:
	var swatches := {"dark": UNKNOWN, "faint": MEASURED, "striped": STRIPE}
	var y := first_baseline
	for line in lines:
		var x := 10.0
		for key: String in swatches:
			if line.begins_with(key):
				draw_rect(Rect2(Vector2(x, y - 9), Vector2(10, 10)), swatches[key])
				draw_rect(Rect2(Vector2(x, y - 9), Vector2(10, 10)), OUTLINE, false, 1.0)
				x += 14
				break
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE, Color("9dabbc"))
		y += LEGEND_LINE_HEIGHT
