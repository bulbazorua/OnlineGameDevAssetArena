extends SceneTree

const GameConnection = preload("res://network/game_connection.gd")
const GameProtocol = preload("res://network/protocol.gd")
const GameContent = preload("res://content/game_content.gd")
const SessionSnapshot = preload("res://session/session_snapshot.gd")

var host_pid := -1
var clients: Array[Node] = []
var port := 0


func _initialize() -> void:
	Engine.max_fps = 120
	_run.call_deferred()


func _run() -> void:
	var server_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):
			server_path = argument.trim_prefix("--server=")
	var reservation := PacketPeerUDP.new()
	if server_path.is_empty() or reservation.bind(0, "127.0.0.1") != OK:
		push_error("Could not prepare the connection check.")
		quit(1)
		return
	port = reservation.get_local_port()
	reservation.close()
	host_pid = OS.create_process(server_path, ["--bind=127.0.0.1", "--port=%d" % port, "--content-dir=" + ProjectSettings.globalize_path("res://content/data")])
	if host_pid <= 0:
		push_error("Could not start the Odin host.")
		quit(1)
		return
	var failure := await _check()
	for client in clients:
		client.queue_free()
	await process_frame
	if host_pid > 0 and OS.is_process_running(host_pid):
		OS.kill(host_pid)
	if failure.is_empty():
		print("PASS: ", get_script().resource_path.get_file())
		quit(0)
	else:
		push_error(failure)
		quit(1)


func _new_client(audience := false) -> Node:
	var client = load("res://main.tscn").instantiate()
	client.get_node("UI/Screens/LobbyScreen").get_node("%HostPort").value = port
	client.get_node("UI/Screens/LobbyScreen").get_node("%JoinAsAudience").button_pressed = audience
	clients.append(client)
	root.add_child(client)
	return client


func _wait_for(condition: Callable, timeout_ms := 7000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await create_timer(0.02).timeout
	return false


func _check() -> String:
	return "No check implemented."
