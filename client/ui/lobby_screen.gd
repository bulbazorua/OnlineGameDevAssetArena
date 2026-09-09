class_name LobbyScreen
extends Control

const GameConnection = preload("res://network/game_connection.gd")
const SessionSnapshot = preload("res://session/session_snapshot.gd")

signal connect_requested(address: String, port: int, wants_audience: bool)
signal start_selection_requested
signal disconnect_requested

@onready var host_input: LineEdit = %HostAddress
@onready var port_input: SpinBox = %HostPort
@onready var audience_input: CheckButton = %JoinAsAudience
@onready var status_label: Label = %StatusLabel
@onready var detail_label: Label = %DetailLabel
@onready var connect_button: Button = %ConnectButton
@onready var roster_label: Label = %RosterLabel
@onready var start_button: Button = %StartSelectionButton
@onready var arena: Control = %Arena

var _connection_state := GameConnection.ConnectionState.DISCONNECTED


func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	start_button.pressed.connect(func(): start_selection_requested.emit())


func request_connection() -> void:
	connect_requested.emit(host_input.text, int(port_input.value), audience_input.button_pressed)


func _on_connect_pressed() -> void:
	if _connection_state == GameConnection.ConnectionState.DISCONNECTED:
		request_connection()
	else:
		disconnect_requested.emit()


func display_connection(state: GameConnection.ConnectionState, message: String, detail: String, is_error: bool) -> void:
	_connection_state = state
	var disconnected := state == GameConnection.ConnectionState.DISCONNECTED
	host_input.editable = disconnected
	port_input.editable = disconnected
	audience_input.disabled = not disconnected
	match state:
		GameConnection.ConnectionState.DISCONNECTED:
			connect_button.text = "Connect"
		GameConnection.ConnectionState.CONNECTING:
			connect_button.text = "Cancel"
		GameConnection.ConnectionState.CONNECTED:
			connect_button.text = "Disconnect"
	status_label.text = message
	detail_label.text = detail
	var color := Color("dce5f2")
	if is_error:
		color = Color("ffb7a8")
	elif state == GameConnection.ConnectionState.CONNECTED:
		color = Color("89e4b1")
	status_label.add_theme_color_override("font_color", color)


func display_session(snapshot: SessionSnapshot, local_player_id: int) -> void:
	start_button.disabled = snapshot == null or snapshot.player_mask != 3 or local_player_id == 0
	start_button.text = "Watching lobby" if snapshot != null and local_player_id == 0 else "Start character selection"
	arena.set_roster(snapshot.player_mask if snapshot != null else 0, local_player_id)
	if snapshot != null:
		roster_label.text = "Players: %d / 2     Audience: %d" % [snapshot.player_count(), snapshot.audience_count]
	else:
		roster_label.text = "Connect to see the arena" if _connection_state == GameConnection.ConnectionState.DISCONNECTED else "Waiting for the arena"
