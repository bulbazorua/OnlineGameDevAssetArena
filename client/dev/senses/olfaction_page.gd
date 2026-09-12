extends "res://dev/senses/sense_page.gd"

# The Olfaction page: the nose's delivered readings on its local radar, and the
# host's published scent field on the shared arena frame. The two sources keep
# their own readers and clocks; a fresh field never makes an old nose look live.
const Readings = preload("res://dev/senses/olfaction_readings.gd")
const View = preload("res://dev/senses/olfaction_sensor_view.gd")
const Layer = preload("res://dev/senses/scent_field_layer.gd")
const Overview = preload("res://dev/ui/arena_overview.gd")
const FieldFeed = preload("res://dev/scent_feed.gd")
const FieldImage = preload("res://dev/scent_field_image.gd")
const READ_INTERVAL_MS := 100
const NO_CELL := Vector2i(-1, -1)
const READOUT_HINT := "Hover a field cell for its published levels and ages · click to pin one"
const UNITS_NOTE := "Level = published 0–255 of the saturation cap, not a creature reading. Age = whole seconds since the newest deposit, capped at 255. Zero = nothing published, not measured-empty ground."
var feed := FieldFeed.new()
var painter := FieldImage.new()
var record: Dictionary = {}
var readings: Array[Dictionary] = []
var selected_class := ""
var show_classes := {"Human": true, "Orc": true}
var field_status := "WAITING"
var field_reason := "no field received yet"
var selected_cell := NO_CELL
var hover_cell := NO_CELL
var read_us_max := 0
var polls := 0
var view: View
var overview: Overview
var layer: Layer
var _world: Dictionary = {}
var _definition: Variant
var _next_read_ms := 0
var _field_key := ""
var _matches := false


func configure() -> void:
	build_layout("CURRENT SCENT READINGS", ["Reading", "Strength", "Freshness", "Bearing"], [130, 0, 0, 0])
	overview = Overview.new()
	overview.title = "HOST SCENT FIELD · developer-only world data, not what this creature knows"
	overview.title_color = Style.PRIVILEGED
	overview.legend_lines = ["colour = scent class, never who left it · fixed level scale",
		"ring = this nose's sampled reach · zero = nothing published",
		"outline = catalog arena bounds, a developer reference"]
	layer = Layer.new()
	overview.add_layer(layer)
	overview.pointer_moved.connect(_pointer_moved)
	overview.pointer_left.connect(_pointer_left)
	overview.pointer_pressed.connect(_pointer_pressed)
	set_view(ARENA_VIEW, overview)
	view = View.new()
	set_view(LOCAL_VIEW, view)
	painter.floor_alpha = 0.18
	painter.max_alpha = 0.82
	for scent_class: String in Readings.CLASS_COLORS:
		add_filter(scent_class + " scent", Readings.color_of(scent_class), func(value: bool): set_class_filter(scent_class, value))
	table.item_selected.connect(select_reading)
	summary.text = "Nose · waiting for a sampled position"
	note.text = "Waiting for olfaction"
	details.text = "Select a current scent reading for its details."
	readout.text = READOUT_HINT


# A different arena means the match must be judged again before anything is drawn.
func set_arena(definition: Variant) -> void:
	_definition = definition
	if overview.set_arena(definition): refresh_field(Time.get_ticks_msec())


func set_sample(next_record: Dictionary, rows: Array[Dictionary], tile_size: float) -> void:
	record = next_record
	readings = rows
	view.set_sample(record, rows, tile_size)
	var nose: Dictionary = record.get("olfaction", {})
	if nose.get("status") == "Sampled": layer.set_nose(Vector2(nose.position[0], nose.position[1]), float(nose.profile.range), "NOSE · sample #%d" % int(nose.sample_id))
	else: layer.clear_nose()
	rebuild_rows()


# The nose sample's freshness, decided by the window's clock. The field has its own.
func set_status(status: String) -> void:
	var live := status == "LIVE"
	view.modulate.a = 1.0 if live else 0.35
	if layer.nose_live != live:
		layer.nose_live = live
		layer.queue_redraw()


func refresh_text(feed_error: String, origin_unix_us: int) -> void:
	if record.is_empty():
		summary.text = "Nose · waiting for an active creature"
		timing.text = feed_error if not feed_error.is_empty() else "No current nose sample"
		return
	var nose: Dictionary = record.olfaction
	var emitter: Dictionary = record.own_emitter
	var own := "own body gives off %s scent" % str(emitter.class).to_lower() if emitter.enabled else "own body gives off no scent"
	if nose.status != "Sampled":
		summary.text = "Nose · olfaction " + nose.status.replace("_", " ").to_lower() + " · " + own
		timing.text = "No sampled position available"
		return
	summary.text = "Nose at %s · reach %.0f world units · every %d ticks · %s · %s" % [coordinates(nose.position), float(nose.profile.range), int(nose.profile.sample_interval), "freshness estimated" if nose.profile.estimates_freshness else "freshness unknown", own]
	var age := sample_age_text(int(record.scent_delivered_us), origin_unix_us, int(nose.sample_tick), int(nose.delivered_tick))
	timing.text = "Nose sample #%d · source tick %d → delivered tick %d · %s" % [int(nose.sample_id), int(nose.sample_tick), int(nose.delivered_tick), age]


func rebuild_rows() -> void:
	table.clear()
	var root := table.create_item()
	view.selected_number = 0
	var nose: Dictionary = record.get("olfaction", {})
	note.text = "%d scent class%s detected" % [readings.size(), "" if readings.size() == 1 else "es"]
	if readings.is_empty(): note.text = "Sampled: no scent on the measured ground. Absence of smell is not proof of absence."
	if nose.get("status") != "Sampled": note.text = "No current nose sample."
	else: note.text += "\n" + Readings.coverage_summary(nose)
	for row: Dictionary in readings:
		var item := table.create_item(root)
		item.set_metadata(0, row)
		item.set_text(0, "%d · %s" % [int(row.number), row.class])
		item.set_custom_color(0, Readings.color_of(row.class))
		item.set_text(1, Readings.STRENGTH_WORDS[row.strength])
		item.set_text(2, Readings.FRESHNESS_WORDS[row.freshness])
		item.set_text(3, "≈ %s" % row.direction if row.bearing_valid else "no usable direction")
		for column in 4: item.set_tooltip_text(column, Readings.details(row))
		if row.class == selected_class:
			item.select(0)
			view.selected_number = int(row.number)
	if view.selected_number == 0: selected_class = ""
	view.refresh()
	_refresh_details()


func select_reading() -> void:
	var item := table.get_selected()
	if item == null: return
	var row: Dictionary = item.get_metadata(0)
	selected_class = row.class
	view.selected_number = int(row.number)
	view.refresh()
	_refresh_details()


func set_class_filter(scent_class: String, enabled: bool) -> void:
	show_classes[scent_class] = enabled
	view.show_classes[scent_class] = enabled
	view.refresh()
	_apply_field()
	_refresh_details()


# The host field has its own bounded reader and throttle; a world change reads at once.
func update_field(directory: String, run_id: String, fingerprint: String, world: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var changed := world != _world
	_world = world
	if now >= _next_read_ms or changed:
		_next_read_ms = now + READ_INTERVAL_MS
		polls += 1
		feed.read_snapshot(directory.path_join("scent.json"), run_id, fingerprint)
		read_us_max = maxi(read_us_max, feed.read_us)
	refresh_field(now)


func refresh_field(now: int) -> void:
	_matches = _field_matches_world()
	field_status = _status_of(now)
	var key := "" if not _matches else "%d/%d/%dx%d" % [int(feed.field.round_id), int(feed.field.map_id), int(feed.field.width), int(feed.field.height)]
	if key != _field_key:
		_field_key = key
		selected_cell = NO_CELL
		hover_cell = NO_CELL
		layer.selected_cell = NO_CELL
		layer.hover_cell = NO_CELL
		_refresh_details()
	_apply_field()
	var badge := field_status + (" · field tick %d" % int(feed.field.tick) if _matches else " · " + field_reason)
	overview.set_badge(badge, field_status == "LIVE")
	var alpha := 1.0 if field_status == "LIVE" else 0.4
	if not is_equal_approx(layer.field_alpha, alpha):
		layer.field_alpha = alpha
		layer.queue_redraw()
	_refresh_readout()


# Only a valid field for this world, this map and these dimensions is drawn at all.
func _field_matches_world() -> bool:
	var field: Dictionary = feed.field
	if not field.get("valid", false):
		field_reason = "no valid field published" if feed.error.is_empty() else feed.error
		return false
	if not _world.get("active", false):
		field_reason = "no active round"
		return false
	if int(field.round_id) != int(_world.round_id) or int(field.map_id) != int(_world.map_id):
		field_reason = "published field is for round %d, map %d" % [int(field.round_id), int(field.map_id)]
		return false
	if _definition == null:
		field_reason = "map %d is not in the catalog" % int(_world.map_id)
		return false
	if int(field.width) != int(_definition.width) or int(field.height) != int(_definition.height) or not is_equal_approx(float(field.tile_size), float(_definition.tile_size)):
		field_reason = "field %d×%d @ %.0f does not match arena %d×%d @ %d" % [int(field.width), int(field.height), float(field.tile_size), int(_definition.width), int(_definition.height), int(_definition.tile_size)]
		return false
	return true


# The field's own clock: judged from the time it is given so checks can move it.
func _status_of(now: int) -> String:
	if feed.received_ms < 0: return "WAITING"
	if now - feed.received_ms > 3000: return "DISCONNECTED"
	if now - feed.received_ms > FieldFeed.STALE_MS or not feed.error.is_empty(): return "STALE"
	if not _matches: return "WAITING"
	return "LIVE"


func _apply_field() -> void:
	if not _matches:
		painter.clear()
		layer.clear_field()
		return
	if painter.repaint(feed, show_classes):
		layer.set_field(painter.texture, int(feed.field.width), int(feed.field.height), float(feed.field.tile_size))
		if selected_cell != NO_CELL: _refresh_details()


# Published numbers for one cell, per class: quantized level and whole-second age.
func cell_report(cell: Vector2i) -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	if cell == NO_CELL or not _matches: return report
	for index in FieldFeed.CLASSES.size():
		var scent_class: String = FieldFeed.CLASSES[index]
		report.append({"class": scent_class, "level": feed.level(index, cell), "age": feed.age_seconds(index, cell), "shown": bool(show_classes.get(scent_class, true))})
	return report


func cell_line(cell: Vector2i) -> String:
	var parts: Array[String] = ["cell (%d, %d)" % [cell.x, cell.y]]
	for entry in cell_report(cell): parts.append("%s %s" % [entry.class, _level_words(entry)])
	if cell_report(cell).is_empty(): parts.append("no matching host field")
	return " · ".join(parts)


func cell_details(cell: Vector2i) -> String:
	if cell == NO_CELL: return "Click a field cell in the arena view to pin its published levels and ages."
	var tile: float = overview.tile_size
	var lines: Array[String] = ["Pinned cell (%d, %d) · world (%.0f, %.0f) to (%.0f, %.0f)" % [cell.x, cell.y, cell.x * tile, cell.y * tile, (cell.x + 1) * tile, (cell.y + 1) * tile]]
	var report := cell_report(cell)
	if report.is_empty(): lines.append("No matching host field for this cell right now.")
	for entry in report: lines.append("%s scent: %s%s" % [entry.class, _level_words(entry), "" if entry.shown else " (filtered out of the picture)"])
	lines.append(UNITS_NOTE)
	return "\n".join(lines)


func _level_words(entry: Dictionary) -> String:
	if int(entry.level) <= 0: return "no published level"
	return "level %d/255, %s" % [int(entry.level), _age_words(int(entry.age))]


# The publisher caps the age byte, so 255 means "at least this old", never exactly.
func _age_words(age: int) -> String:
	if age >= 255: return "newest deposit ≥ 255 s ago (capped)"
	return "newest deposit %d s ago" % age


func _pointer_moved(world: Vector2) -> void:
	var cell := overview.cell_of(world)
	if cell == hover_cell: return
	hover_cell = cell
	layer.hover_cell = cell
	layer.queue_redraw()
	_refresh_readout()


func _pointer_left() -> void:
	_pointer_moved(Vector2(-1, -1))


func _pointer_pressed(world: Vector2) -> void:
	var cell := overview.cell_of(world)
	selected_cell = NO_CELL if cell == selected_cell else cell
	layer.selected_cell = selected_cell
	layer.queue_redraw()
	_refresh_readout()
	_refresh_details()


func _refresh_readout() -> void:
	if hover_cell != NO_CELL: readout.text = "Hover " + cell_line(hover_cell)
	elif selected_cell != NO_CELL: readout.text = "Pinned " + cell_line(selected_cell)
	else: readout.text = READOUT_HINT


func _refresh_details() -> void:
	var text := "Select a current scent reading for its details."
	var item := table.get_selected()
	if item != null and view.selected_number > 0: text = Readings.details(item.get_metadata(0))
	details.text = text + "\n\n" + cell_details(selected_cell)


func field_debug() -> Dictionary:
	var field: Dictionary = feed.field
	return {"status": field_status, "reason": field_reason if not _matches else "", "matches": _matches, "published_us": feed.published_us,
		"field_tick": int(field.get("tick", -1)), "round_id": int(field.get("round_id", -1)), "width": int(field.get("width", 0)), "height": int(field.get("height", 0)),
		"painted_cells": painter.painted_cells, "rebuilds": painter.rebuilds, "polls": polls, "read_us_max": read_us_max, "error": feed.error,
		"selected_cell": [selected_cell.x, selected_cell.y], "show_classes": show_classes, "legend_fits": overview.legend_fits(), "view": view_mode}
