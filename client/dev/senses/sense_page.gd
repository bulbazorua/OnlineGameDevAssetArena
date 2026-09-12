extends VBoxContainer

# One page of the senses inspector. Every sense fills the same rows, so a reader
# finds the summary, freshness line, view switch, filters, canvas, readout, list
# and details in the same place on every page. The page itself knows no sense.
signal view_changed(mode: String)

const Style = preload("res://dev/ui/dev_ui_style.gd")
const ARENA_VIEW := "arena"
const LOCAL_VIEW := "local"
const VIEW_LABELS := {"arena": "Arena overview", "local": "Local sensor"}
const LEFT_MINIMUM := 400.0
const RIGHT_MINIMUM := 500.0
const CONTROL_ROW_HEIGHT := 32.0
var summary: Label
var timing: Label
var filters: HBoxContainer
var views: Control
var readout: Label
var list_title: Label
var note: Label
var table: Tree
var details: Label
var view_mode := ARENA_VIEW
var view_buttons: Dictionary = {}
var _view_controls: Dictionary = {}
var _buttons: HBoxContainer
var _group := ButtonGroup.new()


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)


func build_layout(list_heading: String, columns: Array, minimum_widths: Array) -> void:
	summary = _line_label(14, self)
	timing = _line_label(13, self)
	var columns_box := HBoxContainer.new()
	columns_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns_box.add_theme_constant_override("separation", 12)
	add_child(columns_box)
	_build_left(columns_box)
	_build_right(columns_box, list_heading, columns, minimum_widths)
	_add_view_button(ARENA_VIEW)


# Fixed-height rows above and below the canvas, each narrower than the column minimum,
# keep the canvas footprint the same on every page whatever the page puts in them.
func _build_left(parent: Node) -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = LEFT_MINIMUM
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	left.add_theme_constant_override("separation", 6)
	parent.add_child(left)
	_buttons = HBoxContainer.new()
	_buttons.custom_minimum_size.y = CONTROL_ROW_HEIGHT
	left.add_child(_buttons)
	filters = HBoxContainer.new()
	filters.custom_minimum_size.y = CONTROL_ROW_HEIGHT
	left.add_child(filters)
	views = Control.new()
	views.custom_minimum_size.y = 300
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(views)
	readout = _line_label(12, left)
	readout.modulate = Style.NOTE


func _build_right(parent: Node, list_heading: String, columns: Array, minimum_widths: Array) -> void:
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = RIGHT_MINIMUM
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	parent.add_child(right)
	list_title = _line_label(16, right)
	list_title.text = list_heading
	note = Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	right.add_child(note)
	table = Tree.new()
	table.columns = columns.size()
	table.hide_root = true
	table.hide_folding = true
	table.select_mode = Tree.SELECT_ROW
	table.column_titles_visible = true
	for index in columns.size():
		table.set_column_title(index, columns[index])
		table.set_column_expand(index, index > 0)
		if minimum_widths[index] > 0: table.set_column_custom_minimum_width(index, minimum_widths[index])
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(table)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_theme_font_size_override("font_size", 14)
	details.custom_minimum_size.y = 120
	right.add_child(details)


static func coordinates(point: Array) -> String:
	return "(%.1f, %.1f)" % [float(point[0]), float(point[1])]


# Age of a delivered sample: time since the host queued it plus the source-to-delivery ticks.
static func sample_age_text(delivered_us: int, origin_unix_us: int, sample_tick: int, delivered_tick: int) -> String:
	if delivered_us < 0: return "age unavailable"
	var since_delivery := Time.get_unix_time_from_system() * 1000.0 - (origin_unix_us + delivered_us) / 1000.0
	if since_delivery < 0: return "age unavailable"
	return "sample age ≈ %.0f ms" % (since_delivery + ((delivered_tick - sample_tick) & 0xffffffff) * 1000.0 / 60.0)


func _line_label(font_size: int, parent: Node) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label


func add_filter(text: String, color: Color, callback: Callable) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = true
	toggle.modulate = color
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(callback)
	filters.add_child(toggle)
	return toggle


func set_view(mode: String, control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	views.add_child(control)
	_view_controls[mode] = control
	if not view_buttons.has(mode): _add_view_button(mode)
	control.visible = mode == view_mode


func view_control(mode: String) -> Control:
	return _view_controls.get(mode)


func select_view(mode: String) -> void:
	if not view_buttons.has(mode): return
	view_mode = mode
	for key: String in _view_controls: _view_controls[key].visible = key == mode
	view_buttons[mode].set_pressed_no_signal(true)
	view_changed.emit(mode)


func _add_view_button(mode: String) -> void:
	var button := Button.new()
	button.text = VIEW_LABELS[mode]
	button.toggle_mode = true
	button.button_group = _group
	button.focus_mode = Control.FOCUS_NONE
	button.button_pressed = mode == view_mode
	button.toggled.connect(func(pressed: bool): if pressed: select_view(mode))
	_buttons.add_child(button)
	view_buttons[mode] = button
