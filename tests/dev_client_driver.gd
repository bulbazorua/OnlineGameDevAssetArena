extends SceneTree

# Integration-only input/render driver; the real launcher never enables this.
var app: Node
var directory := ""
var slot := ""
var sequence := 0
var busy := false


func _initialize() -> void:
	Engine.max_fps = 120
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dev-session-dir="): directory = argument.trim_prefix("--dev-session-dir=")
		if argument.begins_with("--dev-slot="): slot = argument.trim_prefix("--dev-slot=")
	_start.call_deferred()


func _start() -> void:
	if FileAccess.file_exists(directory.path_join("driver.json")):
		var previous = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("driver.json")))
		if previous is Dictionary:
			sequence = int(previous.get("sequence", 0))
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	var timer := Timer.new()
	app.add_child(timer)
	timer.wait_time = 0.1
	timer.timeout.connect(_command)
	timer.start()


func _command() -> void:
	if busy or not FileAccess.file_exists(directory.path_join("driver.json")):
		return
	var command = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("driver.json")))
	if command == null or int(command.sequence) <= sequence:
		return
	sequence = int(command.sequence)
	busy = true
	if command.get("move", false) and slot == "p1":
		var event := InputEventKey.new()
		event.physical_keycode = KEY_S
		event.pressed = true
		root.push_input(event, true)
		await create_timer(0.65).timeout # Complete lift/plant, then travel before testing reload.
		event = InputEventKey.new()
		event.physical_keycode = KEY_S
		root.push_input(event, true)
	await create_timer(0.3).timeout
	if command.get("capture", false) and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("%s-%d.png" % [slot, sequence]))
	# Read the currently bound terrain texture, not a fresh disk load.
	var texture: Texture2D = app.content.tile_set.get_source(1).texture
	var file := FileAccess.open(directory.path_join("driver-%s.json" % slot), FileAccess.WRITE)
	file.store_string(JSON.stringify({"sequence": sequence, "texture_width": texture.get_width(),
		"texture_hash": texture.get_image().get_data().hex_encode().sha256_text()}))
	file.close()
	busy = false
