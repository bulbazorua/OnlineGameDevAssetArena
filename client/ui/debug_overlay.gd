class_name DebugOverlay
extends CanvasLayer

const GameConnection = preload("res://network/game_connection.gd")
const CollisionOverlay = preload("res://dev/collision_overlay.gd")
const UPDATE_INTERVAL := 0.25

@onready var fps_label: Label = %FPS
@onready var ping_label: Label = %Ping
var _network: GameConnection
var _elapsed := 0.0
var colliders: CollisionOverlay
var category_buttons: Dictionary = {}


func configure(network: GameConnection, arena: Node2D) -> void:
	_network = network
	_network.connection_changed.connect(_refresh)
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
	_refresh()
	_show_filters(false)


func _show_filters(value: bool) -> void:
	%Filters.visible = value
	%Panel.offset_left = -300.0 if value else -212.0
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
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= UPDATE_INTERVAL:
		_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	var fps := roundi(Engine.get_frames_per_second())
	fps_label.text = "FPS: %d" % fps if fps > 0 else "FPS: --"
	var ping := _network.get_ping_ms() if _network != null else -1
	ping_label.text = "PING: %d ms" % ping if ping >= 0 else "PING: --"
