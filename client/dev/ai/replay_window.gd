extends Control

const Store = preload("res://dev/ai/replay_store.gd")
const Stage = preload("res://dev/ai/replay_stage.gd")
const Graph = preload("res://dev/ai/decision_graph.gd")
const Palette = preload("res://dev/ai/trace_palette.gd")
const VisionView = preload("res://dev/ai/vision_view.gd")
const Trace = preload("res://dev/ai/trace_reader.gd")
const Content = preload("res://content/game_content.gd")
var content := Content.new()
var store: RefCounted
var entries: Array = []
var header: Dictionary = {}
var frame: Dictionary = {}
var snapshot: SessionSnapshot
var current_index := -1
var wanted_index := -1
var playing := false
var speed := 1.0
var _play_position := 0.0
var _token := 0
var _loading := false
var _warning := ""
var _notice := ""
var _path := ""
var _status: Label
var _clock: Label
var _play: Button
var _seek: HSlider
var _tabs: TabContainer
var stage: SubViewportContainer
var _graphs: Array[Control] = []
var _visions: Array[Control] = []
var _details: Array[TextEdit] = []
var _trace_labels: Array[Label] = []
var _traces: Dictionary = {}
var _cursors := [0, 0]
var _dialog: FileDialog

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.is_debug_build() or "--dev" not in args:
		get_tree().quit(2)
		return
	var error: String = content.load_catalog()
	if not error.is_empty(): push_error(error); get_tree().quit(1); return
	get_window().title = "MoPock · QA MATCH REPLAY"
	get_window().size = Vector2i(1440, 940)
	get_window().min_size = Vector2i(1100, 720)
	get_window().content_scale_size = Vector2i(1440, 940)
	_build_ui()
	for argument in args:
		if argument.begins_with("--replay="): open_recording(argument.trim_prefix("--replay="))

func _exit_tree() -> void:
	if store != null: store.close()

func _label(text: String, parent: Node, size := 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _button(text: String, parent: Node, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0c1420")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["top", "bottom", "left", "right"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	_label("QA match replay  /  one recorded clock for the arena and both brains", layout, 23).modulate = Color("75c8ff")
	_status = _label("Open a recording to begin.", layout)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tools := HBoxContainer.new()
	layout.add_child(tools)
	_button("Open recording…", tools, func(): _dialog.popup_centered_ratio(0.75))
	_play = _button("Play", tools, toggle_play)
	_button("◀ Frame", tools, func(): seek_frame(current_index - 1))
	_button("Frame ▶", tools, func(): seek_frame(current_index + 1))
	var rate := OptionButton.new()
	for value in [0.25, 0.5, 1.0, 2.0, 4.0]: rate.add_item(str(value) + "×")
	rate.select(2)
	rate.item_selected.connect(func(index): speed = [0.25, 0.5, 1.0, 2.0, 4.0][index])
	tools.add_child(rate)
	_button("Overview", tools, func(): stage.overview())
	_button("P1 camera", tools, func(): stage.focus_owner(1))
	_button("P2 camera", tools, func(): stage.focus_owner(2))
	_clock = _label("", layout, 15)
	_seek = HSlider.new()
	_seek.step = 1
	_seek.value_changed.connect(func(value): seek_frame(int(value)))
	layout.add_child(_seek)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_tabs)
	stage = Stage.new()
	stage.content = content
	stage.name = "Recorded arena"
	_tabs.add_child(stage)
	for owner in [1, 2]:
		var pane := VBoxContainer.new()
		pane.name = "P%d decision" % owner
		_tabs.add_child(pane)
		_trace_labels.append(_label("No frame selected.", pane))
		var controls := HBoxContainer.new()
		pane.add_child(controls)
		_button("Fit all", controls, func(): _graphs[owner - 1].fit_all())
		_button("Root", controls, func(): _graphs[owner - 1].center_root())
		_button("−", controls, func(): _graphs[owner - 1].zoom_by(1.0 / 1.2))
		_button("+", controls, func(): _graphs[owner - 1].zoom_by(1.2))
		_button("First event", controls, func(): step_trace(owner, -100))
		_button("◀ Event", controls, func(): step_trace(owner, -1))
		_button("Event ▶", controls, func(): step_trace(owner, 1))
		_button("Full trace", controls, func(): step_trace(owner, 100))
		var host_toggle := CheckButton.new()
		host_toggle.text = "Host diagnostics"
		controls.add_child(host_toggle)
		var legend := HFlowContainer.new()
		pane.add_child(legend)
		for status: String in ["Selected", "Passed", "Rejected", "Resolved", "Skipped", "Unavailable"]:
			_label("● " + Palette.LABELS[status] + "  ", legend, 11).modulate = Palette.color(status)
		var split := HSplitContainer.new()
		split.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pane.add_child(split)
		var graph := Graph.new()
		graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
		graph.node_selected.connect(func(node): _details[owner - 1].text = JSON.stringify({"event": node, "evidence": Trace.evidence_for(_traces[owner], int(node.get("reference", 0)), int(node.get("subject", 0))) if _traces.has(owner) else {}}, "  "))
		split.add_child(graph)
		_graphs.append(graph)
		var vision := VisionView.new()
		vision.content = content
		vision.custom_minimum_size.x = 460
		vision.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		split.add_child(vision)
		_visions.append(vision)
		host_toggle.toggled.connect(func(pressed: bool): vision.host_view = pressed; _render_trace())
		var details := TextEdit.new()
		details.editable = false
		details.custom_minimum_size.y = 120
		details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		pane.add_child(details)
		_details.append(details)
	_tabs.tab_changed.connect(func(_tab): _render_trace())
	_label("Recorded host state · Pause freezes movement and animation · Wheel: camera zoom · Right drag: camera pan", layout, 12)
	_label("This playback does not run AI or connect to the live match. Recordings use the available compatible art, not captured video.", layout, 12).modulate = Color("a4b7cf")
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.replay.jsonl ; QA match recordings"])
	_dialog.file_selected.connect(open_recording)
	add_child(_dialog)

func open_recording(path: String) -> void:
	if store != null: store.close()
	store = Store.new()
	playing = false
	_loading = true
	_notice = ""
	_warning = ""
	_path = path
	entries = []
	current_index = -1
	wanted_index = -1
	frame = {}
	_traces.clear()
	_token += 1
	_dialog.current_dir = path.get_base_dir()
	store.open(path, content.fingerprint.hex_encode())
	_refresh_status()

func seek_frame(index: int, pause := true) -> void:
	if entries.is_empty(): return
	if pause: playing = false
	_notice = ""
	wanted_index = clampi(index, 0, entries.size() - 1)
	_play_position = float(wanted_index)
	_token += 1
	store.request_frame(wanted_index, _token)
	_refresh_status()

func toggle_play() -> void:
	if entries.is_empty() or current_index < 0: return
	playing = not playing
	_token += 1
	wanted_index = current_index
	_play_position = float(current_index)
	_notice = ""
	if playing and current_index == entries.size() - 1: seek_frame(0, false)
	_refresh_status()

func _process(delta: float) -> void:
	if store == null: return
	var result: Dictionary = store.take_result()
	if result.kind == "index":
		_loading = false
		if not result.error.is_empty(): _notice = result.error
		else:
			entries = result.entries
			header = result.header
			_warning = result.warning
			_seek.max_value = maxi(0, entries.size() - 1)
			seek_frame(0)
		_refresh_status()
	elif result.kind == "frame" and int(result.token) == _token:
		if not result.error.is_empty(): playing = false; _notice = result.error; _refresh_status()
		else: _apply_frame(result)
	elif result.kind == "progress" and _loading:
		_status.text = "Indexing recording in the background… %d%%" % int(float(result.value) * 100)
	if not playing or entries.is_empty() or current_index < 0: return
	_play_position += delta * speed * 60.0
	var target := mini(int(_play_position), entries.size() - 1)
	for index in range(current_index + 1, target + 1):
		if entries[index].gap_before:
			playing = false
			_token += 1
			_notice = "Recording gap before tick %d. Paused; seek or step explicitly to inspect the next available frame." % int(entries[index].tick)
			_refresh_status()
			return
	if target > current_index and target != wanted_index:
		wanted_index = target
		_token += 1
		store.request_frame(target, _token)
	if current_index == entries.size() - 1 and wanted_index == current_index: playing = false; _refresh_status()

func _apply_frame(result: Dictionary) -> void:
	var state: SessionSnapshot = result.snapshot
	if state.map_id > 0 and not content.arena_catalog.arenas_by_id.has(state.map_id): _notice = "Unknown recorded arena."; playing = false; _refresh_status(); return
	for entity in state.characters:
		if not content.by_id.has(entity.definition_id): _notice = "Unknown recorded character."; playing = false; _refresh_status(); return
	current_index = int(result.index)
	frame = result.frame
	snapshot = state
	stage.present(snapshot)
	_seek.set_value_no_signal(current_index)
	_traces.clear()
	for trace: Dictionary in frame.ai: _traces[int(trace.owner_id)] = trace
	for owner in [1, 2]: _cursors[owner - 1] = _traces[owner].nodes.size() if _traces.has(owner) else 0
	_clock.text = "%.3f / %.3f s  ·  tick %d  ·  frame %d / %d  ·  round %d  ·  %s" % [float(frame.sequence - entries[0].sequence) / 60.0, float(entries[-1].sequence - entries[0].sequence) / 60.0, snapshot.server_tick, current_index + 1, entries.size(), snapshot.round_id, SessionSnapshot.Phase.keys()[snapshot.phase]]
	_render_trace()
	_refresh_status()

func step_trace(owner: int, direction: int) -> void:
	if not _traces.has(owner): return
	if playing: toggle_play()
	_cursors[owner - 1] = clampi(_cursors[owner - 1] + direction, 0, _traces[owner].nodes.size())
	_render_trace()

func _render_trace() -> void:
	var owner := _tabs.current_tab
	if owner == 0: return
	var graph: Control = _graphs[owner - 1]
	graph.visible = _traces.has(owner)
	if not _traces.has(owner):
		_trace_labels[owner - 1].text = "No P%d AI trace recorded at this frame." % owner
		_details[owner - 1].text = "AI may not have started yet, or telemetry was lost. No earlier trace is substituted."
		return
	var trace: Dictionary = _traces[owner]
	var cursor: int = _cursors[owner - 1]
	graph.present(trace, cursor)
	_visions[owner - 1].present(trace, cursor, _visions[owner - 1].host_view)
	var sample_text := ""
	if int(trace.get("schema_version", 1)) >= 2:
		var sample: Dictionary = trace.input.senses.vision
		sample_text = " · eye sample #%d at tick %d (age %d, %s)" % [int(sample.sample_id), int(sample.sample_tick), (int(trace.input.tick) - int(sample.sample_tick)) & 0xffffffff, sample.status]
	else:
		sample_text = " · schema 1 wander record"
	if int(trace.get("schema_version", 1)) >= 4:
		var nose: Dictionary = trace.input.senses.olfaction
		sample_text += " · nose sample #%d at tick %d (%d readings, %s)" % [int(nose.sample_id), int(nose.sample_tick), int(nose.reading_count), nose.status]
	elif int(trace.get("schema_version", 1)) >= 2:
		sample_text += " · olfaction not recorded in this schema"
	_trace_labels[owner - 1].text = "P%d · entity %d · tick %d · %s → %s · event %d / %d%s" % [owner, int(trace.input.entity_id), int(trace.input.tick), trace.decision_reason, trace.result.kind, cursor, trace.nodes.size(), sample_text]
	_details[owner - 1].text = JSON.stringify({"received": trace.input, "requested": trace.after.last.requested, "confirmed": trace.result, "private_search": trace.after.get("search", {}), "private_scent_memory": trace.after.get("scent", "not recorded in this schema"), "host_scent_field": "not recorded; the live field is never read for an old frame"}, "  ")

func _refresh_status() -> void:
	if _status == null: return
	_play.text = "Pause" if playing else "Play"
	_status.text = ("LOADING" if _loading else "PLAYING" if playing else "PAUSED") + " · " + _path
	if not header.is_empty(): _status.text += " · replay schema %d / trace schema %d" % [int(header.get("schema_version", 1)), int(header.get("trace_schema", 1))]
	if not _warning.is_empty(): _status.text += "\n" + _warning
	if not _notice.is_empty(): _status.text += "\n" + _notice
