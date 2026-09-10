class_name ArenaCamera
extends Camera2D

# Local presentation only. This controller never sends gameplay input.
signal view_changed

const PLAYER_ZOOM := 1.5
const MAX_ZOOM := 3.0
const ZOOM_STEP := 1.2
const PAN_SPEED := 600.0 # Viewport pixels per second, independent of zoom.
const PAN_KEYS := [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]

var player_id := 0
var follow_owner := 0 # Zero is the audience's free camera.
var is_overview := true
var arena_size := Vector2.ZERO
var _pan_keys: Dictionary = {}
var _drag_button := MOUSE_BUTTON_NONE


func _ready() -> void:
	get_viewport().size_changed.connect(_resize)
	position_smoothing_enabled = false
	drag_horizontal_enabled = false
	drag_vertical_enabled = false


func configure_role(size: Vector2, role: int) -> void:
	arena_size = size
	player_id = role
	reset_input()
	select_view(role)


func select_view(owner: int) -> void:
	if arena_size == Vector2.ZERO or owner < 0 or owner > 2:
		return
	# Enforce the fighter lock here as well as hiding the audience controls.
	follow_owner = player_id if player_id > 0 else owner
	is_overview = follow_owner == 0
	reset_input()
	zoom = Vector2.ONE * (overview_zoom() if is_overview else PLAYER_ZOOM)
	if is_overview:
		position = arena_size * 0.5
	view_changed.emit()


func overview_zoom() -> float:
	var available := get_viewport_rect().size - Vector2(48, 240)
	return clampf(minf(available.x / arena_size.x, available.y / arena_size.y), 0.1, PLAYER_ZOOM)


func update_view(follow_position: Vector2, delta: float) -> void:
	if player_id > 0:
		follow_owner = player_id
		zoom = Vector2.ONE * PLAYER_ZOOM
		# Follow the rendered character exactly, including near the map boundary.
		position = follow_position
	elif follow_owner > 0:
		position = follow_position
	if player_id == 0 and not _pan_keys.is_empty():
		var direction := Vector2(
			int(_held(KEY_D, KEY_RIGHT)) - int(_held(KEY_A, KEY_LEFT)),
			int(_held(KEY_S, KEY_DOWN)) - int(_held(KEY_W, KEY_UP)))
		pan(direction.normalized() * PAN_SPEED * delta)
	force_update_scroll()


func zoom_by(steps: float, anchor := Vector2.INF) -> void:
	if not enabled or player_id > 0 or arena_size == Vector2.ZERO:
		return
	var old_zoom := zoom.x
	var next_zoom := clampf(old_zoom * pow(ZOOM_STEP, steps), overview_zoom(), MAX_ZOOM)
	if is_equal_approx(old_zoom, next_zoom):
		return
	if anchor != Vector2.INF and follow_owner == 0:
		# Keep the world point under the pointer still while zooming a free view.
		var offset_from_center := anchor - get_viewport_rect().size * 0.5
		position += offset_from_center * (1.0 / old_zoom - 1.0 / next_zoom)
		_clamp_free_position()
	zoom = Vector2.ONE * next_zoom
	is_overview = false
	force_update_scroll()
	view_changed.emit()


func pan(viewport_delta: Vector2) -> void:
	if not enabled or player_id > 0 or viewport_delta.is_zero_approx():
		return
	var changed := follow_owner != 0 or is_overview
	follow_owner = 0
	is_overview = false
	position += viewport_delta / zoom
	_clamp_free_position()
	force_update_scroll()
	if changed:
		view_changed.emit()


func handle_key(event: InputEventKey) -> bool:
	if not enabled or player_id > 0 or event.echo:
		return false
	var key := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key in PAN_KEYS:
		if event.pressed: _pan_keys[key] = true
		else: _pan_keys.erase(key)
		return true
	if not event.pressed:
		return false
	if key in [KEY_0, KEY_HOME, KEY_1, KEY_2]:
		select_view(key - KEY_0 if key in [KEY_1, KEY_2] else 0)
		return true
	if key in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
		zoom_by(-1.0 if key in [KEY_MINUS, KEY_KP_SUBTRACT] else 1.0)
		return true
	return false


func handle_pointer(event: InputEvent) -> bool:
	if not enabled or player_id > 0:
		return false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var steps := maxf(event.factor, 0.01) * (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
			zoom_by(steps, event.position)
			return true
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_drag_button = event.button_index
			return true
	return false


func continue_input(event: InputEvent) -> bool:
	# Releases and an existing drag must still work when the pointer crosses UI.
	if event is InputEventKey and not event.pressed:
		_pan_keys.erase(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	if event is InputEventMouseButton and not event.pressed and event.button_index == _drag_button:
		_drag_button = MOUSE_BUTTON_NONE
	if event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE and enabled and player_id == 0:
		pan(-event.relative)
		return true
	return false


func reset_input() -> void:
	_pan_keys.clear()
	_drag_button = MOUSE_BUTTON_NONE


func _held(first: int, second: int) -> bool:
	return _pan_keys.has(first) or _pan_keys.has(second)


func _clamp_free_position() -> void:
	position = position.clamp(Vector2.ZERO, arena_size)


func _resize() -> void:
	if arena_size == Vector2.ZERO:
		return
	if player_id > 0:
		zoom = Vector2.ONE * PLAYER_ZOOM
	elif is_overview:
		zoom = Vector2.ONE * overview_zoom()
		position = arena_size * 0.5
	else:
		zoom = Vector2.ONE * clampf(zoom.x, overview_zoom(), MAX_ZOOM)
	force_update_scroll()
	view_changed.emit()
