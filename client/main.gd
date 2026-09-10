class_name AppController
extends Node

const ArenaSelectScreen = preload("res://ui/arena_select_screen.gd")
const GameArena = preload("res://world/game_arena.gd")
const GameContent = preload("res://content/game_content.gd")
const CharacterSelectScreen = preload("res://ui/character_select_screen.gd")
const GameProtocol = preload("res://network/protocol.gd")
const GameConnection = preload("res://network/game_connection.gd")
const LobbyScreen = preload("res://ui/lobby_screen.gd")
const SessionSnapshot = preload("res://session/session_snapshot.gd")
const DEBUG_OVERLAY_SCENE = preload("res://ui/debug_overlay.tscn")

@onready var game_arena: GameArena = $GameArena
@onready var network: GameConnection = $GameConnection
var content := GameContent.new()
var _viewing_arena := false
@onready var arena_selection: ArenaSelectScreen = $UI/Screens/ArenaSelectScreen
@onready var selection: CharacterSelectScreen = $UI/Screens/CharacterSelectScreen
@onready var lobby: LobbyScreen = $UI/Screens/LobbyScreen


func _ready() -> void:
	# Explicit opt-in; even --dev cannot enable this in a release export.
	if OS.is_debug_build() and "--dev" in OS.get_cmdline_user_args():
		var overlay = DEBUG_OVERLAY_SCENE.instantiate()
		add_child(overlay)
		overlay.configure(network)
	network.connection_changed.connect(_display_connection)
	network.session_changed.connect(_display_session)
	network.world_changed.connect(game_arena.apply_world)
	lobby.connect_requested.connect(network.connect_to_host)
	lobby.disconnect_requested.connect(network.disconnect_from_host)
	lobby.start_selection_requested.connect(network.request_start_selection)
	selection.character_requested.connect(network.request_character)
	selection.ready_requested.connect(network.request_set_ready)
	selection.disconnect_requested.connect(network.disconnect_from_host)
	selection.arena_view_requested.connect(_show_arena)
	arena_selection.characters_requested.connect(_show_characters)
	arena_selection.arena_requested.connect(network.request_arena)
	arena_selection.ready_requested.connect(network.request_set_ready)
	arena_selection.disconnect_requested.connect(network.disconnect_from_host)
	network.command_rejected.connect(_display_rejection)
	var content_error := content.load_catalog()
	if not content_error.is_empty():
		network._set_status("Invalid game content", content_error, true)
		return
	network.content = content
	game_arena.configure(content, network)
	selection.configure(content)
	arena_selection.configure(content)
	_display_connection()
	for argument in OS.get_cmdline_user_args():
		if argument == "--audience":
			lobby.audience_input.button_pressed = true
		elif argument.begins_with("--host="):
			lobby.host_input.text = argument.trim_prefix("--host=")
		elif argument.begins_with("--port="):
			var value := argument.trim_prefix("--port=")
			if not value.is_valid_int() or int(value) < 1 or int(value) > 65535:
				network.connect_to_host(lobby.host_input.text, 0)
				return
			lobby.port_input.value = int(value)
	if OS.is_debug_build() and "--dev" in OS.get_cmdline_user_args():
		var reload_controller = load("res://dev/reload_controller.gd").new()
		add_child(reload_controller)
		reload_controller.configure(self)
	lobby.request_connection()


func _display_connection() -> void:
	lobby.display_connection(network.connection_state, network.status_message, network.status_detail, network.status_error)
	_display_session(network.session)


func _display_session(snapshot: SessionSnapshot) -> void:
	lobby.display_session(snapshot, network.player_id)
	var selecting := snapshot != null and snapshot.phase == SessionSnapshot.Phase.SELECTING
	var playing := snapshot != null and snapshot.phase in [SessionSnapshot.Phase.COUNTDOWN, SessionSnapshot.Phase.IN_ARENA]
	lobby.visible = not selecting and not playing
	game_arena.display_session(snapshot)
	if not selecting:
		_viewing_arena = false
	selection.visible = selecting and not _viewing_arena
	arena_selection.visible = selecting and _viewing_arena
	selection.display_session(snapshot, network.player_id)
	arena_selection.display_session(snapshot, network.player_id)
	if network.player_id == 0 and snapshot != null:
		selection.role_label.text += " · " + network.audience_timeline_label()
		arena_selection.get_node("%RoleLabel").text += " · " + network.audience_timeline_label()


func _display_rejection(reason: int) -> void:
	if arena_selection.visible:
		arena_selection.show_rejection(reason)
	elif selection.visible:
		selection.show_rejection(reason)
	else:
		lobby.detail_label.text = GameProtocol.rejection_text(reason)


func _show_arena() -> void:
	_viewing_arena = true
	_display_session(network.session)


func _show_characters() -> void:
	_viewing_arena = false
	_display_session(network.session)
