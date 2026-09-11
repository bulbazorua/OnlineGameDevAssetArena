class_name DebugOverlay
extends CanvasLayer

const GameConnection = preload("res://network/game_connection.gd")
const CollisionOverlay = preload("res://dev/collision_overlay.gd")
const SenseOverlay = preload("res://dev/sense_overlay.gd")
const ScentOverlay = preload("res://dev/scent_overlay.gd")
const WindowPreferences = preload("res://dev/window_preferences.gd")
const SearchOverlay = preload("res://dev/search/search_overlay.gd")
const SearchPreferences = preload("res://dev/search/search_preferences.gd")
const SearchDetails = preload("res://dev/search/search_details.gd")
const SearchResetControl = preload("res://dev/search/search_reset_control.gd")
const UPDATE_INTERVAL := 0.25

@onready var fps_label: Label = %FPS
@onready var ping_label: Label = %Ping
var _network: GameConnection
var _elapsed := 0.0
var colliders: CollisionOverlay
var category_buttons: Dictionary = {}
var senses: SenseOverlay
var sense_buttons: Dictionary = {}
var scent: ScentOverlay
var scent_buttons: Dictionary = {}
var scent_toggle: CheckBox
var scent_preferences := WindowPreferences.new()
var search: SearchOverlay
var search_preferences := SearchPreferences.new()
var search_toggle: CheckBox
var search_panel: PanelContainer
var search_labels: Array[RichTextLabel] = []
var search_reset: SearchResetControl
var _preference_owner := 0


func configure(network: GameConnection, arena: Node2D) -> void:
	process_priority = 110
	_network = network
	_network.connection_changed.connect(_refresh)
	_network.session_changed.connect(func(_snapshot): _refresh_search())
	colliders = CollisionOverlay.new()
	colliders.configure(arena)
	%CollidersToggle.toggled.connect(colliders.set_enabled)
	%FiltersToggle.toggled.connect(_show_filters)
	for category in CollisionOverlay.CATEGORIES:
		var button := CheckBox.new()
		button.text = category.label
		button.tooltip_text = category.hint
		button.focus_mode = Control.FOCUS_NONE
		for color_name in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(color_name, category.color)
		button.button_pressed = colliders.categories[category.key]
		button.toggled.connect(func(value: bool): colliders.set_category(category.key, value))
		%FilterRows.add_child(button)
		category_buttons[category.key] = button
	%AllColliders.pressed.connect(_set_all.bind(true))
	%NoColliders.pressed.connect(_set_all.bind(false))
	senses = SenseOverlay.new()
	senses.configure(arena)
	%VisionToggle.toggled.connect(senses.set_enabled)
	_build_sense_filters()
	scent = ScentOverlay.new()
	scent.configure(arena, senses.feed)
	_build_scent_filters()
	_build_search(arena)
	_refresh()
	_show_filters(false)


func _build_sense_filters() -> void:
	for category in SenseOverlay.CATEGORIES:
		var button := CheckBox.new()
		button.text = category.label
		button.focus_mode = Control.FOCUS_NONE
		button.button_pressed = senses.categories[category.key]
		for color_name in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(color_name, category.color)
		button.toggled.connect(func(value: bool): senses.set_category(category.key, value))
		%SenseRows.add_child(button)
		sense_buttons[category.key] = button


# Host scent heatmap controls: saved per window, drawing only, never a creature input.
func _build_scent_filters() -> void:
	scent_toggle = %ScentToggle
	scent_toggle.toggled.connect(func(value: bool): scent_preferences.save("field", value); scent.set_enabled(value))
	for category in ScentOverlay.CATEGORIES:
		var button := CheckBox.new()
		button.text = category.label
		button.focus_mode = Control.FOCUS_NONE
		for color_name in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(color_name, category.color)
		button.toggled.connect(func(value: bool): scent_preferences.save(category.key, value); scent.set_category(category.key, value))
		%ScentRows.add_child(button)
		scent_buttons[category.key] = button
	_apply_scent_preferences()


func _apply_scent_preferences() -> void:
	scent_toggle.set_pressed_no_signal(scent_preferences.get_flag("field"))
	scent.set_enabled(scent_preferences.get_flag("field"))
	for key: String in scent_buttons:
		scent_buttons[key].set_pressed_no_signal(scent_preferences.get_flag(key))
		scent.set_category(key, scent_preferences.get_flag(key))


func _show_filters(value: bool) -> void:
	%Filters.visible = value
	%Panel.offset_left = -310.0 if value else -280.0
	%Panel.size.y = 0 # Let the minimum height shrink after closing filters.


func _set_all(value: bool) -> void:
	for key: String in category_buttons:
		var selected := value and key != "grid"
		category_buttons[key].set_pressed_no_signal(selected)
		colliders.set_category(key, selected)
	if value: %CollidersToggle.button_pressed = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_F3:
		%CollidersToggle.button_pressed = not %CollidersToggle.button_pressed
	elif key == KEY_F4:
		%FiltersToggle.button_pressed = not %FiltersToggle.button_pressed
	elif key == KEY_F6:
		search_toggle.button_pressed = not search_toggle.button_pressed
	elif key == KEY_F7:
		search_reset.request_reset()
	elif key == KEY_F8:
		scent_toggle.button_pressed = not scent_toggle.button_pressed
	elif key == KEY_F5:
		%VisionToggle.button_pressed = not %VisionToggle.button_pressed
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if senses != null: %SenseStatus.text = senses.status + ("\n" + scent.status if scent != null and scent.enabled else "")
	_elapsed += delta
	if _elapsed >= UPDATE_INTERVAL:
		_elapsed = 0.0
		_refresh()
		_refresh_search()


func _refresh() -> void:
	var fps := roundi(Engine.get_frames_per_second())
	fps_label.text = "FPS: %d" % fps if fps > 0 else "FPS: --"
	var ping := _network.get_ping_ms() if _network != null else -1
	ping_label.text = "PING: %d ms" % ping if ping >= 0 else "PING: --"


func _build_search(arena: Node2D) -> void:
	search = SearchOverlay.new()
	search.configure(arena)
	search_toggle = CheckBox.new()
	search_toggle.text = "Search / foraging [F6]"
	search_toggle.tooltip_text = "Show private search beliefs and visited places. Saved for this player window."
	search_toggle.focus_mode = Control.FOCUS_NONE
	search_toggle.toggled.connect(func(value: bool): search_preferences.save(value); search.set_enabled(value); search_panel.visible = value)
	var filters := %SenseRows.get_parent()
	filters.add_child(search_toggle)
	filters.move_child(search_toggle, 0)
	search_reset = SearchResetControl.new()
	filters.add_child(search_reset)
	filters.move_child(search_reset, 1)
	search_reset.configure(_network)
	search_panel = PanelContainer.new()
	search_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	search_panel.position = Vector2(12, -480)
	search_panel.size = Vector2(590, 340)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.05, 0.075, 0.96)
	background.content_margin_left = 8
	background.content_margin_right = 8
	background.content_margin_top = 6
	background.content_margin_bottom = 6
	search_panel.add_theme_stylebox_override("panel", background)
	search_panel.visible = false
	$Layout.add_child(search_panel)
	var tabs := TabContainer.new()
	search_panel.add_child(tabs)
	for owner in [1, 2]:
		var label := RichTextLabel.new()
		label.name = "Search P%d" % owner
		label.bbcode_enabled = true
		label.add_theme_font_size_override("normal_font_size", 12)
		label.add_theme_font_size_override("mono_font_size", 11)
		tabs.add_child(label)
		search_labels.append(label)


func _refresh_search() -> void:
	if search == null: return
	if _network.player_id != _preference_owner and _network.player_id in [1, 2]:
		_preference_owner = _network.player_id
		search_preferences.configure(_preference_owner)
		scent_preferences.configure(_preference_owner, "scent", {"field": false, "human": true, "orc": true, "range_p1": true, "range_p2": true})
		_apply_scent_preferences()
	else:
		search_preferences.reload()
		if scent_preferences.reload(): _apply_scent_preferences()
	search_toggle.set_pressed_no_signal(search_preferences.enabled)
	search.set_enabled(search_preferences.enabled)
	search_panel.visible = search.enabled
	for owner in [1, 2]:
		var label := search_labels[owner - 1]
		var scroll := label.get_v_scroll_bar().value
		var value := search.status + " · F6 to hide (saved) · F7 to reset search\n"
		if search.readings.has(owner):
			var record: Dictionary = search.readings[owner]
			value += SearchDetails.text(record.search, int(record.tick), record.intent, record.result)
		if not search_preferences.error.is_empty(): value += "\n" + search_preferences.error
		if label.text != value:
			label.text = value
			label.get_v_scroll_bar().set_deferred("value", scroll)
