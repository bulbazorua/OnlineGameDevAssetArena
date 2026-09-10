extends Control

const Reader = preload("res://dev/ai/trace_reader.gd")
const Spatial = preload("res://dev/ai/spatial_trace.gd")
const Loader = preload("res://dev/ai/trace_loader.gd")
const Timeline = preload("res://dev/ai/trace_timeline.gd")
const Graph = preload("res://dev/ai/decision_graph.gd")
const Palette = preload("res://dev/ai/trace_palette.gd")
const GameContent = preload("res://content/game_content.gd")
var live_reader := Reader.new()
var reader := live_reader
var content := GameContent.new()
var selected: Dictionary = {}
var event_cursor := 0
var paused := false
var offline := false
var observer_id := 0
var trace_dir := ""
var run_id := ""
var session_dir := ""
var slot := ""
var _elapsed := 0.0
var _last_advance := 0
var _generation := 0
var _reload_error := ""
var _operation_error := ""
var _visible_records: Array[Dictionary] = []
var _heading: Label
var _status: Label
var _metrics: Label
var _footer: Label
var _step_label: Label
var _filter: LineEdit
var _timeline: Control
var _graph: Control
var _tabs: TabContainer
var _details: TextEdit
var _events: TextEdit
var _payload: TextEdit
var _spatial: Control
var _pause: Button
var _dialog: FileDialog
var _loader := Loader.new()
var _load_revision := 0
var _journal_pending := ""
var _journal_loading := false
var _filter_pending := -1.0
var _selected_node: Dictionary = {}
var _tab_dirty := [true, true, true, true]
var _reader_us := 0
var _selection_us := 0
var timeline_rebuilds := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for argument in args:
		if argument.begins_with("--ai-owner="): observer_id = int(argument.trim_prefix("--ai-owner="))
		elif argument.begins_with("--dev-ai-dir="): trace_dir = argument.trim_prefix("--dev-ai-dir=")
		elif argument.begins_with("--dev-ai-run="): run_id = argument.trim_prefix("--dev-ai-run=")
		elif argument.begins_with("--dev-session-dir="): session_dir = argument.trim_prefix("--dev-session-dir=")
		elif argument.begins_with("--dev-slot="): slot = argument.trim_prefix("--dev-slot=")
	if not OS.is_debug_build() or "--dev" not in args or "--ai-debug" not in args or observer_id not in [1, 2] or not trace_dir.is_absolute_path() or run_id.is_empty() or not session_dir.is_absolute_path() or slot != "ai%d" % observer_id:
		print("[AI debugger] Requires an explicitly bound local development session.")
		get_tree().quit(2)
		return
	var error: String = content.load_catalog()
	if not error.is_empty():
		push_error(error)
		get_tree().quit(1)
		return
	get_window().title = "MoPock P%d · AI DEBUG" % observer_id
	get_window().min_size = Vector2i(1120, 760)
	get_window().size = Vector2i(1440, 940)
	get_window().content_scale_size = Vector2i(1440, 940)
	_build_ui()
	_loader.start()
	_last_advance = Time.get_ticks_msec()
	_write_status()

func _exit_tree() -> void:
	_loader.close()


func _label(text: String, parent: Node, font_size := 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(text: String, parent: Node, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _text(parent: Node, title: String) -> TextEdit:
	var edit := TextEdit.new()
	edit.name = title
	edit.editable = false
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 13)
	parent.add_child(edit)
	return edit


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0c1420")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	_heading = _label("MoPock P%d  /  private brain debugger" % observer_id, layout, 24)
	_heading.modulate = Color("75c8ff") if observer_id == 1 else Color("ffbc80")
	_status = _label("Waiting for host telemetry…", layout)
	_metrics = _label("Dedicated native thread  ·  copied inputs  ·  authoritative outcomes", layout, 13)
	var toolbar := HBoxContainer.new()
	layout.add_child(toolbar)
	_pause = _button("Pause trace", toolbar, _toggle_pause)
	_button("Live", toolbar, go_live)
	_button("◀ Decision", toolbar, func(): step_decision(-1))
	_button("Decision ▶", toolbar, func(): step_decision(1))
	_button("Replay decision", toolbar, restart_decision)
	_button("◀ Event", toolbar, func(): step_event(-1))
	_button("Event ▶", toolbar, func(): step_event(1))
	_button("Open journal…", toolbar, func(): _dialog.popup_centered_ratio(0.75))
	_step_label = _label("Select a decision to inspect its recorded execution.", layout, 13)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(split)
	var history := VBoxContainer.new()
	history.custom_minimum_size.x = 285
	split.add_child(history)
	_label("DECISION TIMELINE", history, 13)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter tick, reason, branch or outcome"
	_filter.text_changed.connect(func(_value): _begin_browsing(); _filter_pending = 0.18)
	history.add_child(_filter)
	_timeline = Timeline.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.add_theme_font_size_override("font_size", 13)
	_timeline.item_selected.connect(func(index): select_record(_visible_records[index]))
	_timeline.browse_started.connect(_begin_browsing)
	history.add_child(_timeline)
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_tabs)
	var decisions := VSplitContainer.new()
	decisions.name = "Decision tree"
	_tabs.add_child(decisions)
	var graph_area := VBoxContainer.new()
	graph_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	decisions.add_child(graph_area)
	var graph_tools := HBoxContainer.new()
	graph_area.add_child(graph_tools)
	_button("Fit all", graph_tools, func(): _graph.fit_all())
	_button("Root", graph_tools, func(): _graph.center_root())
	_button("−", graph_tools, func(): _graph.zoom_by(1.0 / 1.2))
	_button("+", graph_tools, func(): _graph.zoom_by(1.2))
	_button("Current event", graph_tools, func(): _graph.focus_node(event_cursor))
	_label("Wheel: scroll · Ctrl+wheel: zoom · Right drag: pan", graph_tools, 12)
	var legend := HFlowContainer.new()
	graph_area.add_child(legend)
	for status: String in ["Selected", "Passed", "Rejected", "Resolved", "Skipped", "Unavailable"]:
		_label("● " + Palette.LABELS[status] + "  ", legend, 11).modulate = Palette.color(status)
	_graph = Graph.new()
	_graph.custom_minimum_size.y = 330
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.node_selected.connect(_node_selected)
	graph_area.add_child(_graph)
	_details = _text(decisions, "Details")
	_details.custom_minimum_size.y = 125
	_details.size_flags_stretch_ratio = 0.3
	_events = _text(_tabs, "Event log")
	_payload = _text(_tabs, "Recorded payload")
	_spatial = Spatial.new()
	_spatial.name = "Spatial data"
	_tabs.add_child(_spatial)
	_tabs.tab_changed.connect(func(_tab): _render_active_tab())
	_footer = _label("", layout, 12)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.modulate = Color("a2b3c8")
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.current_dir = trace_dir
	_dialog.filters = PackedStringArray(["*.jsonl,*.1,*.2,*.3 ; Decision journals"])
	_dialog.file_selected.connect(open_journal)
	add_child(_dialog)


func _process(delta: float) -> void:
	if _status == null: return
	var batch := _loader.take_result()
	if not batch.is_empty(): _accept_batch(batch)
	if _filter_pending >= 0:
		_filter_pending -= delta
		if _filter_pending < 0: _rebuild_timeline()
	_elapsed += delta
	if not _journal_pending.is_empty():
		if _loader.request("journal", _journal_pending, "", content.fingerprint.hex_encode(), observer_id, _load_revision):
			_journal_pending = ""
	if _elapsed < 0.25: return
	_elapsed = 0.0
	if not _journal_loading and not offline:
		_loader.request("snapshot", trace_dir.path_join("ai-%d.json" % observer_id), run_id, content.fingerprint.hex_encode(), observer_id)
	_poll_reload()
	_refresh_status()
	_write_status()


func _accept_batch(batch: Dictionary) -> void:
	_reader_us = int(batch.read_us)
	if batch.kind == "journal":
		if int(batch.revision) != _load_revision: return
		_journal_loading = false
		if not batch.error.is_empty():
			_operation_error = batch.error
			_refresh_status()
			return
		var replay := Reader.new()
		replay.records.assign(batch.records)
		replay.last_sequence = int(batch.last_sequence)
		replay.warning = batch.warning
		reader = replay
		offline = true
		paused = true
		_filter.text = ""
		_rebuild_timeline()
		select_record(reader.records.front(), true, true)
		restart_decision()
	else:
		live_reader.error = batch.error
		live_reader.snapshot = batch.snapshot
		live_reader.missed_live_records = int(batch.missed_live_records)
		live_reader.last_sequence = int(batch.last_sequence)
		for record: Dictionary in batch.records: live_reader.records.append(record)
		if live_reader.records.size() > Reader.HISTORY_LIMIT:
			live_reader.records = live_reader.records.slice(-Reader.HISTORY_LIMIT)
		if batch.changed:
			_last_advance = Time.get_ticks_msec()
			if not offline and not paused:
				_rebuild_timeline()
				if not reader.records.is_empty(): select_record(reader.records.back(), false)
	_refresh_status()


func _rebuild_timeline() -> void:
	timeline_rebuilds += 1
	# Replacing a small array of references does not recreate 2,048 UI items.
	# The canvas shapes/draws only the rows inside its viewport.
	_visible_records = []
	var query := _filter.text.to_lower()
	for record: Dictionary in reader.records:
		if not query.is_empty():
			var description := "#%d t%d %s %s" % [int(record.sequence), int(record.input.tick), record.decision_reason, record.result.kind]
			var matches := query in description.to_lower()
			if not matches:
				for node: Dictionary in record.nodes:
					if query in str(node.label).to_lower(): matches = true; break
			if not matches: continue
		_visible_records.append(record)
	_timeline.set_records(_visible_records, not paused)
	if not selected.is_empty(): _timeline.select_sequence(int(selected.sequence))


func _begin_browsing() -> void:
	if paused: return
	paused = true
	_render_record()


func select_record(record: Dictionary, freeze := true, reveal := false) -> void:
	var started := Time.get_ticks_usec()
	# Reader records are immutable after publication. Holding a reference pins
	# this decision even when the rolling live history evicts it.
	selected = record
	if freeze: paused = true
	event_cursor = selected.nodes.size()
	_timeline.select_sequence(int(selected.sequence), reveal)
	_render_record()
	_selection_us = Time.get_ticks_usec() - started


func _render_record() -> void:
	if selected.is_empty(): return
	var r := selected
	var definition = content.by_id.get(int(r.definition_id))
	var name_text: String = "definition %d" % int(r.definition_id) if definition == null else definition.display_name
	_heading.text = "P%d · %s  /  private brain debugger" % [observer_id, name_text]
	get_window().title = "MoPock P%d · %s · AI DEBUG" % [observer_id, name_text]
	_metrics.text = "Thread %d  ·  entity %d / round %d  ·  tick %d  ·  queue %d µs / compute %d µs" % [int(r.worker_id), int(r.input.entity_id), int(r.input.round_id), int(r.input.tick), int(r.started_us - r.queued_us), int(r.finished_us - r.started_us)]
	_step_label.text = "Recorded decision #%d  ·  event %d / %d  ·  %s" % [int(r.sequence), event_cursor, r.nodes.size(), "playback frozen; battle continues" if paused else "following live host decisions"]
	_pause.text = "Resume trace" if paused else "Pause trace"
	_selected_node = r.nodes[event_cursor - 1] if event_cursor > 0 else {}
	_tab_dirty = [true, true, true, true]
	_render_active_tab()


func _render_active_tab() -> void:
	if selected.is_empty() or not _tab_dirty[_tabs.current_tab]: return
	var r := selected
	var tab := _tabs.current_tab
	_tab_dirty[tab] = false
	match tab:
		0:
			_graph.present(r, event_cursor)
			if _selected_node.is_empty():
				_details.text = "At the start of this recorded decision. Press Event ▶ to reveal its first input."
			else: _node_selected(_selected_node)
		1:
			var lines := PackedStringArray()
			for index in event_cursor:
				var node: Dictionary = r.nodes[index]
				lines.append("%02d  +%d µs  thread %d  [%s/%s] %s" % [int(node.id), int(node.elapsed_us), int(node.thread_id), node.stage, node.status, node.label])
				if not str(node.metric).is_empty(): lines.append("    %s: %s / %s  direction=%s" % [node.metric, node.value, node.threshold, node.direction])
			_events.text = "Run %s · owner %d · round %d · entity %d · decision #%d\n\n%s" % [r.run_id, observer_id, int(r.input.round_id), int(r.input.entity_id), int(r.sequence), "\n".join(lines)]
		2:
			_payload.text = "Complete recorded decision (including its eventual outcome):\n\n" + JSON.stringify(r, "  ")
		3:
			_spatial.present(r, event_cursor)


func _node_selected(node: Dictionary) -> void:
	_selected_node = node
	var payload: Dictionary = {"event": node}
	if node.stage == "Input": payload["received"] = selected.input; payload["configuration"] = selected.config
	elif node.stage == "State": payload["private_state_before"] = selected.before
	elif node.stage == "Decision": payload["reason"] = selected.decision_reason; payload["requested"] = selected.after.last.requested
	elif node.stage == "Outcome": payload["confirmed_result"] = selected.result; payload["private_state_after_feedback"] = selected.after
	_details.text = JSON.stringify(payload, "  ")


func _toggle_pause() -> void:
	if paused: go_live()
	else: _begin_browsing()


func go_live() -> void:
	_operation_error = ""
	_load_revision += 1
	_journal_pending = ""
	_journal_loading = false
	offline = false
	paused = false
	reader = live_reader
	_rebuild_timeline()
	if not reader.records.is_empty(): select_record(reader.records.back(), false)


func restart_decision() -> void:
	paused = true
	event_cursor = 0
	_render_record()


func step_event(direction: int) -> void:
	if selected.is_empty(): return
	paused = true
	event_cursor = clampi(event_cursor + direction, 0, selected.nodes.size())
	_render_record()
	if event_cursor > 0 and _tabs.current_tab == 0: _graph.focus_node(event_cursor)


func step_decision(direction: int) -> void:
	var source: Array[Dictionary] = _visible_records
	if source.is_empty(): return
	var index := source.size() - 1
	for i in source.size():
		if not selected.is_empty() and source[i].sequence == selected.sequence: index = i; break
	select_record(source[clampi(index + direction, 0, source.size() - 1)], true, true)
	restart_decision()


func open_journal(path: String) -> void:
	_operation_error = ""
	paused = true
	_journal_loading = true
	_load_revision += 1
	_journal_pending = path
	_refresh_status()


func _refresh_status() -> void:
	var age := Time.get_ticks_msec() - _last_advance
	if _journal_loading: _status.text = "Loading journal in the background…"
	elif not _operation_error.is_empty(): _status.text = _operation_error
	elif offline: _status.text = "OFFLINE REPLAY  ·  %s  %s" % [selected.get("run_id", ""), reader.warning]
	elif not live_reader.error.is_empty(): _status.text = live_reader.error
	elif age > 500: _status.text = "STALE  ·  no new host decision for %.1f s" % (age / 1000.0)
	else: _status.text = "LIVE SOURCE  ·  %s  ·  own input → evaluated branches → intent → confirmed result" % ("playback paused" if paused else "recording")
	var data: Dictionary = live_reader.snapshot
	if int(selected.get("truncated_nodes", 0)) > 0:
		_status.text += "  ·  WARNING: %d branch events truncated" % int(selected.truncated_nodes)
	_footer.text = "Retained: %d decisions  ·  missed by live reader: %d  ·  host queue drops: %d  ·  writer: %s  ·  publish: %d µs\nJournals: %s/ai-%d.jsonl (+ 3 rotated segments, 8 MiB each). Vision, mood and learning are not implemented." % [reader.records.size(), live_reader.missed_live_records, int(data.get("dropped_records", 0)), "OK" if str(data.get("writer_error", "")).is_empty() else data.writer_error, int(data.get("publish_us", 0)), trace_dir, observer_id]
	_footer.text += "\nQA recording: %s · %d frames · %.1f / 128 MiB · make replay" % [str(data.get("replay_status", "waiting")), int(data.get("replay_frames", 0)), float(data.get("replay_bytes", 0)) / 1048576.0]
	_footer.text += "\nUI selection: %d µs · background read/validation: %d µs · visible rows drawn: %d" % [_selection_us, _reader_us, _timeline.drawn_rows]


func _poll_reload() -> void:
	var path := session_dir.path_join("reload.json")
	if not FileAccess.file_exists(path): return
	var request = Reader.parse_json(FileAccess.get_file_as_string(path))
	if not request is Dictionary or not Reader.integer(request.get("generation"), 1) or int(request.generation) <= _generation: return
	_generation = int(request.generation)
	_reload_error = ""
	# This first debugger draws trace geometry, not imported creature/terrain art.
	# Validate the notification; no gameplay client or renderer needs to be recreated.
	if not request.get("paths") is Array: _reload_error = "Invalid visual reload notification."
	else:
		for resource in request.paths:
			if not resource is String or not resource.begins_with("res://") or not ResourceLoader.exists(resource):
				_reload_error = "Missing validated presentation resource."
	_spatial.queue_redraw()


func _write_status() -> void:
	var value := {"pid": OS.get_process_id(), "role": "ai", "ready": _status != null, "bound": live_reader.last_sequence > 0,
		"owner_id": observer_id, "run_id": run_id, "fingerprint": content.fingerprint.hex_encode(), "last_sequence": live_reader.last_sequence,
		"visual_generation": _generation, "reload_error": _reload_error, "reader_error": live_reader.error,
		"paused": paused, "offline": offline, "event_cursor": event_cursor, "selected_sequence": selected.get("sequence", 0),
		"worker_id": selected.get("worker_id", 0), "nodes": selected.get("nodes", []).size()}
	value["journal_loading"] = _journal_loading
	value["selection_us"] = _selection_us
	value["reader_us"] = _reader_us
	var path := session_dir.path_join(slot + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
