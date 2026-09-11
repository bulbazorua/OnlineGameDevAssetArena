extends SceneTree

var app: Node
var directory := ""
var owner := 0
var captured := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dev-session-dir="): directory = argument.trim_prefix("--dev-session-dir=")
		if argument.begins_with("--ai-owner="): owner = int(argument.trim_prefix("--ai-owner="))
	_start.call_deferred()


func _start() -> void:
	app = load("res://dev/ai/ai_debug_window.tscn").instantiate()
	root.add_child(app)
	var timer := Timer.new()
	app.add_child(timer)
	timer.wait_time = 0.25
	timer.timeout.connect(_inspect)
	timer.start()


func _inspect() -> void:
	if app.selected.is_empty(): return
	app._tabs.current_tab = 5
	var panel = app._search
	var enabled: bool = panel.preferences.enabled
	var shown: bool = "Direction scores" in panel.details.get_parsed_text() and panel.toggle.button_pressed
	var file := FileAccess.open(directory.path_join("search-ai%d.json" % owner), FileAccess.WRITE)
	file.store_string(JSON.stringify({"enabled": enabled, "shown": shown, "tick": app.selected.input.tick}))
	file.close()
	if enabled and shown and not captured and DisplayServer.get_name() != "headless":
		captured = true
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("ai%d-search.png" % owner))
