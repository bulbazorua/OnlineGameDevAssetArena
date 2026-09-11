extends SceneTree

# Separate process: validation must never clear live content or its caches.
func _initialize() -> void:
	var content = load("res://content/game_content.gd").new()
	var error: String = content.load_catalog()
	if not error.is_empty():
		push_error(error)
		quit(1)
		return
	if load("res://main.tscn") == null or load("res://dev/reload_controller.gd") == null or load("res://dev/ai/ai_debug_window.tscn") == null or load("res://dev/ai/replay_window.tscn") == null or load("res://dev/senses/senses_window.tscn") == null:
		quit(1)
		return
	print("[dev] Client content validated.")
	quit(0)
