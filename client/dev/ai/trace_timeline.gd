extends Control

signal item_selected(index: int)
signal browse_started
const Palette = preload("res://dev/ai/trace_palette.gd")
const ROW_HEIGHT := 42.0
var records: Array[Dictionary] = []
var selected_sequence := 0
var drawn_rows := 0
var _scroll := VScrollBar.new()

func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	add_child(_scroll)
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_scroll.offset_left = -14
	_scroll.value_changed.connect(func(_value): queue_redraw())
	_scroll.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: browse_started.emit())
	resized.connect(_update_scroll)

func set_records(value: Array[Dictionary], follow := false) -> void:
	records = value
	_update_scroll()
	if follow: _scroll.value = _scroll.max_value
	queue_redraw()

func select_sequence(sequence: int, reveal := false) -> void:
	selected_sequence = sequence
	if reveal:
		for i in records.size():
			if int(records[i].sequence) != sequence: continue
			if i * ROW_HEIGHT < _scroll.value: _scroll.value = i * ROW_HEIGHT
			elif (i + 1) * ROW_HEIGHT > _scroll.value + size.y: _scroll.value = (i + 1) * ROW_HEIGHT - size.y
			break
	queue_redraw()

func _update_scroll() -> void:
	_scroll.max_value = records.size() * ROW_HEIGHT
	_scroll.page = size.y
	_scroll.visible = _scroll.max_value > size.y
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101d2c"))
	var font := ThemeDB.fallback_font
	var first := maxi(0, int(_scroll.value / ROW_HEIGHT))
	var last := mini(records.size(), first + int(ceil(size.y / ROW_HEIGHT)) + 1)
	drawn_rows = last - first
	for index in range(first, last):
		var record: Dictionary = records[index]
		var y := index * ROW_HEIGHT - _scroll.value
		var selected := int(record.sequence) == selected_sequence
		var color := Palette.color("Selected" if record.after.last.requested.kind in ["Move", "Face"] else "Info")
		if selected:
			draw_rect(Rect2(0, y, size.x - 15, ROW_HEIGHT - 2), Color("263f55"))
			draw_rect(Rect2(0, y, 3, ROW_HEIGHT - 2), Palette.color("Selected"))
		draw_string(font, Vector2(10, y + 16), "#%d   ·   tick %d" % [int(record.sequence), int(record.input.tick)], HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 12, color)
		draw_string(font, Vector2(10, y + 33), "%s → %s" % [record.decision_reason, record.result.kind], HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 13, Color("d7e2ef"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		browse_started.emit()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: _scroll.value -= ROW_HEIGHT * 3
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _scroll.value += ROW_HEIGHT * 3
		elif event.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			var index := int((_scroll.value + event.position.y) / ROW_HEIGHT)
			if index >= 0 and index < records.size(): item_selected.emit(index)
		accept_event()
	elif event is InputEventKey and event.pressed and not records.is_empty():
		var index := records.size() - 1
		for i in records.size():
			if int(records[i].sequence) == selected_sequence: index = i; break
		match event.keycode:
			KEY_UP: index -= 1
			KEY_DOWN: index += 1
			KEY_PAGEUP: index -= int(size.y / ROW_HEIGHT)
			KEY_PAGEDOWN: index += int(size.y / ROW_HEIGHT)
			KEY_HOME: index = 0
			KEY_END: index = records.size() - 1
			_: return
		browse_started.emit()
		index = clampi(index, 0, records.size() - 1)
		item_selected.emit(index)
		select_sequence(int(records[index].sequence), true)
		accept_event()

