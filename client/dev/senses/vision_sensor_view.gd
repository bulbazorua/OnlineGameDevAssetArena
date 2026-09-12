extends Control

# The eye's local picture at the sensor's scale: the sampled focus and side fields,
# focused sightings at their positions and approximate cue wedges. The shared
# radar frames it; this view keeps the meaning of every mark and its own data.
const Geometry = preload("res://dev/vision_cone_geometry.gd")
const Reader = preload("res://dev/ai/trace_reader.gd")
const Radar = preload("res://dev/ui/sensor_radar.gd")
const Style = preload("res://dev/ui/dev_ui_style.gd")
const FOCUS := Color("62d9ff")
const PERIPHERAL := Color("ffb454")
var sample: Dictionary = {}
var rows: Array[Dictionary] = []
var shape: Dictionary = {}
var selected_number := 0
var show_focus := true
var show_periphery := true
var radar: Radar
var _plot: Control


func _init() -> void:
	radar = Radar.new()
	radar.outer_ring_label = "range"
	radar.empty_text = "No current vision sample."
	radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(radar)
	_plot = PlotLayer.new()
	_plot.view = self
	radar.add_layer(_plot)


func set_sample(record: Dictionary, readings: Array[Dictionary]) -> void:
	sample = record.get("vision", {})
	rows = readings
	shape = {}
	if sample.get("status") == "Sampled": shape = Geometry.build(sample, record.sight_fan)
	radar.range_units = maxf(float(sample.get("profile", {}).get("range", 1)), 1.0)
	radar.empty_text = "" if not shape.is_empty() else "No current vision sample."
	radar.show_self = not shape.is_empty()
	radar.self_facing = Vector2.ZERO if shape.is_empty() else Vector2.from_angle(Style.heading_angle(Reader.facing_index(sample.pose.facing)))
	radar.legend_lines = legend_lines()
	refresh()


func legend_lines() -> Array[String]:
	return ["Range %.1f world units = outer ring · blank = unknown" % float(sample.get("profile", {}).get("range", 0)),
		"dot = focused sighting at its observed position · wedge = approximate cue in a near / far band, never a position"]


func legend_fits() -> bool:
	return radar.legend_fits()


func plot_geometry() -> Dictionary:
	return radar.plot_geometry()


func refresh() -> void:
	radar.redraw_layers()
	queue_redraw()


# Screen angle of a cue: sectors are counted from the sampled facing, so they turn with the eye.
func cue_angle(row: Dictionary) -> float:
	return Style.heading_angle((Reader.facing_index(sample.pose.facing) + int(row.sector)) % 8)


func _draw_plot(canvas: CanvasItem) -> void:
	if shape.is_empty(): return
	var geometry := plot_geometry()
	var center: Vector2 = geometry.center
	var radius: float = geometry.radius
	var scale_factor := radar.pixels_per_unit()
	if show_focus: _draw_field(canvas, shape.focus, center, scale_factor, FOCUS)
	if show_periphery:
		_draw_field(canvas, shape.left, center, scale_factor, PERIPHERAL)
		_draw_field(canvas, shape.right, center, scale_factor, PERIPHERAL)
	for row: Dictionary in rows:
		if row.quality == "Focused" and show_focus:
			var point := Vector2(row.position[0], row.position[1])
			_draw_marker(canvas, center + (point - shape.center) * scale_factor, row)
		elif row.quality == "Peripheral" and show_periphery:
			_draw_cue(canvas, center, radius, row)


func _draw_field(canvas: CanvasItem, points: PackedVector2Array, center: Vector2, scale_factor: float, color: Color) -> void:
	if points.size() < 3: return
	var outline := PackedVector2Array()
	for point in points: outline.append(center + point * scale_factor)
	outline.append(outline[0])
	canvas.draw_polyline(outline, Color(color, 0.2), 1.2, true)


func _draw_marker(canvas: CanvasItem, point: Vector2, row: Dictionary) -> void:
	canvas.draw_circle(point, 6, FOCUS)
	if int(row.number) == selected_number: Style.draw_selection_ring(canvas, point, 10)
	Style.draw_number(canvas, point + Vector2(9, -9), int(row.number), FOCUS)


func _draw_cue(canvas: CanvasItem, center: Vector2, radius: float, row: Dictionary) -> void:
	var angle := cue_angle(row)
	var near: bool = row.band == "Near"
	var inner := 0.0 if near else radius * 0.5
	var outer := radius * 0.5 if near else radius
	var wedge := Style.wedge(center, inner, outer, angle)
	canvas.draw_colored_polygon(wedge, Color(PERIPHERAL, 0.12))
	wedge.append(wedge[0])
	canvas.draw_polyline(wedge, PERIPHERAL if int(row.number) != selected_number else Style.SELECTED, 1.5, true)
	Style.draw_number(canvas, center + Vector2.from_angle(angle) * (outer - 18) - Vector2(5, -6), int(row.number), PERIPHERAL)


# The drawing surface inside the radar; the view keeps the data and the meaning.
class PlotLayer extends Control:
	var view: Control

	func _draw() -> void:
		view._draw_plot(self)
