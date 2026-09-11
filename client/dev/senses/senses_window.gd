extends Control

const Feed = preload("res://dev/sense_feed.gd")
const Readings = preload("res://dev/senses/vision_readings.gd")
const VisionView = preload("res://dev/senses/vision_sensor_view.gd")
const ScentReadings = preload("res://dev/senses/olfaction_readings.gd")
const ScentView = preload("res://dev/senses/olfaction_sensor_view.gd")
const Metrics = preload("res://dev/senses/display_metrics.gd")
const MemoryPanel = preload("res://dev/senses/exploration_memory_panel.gd")
const GameContent = preload("res://content/game_content.gd")
const OLFACTION_TAB := 2
const MEMORY_TAB := 5
const PAGES := ["Vision", "Hearing", "Olfaction", "Tactile / terrain", "Pain", "Exploration memory"]
var feed := Feed.new()
var content := GameContent.new()
var metrics := Metrics.new()
var scent_metrics := Metrics.new()
var owner_id := 0
var trace_dir := ""
var run_id := ""
var session_dir := ""
var slot := ""
var record: Dictionary = {}
var readings: Array[Dictionary] = []
var scent_readings: Array[Dictionary] = []
var selected_sense := 0
var live_status := "WAITING"
var _sample_key := ""
var _sample_received_ms := -1
var _scent_key := ""
var _scent_received_ms := -1
var _selected_reference := ""
var _selected_scent := ""
var _elapsed := 0.0
var _status_elapsed := 0.0
var _generation := 0
var _reload_error := ""
var _max_read_us := 0
var _max_update_us := 0
var _heading: Label
var _status: Label
var _pose: Label
var _timing: Label
var _notice: Label
var _empty: Label
var _details: Label
var _vision: Control
var _vision_layout: VBoxContainer
var _table: Tree
var _scent_layout: VBoxContainer
var _scent_pose: Label
var _scent_timing: Label
var _scent: Control
var _scent_empty: Label
var _scent_table: Tree
var _scent_details: Label
var _sense_selector: TabBar
var _memory: MemoryPanel
var _footer: Label


func _ready() -> void:
	if not _bind_arguments():
		print("[Senses] Requires an explicitly bound local development session.")
		get_tree().quit(2)
		return
	var error: String = content.load_catalog()
	if not error.is_empty():
		push_error(error)
		get_tree().quit(1)
		return
	get_window().title = "Character P%d · SENSES" % owner_id
	get_window().min_size = Vector2i(1000, 700)
	get_window().size = Vector2i(1200, 800)
	get_window().content_scale_size = Vector2i(1200, 800)
	_build_ui()
	RenderingServer.frame_post_draw.connect(_presented)
	_poll()
	_write_status()


func _bind_arguments() -> bool:
	var args := OS.get_cmdline_user_args()
	for argument in args:
		if argument.begins_with("--sense-owner="): owner_id = int(argument.trim_prefix("--sense-owner="))
		elif argument.begins_with("--dev-ai-dir="): trace_dir = argument.trim_prefix("--dev-ai-dir=")
		elif argument.begins_with("--dev-ai-run="): run_id = argument.trim_prefix("--dev-ai-run=")
		elif argument.begins_with("--dev-session-dir="): session_dir = argument.trim_prefix("--dev-session-dir=")
		elif argument.begins_with("--dev-slot="): slot = argument.trim_prefix("--dev-slot=")
	return OS.is_debug_build() and "--dev" in args and "--senses-debug" in args and owner_id in [1, 2] and trace_dir.is_absolute_path() and not run_id.is_empty() and session_dir.is_absolute_path() and slot == "senses%d" % owner_id


func _label(text: String, parent: Node, font_size := 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0c1420")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	_heading = _label("Character P%d  /  live senses" % owner_id, layout, 24)
	_heading.modulate = Color("75c8ff") if owner_id == 1 else Color("ffbc80")
	_status = _label("WAITING · receiving current observations", layout, 16)
	_sense_selector = TabBar.new()
	for page: String in PAGES: _sense_selector.add_tab(page)
	_sense_selector.tab_changed.connect(select_sense)
	layout.add_child(_sense_selector)
	_notice = _label("", layout, 20)
	_notice.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.hide()
	_vision_layout = VBoxContainer.new()
	_vision_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vision_layout.add_theme_constant_override("separation", 10)
	layout.add_child(_vision_layout)
	_pose = _label("Self · waiting for a sampled pose", _vision_layout)
	_timing = _label("", _vision_layout, 13)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vision_layout.add_child(split)
	_build_spatial(split)
	_build_readings(split)
	_build_olfaction(layout)
	_memory = MemoryPanel.new()
	layout.add_child(_memory)
	_memory.configure(owner_id)
	_memory.hide()
	_footer = _label("Latest delivered sample · numbers link detections to the view · coordinates use world units", layout, 12)
	_footer.modulate = Color("a2b3c8")


func _build_spatial(parent: Node) -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 400
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var filters := HBoxContainer.new()
	column.add_child(filters)
	for category: String in ["Focused", "Peripheral"]:
		var toggle := CheckButton.new()
		toggle.text = category
		toggle.button_pressed = true
		toggle.modulate = VisionView.FOCUS if category == "Focused" else VisionView.PERIPHERAL
		toggle.toggled.connect(func(value): set_filter(category, value))
		filters.add_child(toggle)
	_vision = VisionView.new()
	_vision.custom_minimum_size.y = 350
	_vision.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_vision)
	_label("Dot = focused sighting · wedge = approximate cue", column, 12)


func _build_readings(parent: Node) -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 530
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	_label("CURRENT DETECTIONS", column, 16)
	_empty = _label("Waiting for vision", column, 13)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_table = Tree.new()
	_table.columns = 3
	_table.hide_root = true
	_table.hide_folding = true
	_table.select_mode = Tree.SELECT_ROW
	_table.column_titles_visible = true
	for index in 3:
		_table.set_column_title(index, ["Reading", "Observed", "Position / direction"][index])
		_table.set_column_expand(index, index > 0)
	_table.set_column_custom_minimum_width(0, 110)
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table.item_selected.connect(_select_reading)
	column.add_child(_table)
	_details = _label("Select a current detection for its details.", column, 14)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size.y = 100


func _build_olfaction(parent: Node) -> void:
	_scent_layout = VBoxContainer.new()
	_scent_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scent_layout.add_theme_constant_override("separation", 10)
	parent.add_child(_scent_layout)
	_scent_layout.hide()
	_scent_pose = _label("Nose · waiting for a sampled position", _scent_layout)
	_scent_timing = _label("", _scent_layout, 13)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scent_layout.add_child(split)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 400
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(column)
	var filters := HBoxContainer.new()
	column.add_child(filters)
	for scent_class: String in ScentReadings.CLASS_COLORS:
		var toggle := CheckButton.new()
		toggle.text = scent_class + " scent"
		toggle.button_pressed = true
		toggle.modulate = ScentReadings.color_of(scent_class)
		toggle.toggled.connect(func(value): set_scent_filter(scent_class, value))
		filters.add_child(toggle)
	_scent = ScentView.new()
	_scent.custom_minimum_size.y = 350
	_scent.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scent)
	var caption := _label("Faint = measured, no scent · striped = partly measured · dark = not measured · wedge = scent in a measured zone · arrow = coarse bearing, never a position", column, 12)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var readings_column := VBoxContainer.new()
	readings_column.custom_minimum_size.x = 530
	readings_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(readings_column)
	_label("CURRENT SCENT READINGS", readings_column, 16)
	_scent_empty = _label("Waiting for olfaction", readings_column, 13)
	_scent_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scent_table = Tree.new()
	_scent_table.columns = 4
	_scent_table.hide_root = true
	_scent_table.hide_folding = true
	_scent_table.select_mode = Tree.SELECT_ROW
	_scent_table.column_titles_visible = true
	for index in 4:
		_scent_table.set_column_title(index, ["Reading", "Strength", "Freshness", "Bearing"][index])
		_scent_table.set_column_expand(index, index > 0)
	_scent_table.set_column_custom_minimum_width(0, 130)
	_scent_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scent_table.item_selected.connect(_select_scent_reading)
	readings_column.add_child(_scent_table)
	_scent_details = _label("Select a current scent reading for its details.", readings_column, 14)
	_scent_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scent_details.custom_minimum_size.y = 100


func _process(delta: float) -> void:
	if _status == null: return
	_elapsed += delta
	_status_elapsed += delta
	if _elapsed >= 0.025:
		_elapsed = 0
		_poll()
	if _status_elapsed >= 0.25:
		_status_elapsed = 0
		_poll_reload()
		_write_status()


func _poll() -> void:
	var started := Time.get_ticks_usec()
	feed.read_snapshot(trace_dir.path_join("senses.json"), run_id, content.fingerprint.hex_encode())
	_max_read_us = maxi(_max_read_us, feed.read_us)
	var latest: Dictionary = feed.record_for_owner(owner_id)
	var sample: Dictionary = latest.get("vision", {})
	var key := "%s/%s/%s/%s" % [latest.get("round_id", -1), latest.get("entity_id", -1), sample.get("sample_id", -1), sample.get("status", "missing")]
	record = latest
	if key != _sample_key:
		_sample_key = key
		_sample_received_ms = Time.get_ticks_msec()
		readings = Readings.current(sample)
		_vision.set_sample(record, readings)
		_rebuild_readings()
	var nose: Dictionary = latest.get("olfaction", {})
	var scent_key := "%s/%s/%s/%s" % [latest.get("round_id", -1), latest.get("entity_id", -1), nose.get("sample_id", -1), nose.get("status", "missing")]
	if scent_key != _scent_key:
		_scent_key = scent_key
		_scent_received_ms = Time.get_ticks_msec()
		scent_readings = ScentReadings.current(nose)
		_scent.set_sample(record, scent_readings, _arena_tile_size(latest))
		_rebuild_scent_readings()
	_memory.update_source(trace_dir, run_id, content.fingerprint.hex_encode(), feed.world)
	_refresh_status()
	_max_update_us = maxi(_max_update_us, Time.get_ticks_usec() - started)


func _refresh_status() -> void:
	live_status = "LIVE"
	if feed.received_ms < 0: live_status = "WAITING"
	elif Time.get_ticks_msec() - feed.received_ms > 3000: live_status = "DISCONNECTED"
	elif feed.is_stale() or not feed.error.is_empty(): live_status = "STALE"
	elif record.is_empty(): live_status = "WAITING"
	elif record.vision.status != "Sampled": live_status = record.vision.status.replace("_", " ").to_upper()
	elif _sample_stalled(): live_status = "STALE"
	_status.text = live_status + " · " + ("latest delivered vision" if live_status == "LIVE" else "vision readings are not current")
	_status.modulate = Color("8cddb0") if live_status == "LIVE" else Color("ffb454")
	if selected_sense == MEMORY_TAB:
		_status.text = _memory.live_status + " · this creature's exploration memory"
		_status.modulate = Color("8cddb0") if _memory.live_status == "LIVE" else Color("ffb454")
	elif selected_sense == OLFACTION_TAB:
		var scent_status := olfaction_status()
		_status.text = scent_status + " · " + ("latest delivered nose sample" if scent_status == "LIVE" else "scent readings are not current")
		_status.modulate = Color("8cddb0") if scent_status == "LIVE" else Color("ffb454")
	_vision.modulate.a = 1.0 if live_status == "LIVE" else 0.35
	_scent.modulate.a = 1.0 if olfaction_status() == "LIVE" else 0.35
	_refresh_olfaction_text()
	if record.is_empty():
		_pose.text = "Self · waiting for an active creature"
		_timing.text = feed.error if not feed.error.is_empty() else "No current vision sample"
		return
	var definition = content.by_id.get(int(record.definition_id))
	var creature_name := str(definition.display_name) if definition != null else "Character"
	get_window().title = "Character P%d · %s · SENSES" % [owner_id, creature_name]
	_heading.text = "Character P%d · %s  /  senses & memory" % [owner_id, creature_name]
	var sample: Dictionary = record.vision
	if sample.status != "Sampled":
		_pose.text = "Self · vision " + sample.status.replace("_", " ").to_lower()
		_timing.text = "No sampled pose available"
		return
	_pose.text = "Self %s · facing %s · focus %.1f° / total %.1f° · %.1f world units" % [Readings.coordinates(sample.pose.position), Readings.direction(sample.pose.facing), sample.profile.focused_fov_degrees, sample.profile.overall_fov_degrees, sample.profile.range]
	var age := "age unavailable"
	if int(record.delivered_us) >= 0:
		var since_delivery := Time.get_unix_time_from_system() * 1000.0 - (feed.origin_unix_us + int(record.delivered_us)) / 1000.0
		if since_delivery >= 0: age = "sample age ≈ %.0f ms" % (since_delivery + ((int(sample.delivered_tick) - int(sample.sample_tick)) & 0xffffffff) * 1000.0 / 60.0)
	_timing.text = "Sample #%d · source tick %d → delivered tick %d · %s" % [int(sample.sample_id), int(sample.sample_tick), int(sample.delivered_tick), age]


func _sample_stalled() -> bool:
	var expected_ms := int(record.vision.profile.sample_interval) * 1000.0 / 60.0
	return Time.get_ticks_msec() - _sample_received_ms > maxf(Feed.STALE_MS, expected_ms * 3.0)


# The nose has its own clock: a fresh eye sample never makes an old smell look live.
func olfaction_status() -> String:
	if feed.received_ms < 0: return "WAITING"
	if Time.get_ticks_msec() - feed.received_ms > 3000: return "DISCONNECTED"
	if feed.is_stale() or not feed.error.is_empty(): return "STALE"
	if record.is_empty(): return "WAITING"
	var nose: Dictionary = record.olfaction
	if nose.status != "Sampled": return nose.status.replace("_", " ").to_upper()
	var expected_ms := int(nose.profile.sample_interval) * 1000.0 / 60.0
	if Time.get_ticks_msec() - _scent_received_ms > maxf(Feed.STALE_MS, expected_ms * 3.0): return "STALE"
	return "LIVE"


func _arena_tile_size(latest: Dictionary) -> float:
	var arena = content.arena_catalog.arenas_by_id.get(int(latest.get("map_id", 0)))
	return 32.0 if arena == null else float(arena.tile_size)


func _refresh_olfaction_text() -> void:
	if record.is_empty():
		_scent_pose.text = "Nose · waiting for an active creature"
		_scent_timing.text = feed.error if not feed.error.is_empty() else "No current nose sample"
		return
	var nose: Dictionary = record.olfaction
	var emitter: Dictionary = record.own_emitter
	var own := "own body gives off %s scent" % str(emitter.class).to_lower() if emitter.enabled else "own body gives off no scent"
	if nose.status != "Sampled":
		_scent_pose.text = "Nose · olfaction " + nose.status.replace("_", " ").to_lower() + " · " + own
		_scent_timing.text = "No sampled position available"
		return
	_scent_pose.text = "Nose at %s · reach %.0f world units · every %d ticks · %s · %s" % [Readings.coordinates(nose.position), float(nose.profile.range), int(nose.profile.sample_interval), "freshness estimated" if nose.profile.estimates_freshness else "freshness unknown", own]
	var age := "age unavailable"
	if int(record.scent_delivered_us) >= 0:
		var since_delivery := Time.get_unix_time_from_system() * 1000.0 - (feed.origin_unix_us + int(record.scent_delivered_us)) / 1000.0
		if since_delivery >= 0: age = "sample age ≈ %.0f ms" % (since_delivery + ((int(nose.delivered_tick) - int(nose.sample_tick)) & 0xffffffff) * 1000.0 / 60.0)
	_scent_timing.text = "Nose sample #%d · source tick %d → delivered tick %d · %s" % [int(nose.sample_id), int(nose.sample_tick), int(nose.delivered_tick), age]


func _rebuild_scent_readings() -> void:
	_scent_table.clear()
	var root := _scent_table.create_item()
	_scent.selected_number = 0
	_scent_details.text = "Select a current scent reading for its details."
	var nose: Dictionary = record.get("olfaction", {})
	_scent_empty.text = "%d scent class%s detected" % [scent_readings.size(), "" if scent_readings.size() == 1 else "es"]
	if scent_readings.is_empty(): _scent_empty.text = "Sampled: no scent on the measured ground. Absence of smell is not proof of absence."
	if nose.get("status") != "Sampled": _scent_empty.text = "No current nose sample."
	else: _scent_empty.text += "\n" + ScentReadings.coverage_summary(nose)
	for row: Dictionary in scent_readings:
		var item := _scent_table.create_item(root)
		item.set_metadata(0, row)
		item.set_text(0, "%d · %s" % [int(row.number), row.class])
		item.set_custom_color(0, ScentReadings.color_of(row.class))
		item.set_text(1, ScentReadings.STRENGTH_WORDS[row.strength])
		item.set_text(2, ScentReadings.FRESHNESS_WORDS[row.freshness])
		item.set_text(3, "≈ %s" % row.direction if row.bearing_valid else "no usable direction")
		for column in 4: item.set_tooltip_text(column, ScentReadings.details(row))
		if row.class == _selected_scent:
			item.select(0)
			_scent.selected_number = int(row.number)
			_scent_details.text = ScentReadings.details(row)
	if _scent.selected_number == 0: _selected_scent = ""
	_scent.queue_redraw()


func _select_scent_reading() -> void:
	var item := _scent_table.get_selected()
	if item == null: return
	var row: Dictionary = item.get_metadata(0)
	_selected_scent = row.class
	_scent.selected_number = int(row.number)
	_scent.queue_redraw()
	_scent_details.text = ScentReadings.details(row)


func set_scent_filter(scent_class: String, enabled: bool) -> void:
	_scent.show_classes[scent_class] = enabled
	_scent.queue_redraw()


func _rebuild_readings() -> void:
	_table.clear()
	var root := _table.create_item()
	_vision.selected_number = 0
	_details.text = "Select a current detection for its details."
	_empty.text = "%d focused · %d peripheral" % [int(record.get("vision", {}).get("focused_count", 0)), int(record.get("vision", {}).get("cue_count", 0))]
	if readings.is_empty(): _empty.text = "Nothing detected in this sample. Unseen does not mean absent."
	if record.get("vision", {}).get("status") != "Sampled": _empty.text = "No current vision sample."
	for row: Dictionary in readings:
		var item := _table.create_item(root)
		item.set_metadata(0, row)
		item.set_text(0, "%d · %s" % [int(row.number), row.quality])
		item.set_custom_color(0, VisionView.FOCUS if row.quality == "Focused" else VisionView.PERIPHERAL)
		item.set_text(1, _subject_name(row) + " · " + row.locomotion.to_lower() if row.quality == "Focused" else "Unknown presence")
		item.set_text(2, Readings.coordinates(row.position) if row.quality == "Focused" else "≈ %s · %s" % [row.direction, row.band.to_lower()])
		for column in 3: item.set_tooltip_text(column, _reading_details(row))
		if _reading_reference(row) == _selected_reference:
			item.select(0)
			_vision.selected_number = int(row.number)
			_details.text = _reading_details(row)
	if _vision.selected_number == 0: _selected_reference = ""


func _subject_name(row: Dictionary) -> String:
	var definition = content.by_id.get(int(row.appearance_id)) if row.kind == "Creature" else null
	var title := str(definition.display_name) if definition != null else str(row.kind)
	return "%s #%d" % [title, int(row.subject)]


func _reading_details(row: Dictionary) -> String:
	if row.quality == "Peripheral":
		return "Peripheral cue #%d\nApproximate direction %s · %s range band\nIdentity, exact position and action are unknown." % [int(row.observation_id), row.direction, row.band.to_lower()]
	return "%s · focused observation #%d\nPosition %s · distance %.2f world units\nFacing %s · observed state %s" % [_subject_name(row), int(row.observation_id), Readings.coordinates(row.position), float(row.distance), Readings.direction(row.facing), row.locomotion.to_lower()]


func _select_reading() -> void:
	var item := _table.get_selected()
	if item == null: return
	var row: Dictionary = item.get_metadata(0)
	_selected_reference = _reading_reference(row)
	_vision.selected_number = int(row.number)
	_vision.queue_redraw()
	_details.text = _reading_details(row)


func _reading_reference(row: Dictionary) -> String:
	return "focused:%d" % int(row.subject) if row.quality == "Focused" else "cue:%d:%s" % [int(row.sector), row.band]


func select_sense(index: int) -> void:
	if index < 0 or index >= PAGES.size(): return
	selected_sense = index
	_vision_layout.visible = index == 0
	_scent_layout.visible = index == OLFACTION_TAB
	_memory.visible = index == MEMORY_TAB
	_notice.visible = index > 0 and index < MEMORY_TAB and index != OLFACTION_TAB
	if _notice.visible: _notice.text = "%s · Not implemented\nNo readings are available for this sense yet." % PAGES[index]
	if index == MEMORY_TAB: _footer.text = "Remembered visits only · blank = unvisited or forgotten · old entries fade or are replaced as memory fills"
	elif index == OLFACTION_TAB: _footer.text = "Latest delivered nose sample · colours mark scent classes, never individuals · dark = not measured, faint = measured with no scent · a bearing is coarse, not a position"
	else: _footer.text = "Latest delivered sample · numbers link detections to the view · coordinates use world units"
	_refresh_status()


func set_filter(category: String, enabled: bool) -> void:
	if category == "Focused": _vision.show_focus = enabled
	elif category == "Peripheral": _vision.show_periphery = enabled
	_vision.queue_redraw()


func _presented() -> void:
	if record.is_empty(): return
	if selected_sense == 0 and live_status == "LIVE" and int(record.delivered_us) >= 0:
		metrics.presented(_sample_key, feed.origin_unix_us + int(record.delivered_us))
	if selected_sense == OLFACTION_TAB and olfaction_status() == "LIVE" and int(record.scent_delivered_us) >= 0:
		scent_metrics.presented(_scent_key, feed.origin_unix_us + int(record.scent_delivered_us))


func _poll_reload() -> void:
	var path := session_dir.path_join("reload.json")
	if not FileAccess.file_exists(path): return
	var request = Feed.Reader.parse_json(FileAccess.get_file_as_string(path))
	if not request is Dictionary or not Feed.Reader.integer(request.get("generation"), 1) or int(request.generation) <= _generation: return
	_generation = int(request.generation)
	_reload_error = ""
	if not request.get("paths") is Array: _reload_error = "Invalid visual reload notification."
	else:
		for resource in request.paths:
			if not resource is String or not resource.begins_with("res://") or not ResourceLoader.exists(resource):
				_reload_error = "Missing validated presentation resource."
	_vision.queue_redraw()


func _write_status() -> void:
	var value := {"pid": OS.get_process_id(), "role": "senses", "ready": _status != null, "bound": feed.published_us >= 0,
		"owner_id": owner_id, "run_id": run_id, "fingerprint": content.fingerprint.hex_encode(),
		"visual_generation": _generation, "reload_error": _reload_error, "reader_error": feed.error,
		"status": live_status, "selected_sense": PAGES[selected_sense], "sample_key": _sample_key,
		"record": record, "readings": readings, "metrics": metrics.summary(),
		"olfaction_status": olfaction_status(), "scent_key": _scent_key, "scent_readings": scent_readings, "scent_metrics": scent_metrics.summary(),
		"scent_coverage": ScentReadings.coverage_counts(record.get("olfaction", {})), "scent_legend_fits": _scent.legend_fits(),
		"exploration_memory": _memory.debug_state(),
		"read_us_max": _max_read_us, "update_us_max": _max_update_us}
	var path := session_dir.path_join(slot + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
