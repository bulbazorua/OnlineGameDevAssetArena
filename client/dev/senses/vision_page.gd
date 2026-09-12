extends "res://dev/senses/sense_page.gd"

# The Vision page: current sightings and cues from one delivered eye sample, on the
# shared arena frame and on the eye's local radar. Rows come only from that sample.
const Readings = preload("res://dev/senses/vision_readings.gd")
const View = preload("res://dev/senses/vision_sensor_view.gd")
const Layer = preload("res://dev/senses/vision_arena_layer.gd")
const Overview = preload("res://dev/ui/arena_overview.gd")
const READOUT_HINT := "Hover the arena for world coordinates · the outline is a developer reference, not what the eye saw"
var content: RefCounted
var record: Dictionary = {}
var readings: Array[Dictionary] = []
var selected_reference := ""
var view: View
var overview: Overview
var layer: Layer


func configure(game_content: RefCounted) -> void:
	content = game_content
	build_layout("CURRENT DETECTIONS", ["Reading", "Observed", "Position / direction"], [110, 0, 0])
	overview = Overview.new()
	overview.title = "ARENA OVERVIEW · this eye's delivered sample only"
	overview.legend_lines = ["fan = sight sampled at the pose: blue focus, amber sides",
		"dot = sighting where seen · wedge = cue, not a position",
		"outline = developer reference, not remembered terrain"]
	layer = Layer.new()
	overview.add_layer(layer)
	overview.pointer_moved.connect(_pointer_moved)
	overview.pointer_left.connect(func(): readout.text = READOUT_HINT)
	set_view(ARENA_VIEW, overview)
	view = View.new()
	set_view(LOCAL_VIEW, view)
	add_filter("Focused", View.FOCUS, func(value: bool): set_filter("Focused", value))
	add_filter("Peripheral", View.PERIPHERAL, func(value: bool): set_filter("Peripheral", value))
	table.item_selected.connect(select_reading)
	summary.text = "Self · waiting for a sampled pose"
	note.text = "Waiting for vision"
	details.text = "Select a current detection for its details."
	readout.text = READOUT_HINT


func set_arena(definition: Variant) -> void:
	overview.set_arena(definition)


func set_sample(next_record: Dictionary, rows: Array[Dictionary]) -> void:
	record = next_record
	readings = rows
	view.set_sample(record, readings)
	layer.set_sample(record, readings, view.shape)
	rebuild_rows()


# The eye's freshness, decided by the window's clock; both pictures dim together.
func set_status(status: String) -> void:
	var live := status == "LIVE"
	view.modulate.a = 1.0 if live else 0.35
	layer.modulate.a = 1.0 if live else 0.35
	var sample: Dictionary = record.get("vision", {})
	overview.set_badge(status if sample.get("status") != "Sampled" else "%s · sample #%d" % [status, int(sample.sample_id)], live)


func refresh_text(feed_error: String, origin_unix_us: int) -> void:
	if record.is_empty():
		summary.text = "Self · waiting for an active creature"
		timing.text = feed_error if not feed_error.is_empty() else "No current vision sample"
		return
	var sample: Dictionary = record.vision
	if sample.status != "Sampled":
		summary.text = "Self · vision " + sample.status.replace("_", " ").to_lower()
		timing.text = "No sampled pose available"
		return
	summary.text = "Self %s · facing %s · focus %.1f° / total %.1f° · %.1f world units" % [coordinates(sample.pose.position), Readings.direction(sample.pose.facing), sample.profile.focused_fov_degrees, sample.profile.overall_fov_degrees, sample.profile.range]
	var age := sample_age_text(int(record.delivered_us), origin_unix_us, int(sample.sample_tick), int(sample.delivered_tick))
	timing.text = "Sample #%d · source tick %d → delivered tick %d · %s" % [int(sample.sample_id), int(sample.sample_tick), int(sample.delivered_tick), age]


func rebuild_rows() -> void:
	table.clear()
	var root := table.create_item()
	view.selected_number = 0
	layer.selected_number = 0
	details.text = "Select a current detection for its details."
	var sample: Dictionary = record.get("vision", {})
	note.text = "%d focused · %d peripheral" % [int(sample.get("focused_count", 0)), int(sample.get("cue_count", 0))]
	if readings.is_empty(): note.text = "Nothing detected in this sample. Unseen does not mean absent."
	if sample.get("status") != "Sampled": note.text = "No current vision sample."
	for row: Dictionary in readings:
		var item := table.create_item(root)
		item.set_metadata(0, row)
		item.set_text(0, "%d · %s" % [int(row.number), row.quality])
		item.set_custom_color(0, View.FOCUS if row.quality == "Focused" else View.PERIPHERAL)
		item.set_text(1, _subject_name(row) + " · " + row.locomotion.to_lower() if row.quality == "Focused" else "Unknown presence")
		item.set_text(2, coordinates(row.position) if row.quality == "Focused" else "≈ %s · %s" % [row.direction, row.band.to_lower()])
		for column in 3: item.set_tooltip_text(column, reading_details(row))
		if _reading_reference(row) == selected_reference:
			item.select(0)
			_apply_selection(row)
	if view.selected_number == 0: selected_reference = ""
	refresh_views()


func select_reading() -> void:
	var item := table.get_selected()
	if item == null: return
	var row: Dictionary = item.get_metadata(0)
	selected_reference = _reading_reference(row)
	_apply_selection(row)
	refresh_views()


func _apply_selection(row: Dictionary) -> void:
	view.selected_number = int(row.number)
	layer.selected_number = int(row.number)
	details.text = reading_details(row)


func set_filter(category: String, enabled: bool) -> void:
	if category == "Focused":
		view.show_focus = enabled
		layer.show_focus = enabled
	elif category == "Peripheral":
		view.show_periphery = enabled
		layer.show_periphery = enabled
	refresh_views()


func refresh_views() -> void:
	view.refresh()
	layer.queue_redraw()


func _subject_name(row: Dictionary) -> String:
	var definition = content.by_id.get(int(row.appearance_id)) if row.kind == "Creature" else null
	var title := str(definition.display_name) if definition != null else str(row.kind)
	return "%s #%d" % [title, int(row.subject)]


func reading_details(row: Dictionary) -> String:
	if row.quality == "Peripheral":
		return "Peripheral cue #%d\nApproximate direction %s · %s range band\nIdentity, exact position and action are unknown." % [int(row.observation_id), row.direction, row.band.to_lower()]
	return "%s · focused observation #%d\nPosition %s · distance %.2f world units\nFacing %s · observed state %s" % [_subject_name(row), int(row.observation_id), coordinates(row.position), float(row.distance), Readings.direction(row.facing), row.locomotion.to_lower()]


func _reading_reference(row: Dictionary) -> String:
	return "focused:%d" % int(row.subject) if row.quality == "Focused" else "cue:%d:%s" % [int(row.sector), row.band]


func _pointer_moved(world: Vector2) -> void:
	if not overview.contains_world(world):
		readout.text = READOUT_HINT
		return
	var cell := overview.cell_of(world)
	readout.text = "Pointer · world (%.0f, %.0f) · tile (%d, %d) · sampled positions only, no live truth" % [world.x, world.y, cell.x, cell.y]
