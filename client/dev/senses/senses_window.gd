extends Control

const Feed = preload("res://dev/sense_feed.gd")
const Readings = preload("res://dev/senses/vision_readings.gd")
const ScentReadings = preload("res://dev/senses/olfaction_readings.gd")
const Metrics = preload("res://dev/senses/display_metrics.gd")
const Style = preload("res://dev/ui/dev_ui_style.gd")
const VisionPage = preload("res://dev/senses/vision_page.gd")
const OlfactionPage = preload("res://dev/senses/olfaction_page.gd")
const MemoryPanel = preload("res://dev/senses/exploration_memory_panel.gd")
const GameContent = preload("res://content/game_content.gd")
const OLFACTION_TAB := 2
const MEMORY_TAB := 5
const PAGES := ["Vision", "Hearing", "Olfaction", "Tactile / terrain", "Pain", "Exploration memory"]
const FOOTERS := {
	0: "Latest delivered sample · numbers link detections to the view · coordinates use world units · the arena outline is a developer reference",
	OLFACTION_TAB: "Nose readings: latest delivered sample, colours mark scent classes, never individuals · arena field: host world data, not what this creature knows",
	MEMORY_TAB: "Remembered visits only · blank = unvisited or forgotten · old entries fade or are replaced as memory fills",
}
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
var _elapsed := 0.0
var _status_elapsed := 0.0
var _generation := 0
var _reload_error := ""
var _max_read_us := 0
var _max_update_us := 0
var _heading: Label
var _status: Label
var _notice: Label
var _sense_selector: TabBar
var _vision_page: VisionPage
var _scent_page: OlfactionPage
var _memory: MemoryPanel
var _vision: Control
var _scent: Control
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


# The window only binds and wires pages; each page builds the shared layout itself.
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
	_vision_page = VisionPage.new()
	layout.add_child(_vision_page)
	_vision_page.configure(content)
	_vision = _vision_page.view
	_scent_page = OlfactionPage.new()
	layout.add_child(_scent_page)
	_scent_page.configure()
	_scent_page.hide()
	_scent = _scent_page.view
	_memory = MemoryPanel.new()
	layout.add_child(_memory)
	_memory.configure(owner_id)
	_memory.hide()
	_footer = _label(FOOTERS[0], layout, 12)
	_footer.modulate = Style.NOTE


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
	var fingerprint := content.fingerprint.hex_encode()
	feed.read_snapshot(trace_dir.path_join("senses.json"), run_id, fingerprint)
	_max_read_us = maxi(_max_read_us, feed.read_us)
	var latest: Dictionary = feed.record_for_owner(owner_id)
	var definition = _arena_definition()
	for page in [_vision_page, _scent_page, _memory]: page.set_arena(definition)
	var sample: Dictionary = latest.get("vision", {})
	var key := "%s/%s/%s/%s" % [latest.get("round_id", -1), latest.get("entity_id", -1), sample.get("sample_id", -1), sample.get("status", "missing")]
	record = latest
	if key != _sample_key:
		_sample_key = key
		_sample_received_ms = Time.get_ticks_msec()
		readings = Readings.current(sample)
		_vision_page.set_sample(record, readings)
	var nose: Dictionary = latest.get("olfaction", {})
	var scent_key := "%s/%s/%s/%s" % [latest.get("round_id", -1), latest.get("entity_id", -1), nose.get("sample_id", -1), nose.get("status", "missing")]
	if scent_key != _scent_key:
		_scent_key = scent_key
		_scent_received_ms = Time.get_ticks_msec()
		scent_readings = ScentReadings.current(nose)
		_scent_page.set_sample(record, scent_readings, 32.0 if definition == null else float(definition.tile_size))
	_memory.update_source(trace_dir, run_id, fingerprint, feed.world)
	_scent_page.update_field(trace_dir, run_id, fingerprint, feed.world)
	_refresh_status()
	_max_update_us = maxi(_max_update_us, Time.get_ticks_usec() - started)


# The catalog arena of the bound world; nothing while the world is inactive or unknown.
func _arena_definition() -> Variant:
	if not feed.world.get("active", false): return null
	return content.arena_catalog.arenas_by_id.get(int(feed.world.get("map_id", 0)))


func _refresh_status() -> void:
	live_status = "LIVE"
	if feed.received_ms < 0: live_status = "WAITING"
	elif Time.get_ticks_msec() - feed.received_ms > 3000: live_status = "DISCONNECTED"
	elif feed.is_stale() or not feed.error.is_empty(): live_status = "STALE"
	elif record.is_empty(): live_status = "WAITING"
	elif record.vision.status != "Sampled": live_status = record.vision.status.replace("_", " ").to_upper()
	elif _sample_stalled(): live_status = "STALE"
	_status.text = live_status + " · " + ("latest delivered vision" if live_status == "LIVE" else "vision readings are not current")
	_status.modulate = Style.status_color(live_status == "LIVE")
	if selected_sense == MEMORY_TAB:
		_status.text = _memory.live_status + " · this creature's exploration memory"
		_status.modulate = Style.status_color(_memory.live_status == "LIVE")
	elif selected_sense == OLFACTION_TAB:
		var scent_status := olfaction_status()
		_status.text = scent_status + " · " + ("latest delivered nose sample" if scent_status == "LIVE" else "scent readings are not current") + " · host field " + _scent_page.field_status
		_status.modulate = Style.status_color(scent_status == "LIVE")
	_vision_page.set_status(live_status)
	_scent_page.set_status(olfaction_status())
	_vision_page.refresh_text(feed.error, feed.origin_unix_us)
	_scent_page.refresh_text(feed.error, feed.origin_unix_us)
	if record.is_empty(): return
	var definition = content.by_id.get(int(record.definition_id))
	var creature_name := str(definition.display_name) if definition != null else "Character"
	get_window().title = "Character P%d · %s · SENSES" % [owner_id, creature_name]
	_heading.text = "Character P%d · %s  /  senses & memory" % [owner_id, creature_name]


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


func set_scent_filter(scent_class: String, enabled: bool) -> void:
	_scent_page.set_class_filter(scent_class, enabled)


func set_filter(category: String, enabled: bool) -> void:
	_vision_page.set_filter(category, enabled)


func select_sense(index: int) -> void:
	if index < 0 or index >= PAGES.size(): return
	selected_sense = index
	_vision_page.visible = index == 0
	_scent_page.visible = index == OLFACTION_TAB
	_memory.visible = index == MEMORY_TAB
	_notice.visible = index > 0 and index < MEMORY_TAB and index != OLFACTION_TAB
	if _notice.visible: _notice.text = "%s · Not implemented\nNo readings are available for this sense yet." % PAGES[index]
	_footer.text = FOOTERS.get(index, FOOTERS[0])
	_refresh_status()


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
	_vision_page.refresh_views()


func _write_status() -> void:
	var value := {"pid": OS.get_process_id(), "role": "senses", "ready": _status != null, "bound": feed.published_us >= 0,
		"owner_id": owner_id, "run_id": run_id, "fingerprint": content.fingerprint.hex_encode(),
		"visual_generation": _generation, "reload_error": _reload_error, "reader_error": feed.error,
		"status": live_status, "selected_sense": PAGES[selected_sense], "sample_key": _sample_key,
		"record": record, "readings": readings, "metrics": metrics.summary(),
		"olfaction_status": olfaction_status(), "scent_key": _scent_key, "scent_readings": scent_readings, "scent_metrics": scent_metrics.summary(),
		"scent_coverage": ScentReadings.coverage_counts(record.get("olfaction", {})), "scent_legend_fits": _scent.legend_fits(),
		"exploration_memory": _memory.debug_state(), "scent_field": _scent_page.field_debug(),
		"views": {"vision": _vision_page.view_mode, "olfaction": _scent_page.view_mode, "memory": _memory.view_mode},
		"overview_legends_fit": {"vision": _vision_page.overview.legend_fits(), "olfaction": _scent_page.overview.legend_fits(), "memory": _memory.overview.legend_fits()},
		"read_us_max": _max_read_us, "update_us_max": _max_update_us}
	var path := session_dir.path_join(slot + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
