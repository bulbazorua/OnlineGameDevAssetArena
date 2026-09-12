extends Control

# Draws one delivered eye sample on the arena frame: the sampled sight fields at the
# sampled pose, focused sightings where they were observed, and peripheral cues as
# approximate wedges. Never a hidden or newer position.
const Style = preload("res://dev/ui/dev_ui_style.gd")
const Reader = preload("res://dev/ai/trace_reader.gd")
const FOCUS := Color("62d9ff")
const PERIPHERAL := Color("ffb454")
var sample: Dictionary = {}
var rows: Array[Dictionary] = []
var shape: Dictionary = {}
var show_focus := true
var show_periphery := true
var selected_number := 0
var frame: Control


func set_sample(record: Dictionary, readings: Array[Dictionary], sight_shape: Dictionary) -> void:
	sample = record.get("vision", {})
	rows = readings
	shape = sight_shape
	queue_redraw()


func cue_angle(row: Dictionary) -> float:
	return Style.heading_angle((Reader.facing_index(sample.pose.facing) + int(row.sector)) % 8)


func _draw() -> void:
	if frame == null or not frame.has_arena() or shape.is_empty(): return
	var origin: Vector2 = shape.center
	var anchor: Vector2 = frame.world_to_view(origin)
	var scale_factor: float = frame.scale_factor()
	if show_focus: _draw_field(shape.focus, anchor, scale_factor, FOCUS)
	if show_periphery:
		_draw_field(shape.left, anchor, scale_factor, PERIPHERAL)
		_draw_field(shape.right, anchor, scale_factor, PERIPHERAL)
	var reach: float = float(sample.profile.range) * scale_factor
	for row: Dictionary in rows:
		if row.quality == "Focused" and show_focus:
			_draw_marker(frame.world_to_view(Vector2(row.position[0], row.position[1])), row)
		elif row.quality == "Peripheral" and show_periphery:
			_draw_cue(anchor, reach, row)
	var facing := Vector2.from_angle(Style.heading_angle(Reader.facing_index(sample.pose.facing)))
	Style.draw_self_marker(self, anchor, "SELF", facing)


# Outline only: a wall-clipped sector can be concave or pinched, which a fill cannot triangulate.
func _draw_field(points: PackedVector2Array, anchor: Vector2, scale_factor: float, color: Color) -> void:
	if points.size() < 3: return
	var outline := PackedVector2Array()
	for point in points: outline.append(anchor + point * scale_factor)
	outline.append(outline[0])
	draw_polyline(outline, Color(color, 0.5), 1.2, true)


func _draw_marker(point: Vector2, row: Dictionary) -> void:
	draw_circle(point, 5, FOCUS)
	if int(row.number) == selected_number: Style.draw_selection_ring(self, point, 9)
	Style.draw_number(self, point + Vector2(8, -8), int(row.number), FOCUS, 13)


func _draw_cue(anchor: Vector2, reach: float, row: Dictionary) -> void:
	var angle := cue_angle(row)
	var near: bool = row.band == "Near"
	var wedge := Style.wedge(anchor, 0.0 if near else reach * 0.5, reach * 0.5 if near else reach, angle)
	draw_colored_polygon(wedge, Color(PERIPHERAL, 0.12))
	wedge.append(wedge[0])
	draw_polyline(wedge, PERIPHERAL if int(row.number) != selected_number else Style.SELECTED, 1.5, true)
	Style.draw_number(self, anchor + Vector2.from_angle(angle) * (reach * (0.5 if near else 1.0) + 10), int(row.number), PERIPHERAL, 13)
