extends Control

# The nose's own picture at the sensor's resolution: what each of its sixteen zones
# measured, then the scent found there. Dark ground is unknown, never "no scent".
# The shared radar frames it; this view keeps the coverage and reading meanings.
const Readings = preload("res://dev/senses/olfaction_readings.gd")
const Radar = preload("res://dev/ui/sensor_radar.gd")
const Style = preload("res://dev/ui/dev_ui_style.gd")
const STRENGTH_ALPHA := {"None": 0.0, "Weak": 0.22, "Medium": 0.48, "Strong": 0.78}
const BLIND_RADIUS_TILES := 0.75
const UNKNOWN := Color("101e2c")
const MEASURED := Color("18293a")
const STRIPE := Color("243a50")
const OUTLINE := Color("2b4056")
var sample: Dictionary = {}
var rows: Array[Dictionary] = []
var tile_size := 32.0
var selected_number := 0
var show_classes := {"Human": true, "Orc": true}
var radar: Radar
var _plot: Control


func _init() -> void:
	radar = Radar.new()
	radar.self_label = "NOSE"
	radar.outer_ring_label = "reach"
	radar.empty_text = "No current nose sample."
	radar.legend_swatches = {"dark": UNKNOWN, "faint": MEASURED, "striped": STRIPE}
	radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(radar)
	_plot = PlotLayer.new()
	_plot.view = self
	radar.add_layer(_plot)


func set_sample(record: Dictionary, readings: Array[Dictionary], arena_tile_size: float) -> void:
	sample = record.get("olfaction", {})
	rows = readings
	tile_size = arena_tile_size
	var sampled: bool = sample.get("status") == "Sampled"
	radar.range_units = maxf(float(sample.get("profile", {}).get("range", 1)), 1.0)
	radar.empty_text = "" if sampled else "No current nose sample."
	radar.show_self = sampled
	radar.guide_rings = _guide_rings()
	radar.legend_lines = legend_lines()
	refresh()


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
	return radar.legend_fits()


# Where the picture sits, plus the body's blind disc in pixels. Probes read this so
# their pixel checks follow the same geometry as the drawing.
func plot_geometry() -> Dictionary:
	var geometry := radar.plot_geometry()
	geometry.blind = _blind_fraction() * geometry.radius
	return geometry


func refresh() -> void:
	radar.redraw_layers()
	queue_redraw()


func _blind_fraction() -> float:
	return clampf(BLIND_RADIUS_TILES * tile_size / radar.range_units, 0.0, 1.0)


# The reach ring, the half ring when the body does not swallow it, and the blind disc edge.
func _guide_rings() -> Array[float]:
	var rings: Array[float] = [1.0]
	var blind := _blind_fraction()
	if blind < 0.5: rings.append(0.5)
	if blind > 0 and blind < 1: rings.append(blind)
	return rings


# Inner and outer radius of one zone's band; the body's blind disc eats the inside.
func _band_radii(zone: int, radius: float, blind: float) -> Vector2:
	if zone % 2 == 1: return Vector2(maxf(radius * 0.5, blind), radius)
	return Vector2(blind, radius * 0.5)


# Nose zones point in world directions: they never turn with the body's facing.
func sector_angle(zone: int) -> float:
	return Style.heading_angle(zone / 2)


func _draw_plot(canvas: CanvasItem) -> void:
	if sample.is_empty() or sample.get("status") != "Sampled": return
	var geometry := plot_geometry()
	var center: Vector2 = geometry.center
	var radius: float = geometry.radius
	var blind: float = geometry.blind
	_draw_coverage(canvas, center, radius, blind)
	for row: Dictionary in rows:
		if show_classes.get(row.class, true): _draw_zones(canvas, center, radius, blind, row)
	for row: Dictionary in rows:
		if show_classes.get(row.class, true) and row.bearing_valid: _draw_bearing(canvas, center, radius, row)
	_draw_class_legend(canvas)


# Only measured ground gets a fill: solid faint for fully measured zones, stripes for
# partly measured ones. Unmeasured zones stay as dark as the background.
func _draw_coverage(canvas: CanvasItem, center: Vector2, radius: float, blind: float) -> void:
	for zone in 16:
		var word := zone_coverage(zone)
		var band := _band_radii(zone, radius, blind)
		if band.y <= band.x or word not in ["Sampled", "Partial"]: continue
		var wedge := Style.wedge(center, band.x, band.y, sector_angle(zone))
		if word == "Sampled":
			canvas.draw_colored_polygon(wedge, MEASURED)
		else:
			var angle := sector_angle(zone)
			var ring := band.x + 3.0
			while ring < band.y:
				canvas.draw_arc(center, ring, angle - PI / 8.0, angle + PI / 8.0, 10, STRIPE, 2.0, true)
				ring += 6.0
		wedge.append(wedge[0])
		canvas.draw_polyline(wedge, OUTLINE, 1.0, true)


func _draw_zones(canvas: CanvasItem, center: Vector2, radius: float, blind: float, row: Dictionary) -> void:
	var color := Readings.color_of(row.class)
	for zone in 16:
		var band: String = row.zones[zone]
		var radii := _band_radii(zone, radius, blind)
		if band == "None" or radii.y <= radii.x: continue
		var wedge := Style.wedge(center, radii.x, radii.y, sector_angle(zone))
		canvas.draw_colored_polygon(wedge, Color(color, STRENGTH_ALPHA[band]))
		if int(row.number) == selected_number:
			wedge.append(wedge[0])
			canvas.draw_polyline(wedge, Style.SELECTED, 1.2, true)


func _draw_bearing(canvas: CanvasItem, center: Vector2, radius: float, row: Dictionary) -> void:
	var direction := Vector2.from_angle(Style.heading_angle(Readings.FACING_NAMES.find(row.direction)))
	var color := Readings.color_of(row.class)
	var tip := center + direction * radius * 0.9
	canvas.draw_line(center, tip, color, 2.5, true)
	canvas.draw_line(tip, tip - direction.rotated(0.5) * 10, color, 2.5, true)
	canvas.draw_line(tip, tip - direction.rotated(-0.5) * 10, color, 2.5, true)
	Style.draw_text(canvas, tip + Vector2(6, -14), "%d · %s ≈ %s" % [int(row.number), row.class, row.direction], 12, color)


func _draw_class_legend(canvas: CanvasItem) -> void:
	var legend_y := 24
	var legend_x := size.x - 134
	for scent_class: String in Readings.CLASS_COLORS:
		canvas.draw_rect(Rect2(Vector2(legend_x, legend_y - 10), Vector2(12, 12)), Readings.color_of(scent_class))
		Style.draw_text(canvas, Vector2(legend_x + 18, legend_y), "%s scent" % scent_class, 12, Style.TEXT)
		legend_y += 18
	Style.draw_text(canvas, Vector2(legend_x, legend_y), "weak · medium · strong", 11, Style.MUTED)
	var swatch_x := legend_x
	for band: String in ["Weak", "Medium", "Strong"]:
		canvas.draw_rect(Rect2(Vector2(swatch_x, legend_y + 6), Vector2(20, 8)), Color(Color.WHITE, STRENGTH_ALPHA[band]))
		swatch_x += 24


# The drawing surface inside the radar; the view keeps the data and the meaning.
class PlotLayer extends Control:
	var view: Control

	func _draw() -> void:
		view._draw_plot(self)
