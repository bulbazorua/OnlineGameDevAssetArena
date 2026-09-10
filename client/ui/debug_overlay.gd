class_name DebugOverlay
extends CanvasLayer

const GameConnection = preload("res://network/game_connection.gd")
const UPDATE_INTERVAL := 0.25

@onready var fps_label: Label = %FPS
@onready var ping_label: Label = %Ping
var _network: GameConnection
var _elapsed := 0.0


func configure(network: GameConnection) -> void:
	_network = network
	_network.connection_changed.connect(_refresh)
	_refresh()


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
