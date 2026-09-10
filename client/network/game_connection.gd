class_name GameConnection
extends Node

const GameProtocol = preload("res://network/protocol.gd")
const GameContent = preload("res://content/game_content.gd")
const SessionSnapshot = preload("res://session/session_snapshot.gd")

signal command_rejected(reason: int)
signal connection_changed
signal session_changed(snapshot: SessionSnapshot)
signal world_changed(snapshot: SessionSnapshot)

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED }
const CONNECTION_TIMEOUT_MS := 5000
const MAX_EVENTS_PER_FRAME := 32

var content: GameContent
var connection_state := ConnectionState.DISCONNECTED
var player_id := 0
var audience_delay_ms := 0
var session: SessionSnapshot
var status_message := "Disconnected"
var status_detail := "Use 127.0.0.1 for a host running on this computer."
var status_error := false
var connection: ENetConnection
var server_peer: ENetPacketPeer
var _connection_started_ms := 0
var _wants_audience := false


func connect_to_host(address: String, port: int, wants_audience := false) -> void:
	if connection_state != ConnectionState.DISCONNECTED:
		return
	if content == null or content.fingerprint.size() != 32:
		_set_status("Invalid game content", "Load a valid character catalog before connecting.", true)
		return
	if port < 1 or port > 65535:
		_set_status("Invalid port", "Choose a port between 1 and 65535.", true)
		return
	address = address.strip_edges()
	if address.is_empty():
		_set_status("Host address required", "Enter the host's address to connect.", true)
		return
	_wants_audience = wants_audience
	connection = ENetConnection.new()
	if connection.create_host(1, 2) != OK:
		_close_connection("Connection failed", "Could not create the network connection.", true)
		return
	connection.compress(ENetConnection.COMPRESS_NONE)
	server_peer = connection.connect_to_host(address, port, 2)
	if server_peer == null:
		_close_connection("Connection failed", "Check the host address and try again.", true)
		return
	server_peer.set_timeout(32, 1500, 5000)
	connection_state = ConnectionState.CONNECTING
	_connection_started_ms = Time.get_ticks_msec()
	_set_status("Connecting…", "Waiting for the host to welcome you.")


func disconnect_from_host() -> void:
	_close_connection("Disconnected", "You can connect again when ready.")


func get_ping_ms() -> int:
	# ENet's smoothed reliable-packet RTT; -1 means no connected host.
	if connection_state != ConnectionState.CONNECTED or server_peer == null or not server_peer.is_active() or server_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return -1
	return roundi(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func _process(_delta: float) -> void:
	if connection == null:
		return
	# This node keeps servicing ENet independently of the visible screen.
	for _event_index in MAX_EVENTS_PER_FRAME:
		var event := connection.service(0)
		match event[0]:
			ENetConnection.EVENT_NONE:
				break
			ENetConnection.EVENT_ERROR:
				_close_connection("Network error", "Try connecting again.", true)
				return
			ENetConnection.EVENT_CONNECT:
				if server_peer.send(0, GameProtocol.encode_hello(_wants_audience, content.fingerprint), ENetPacketPeer.FLAG_RELIABLE) != OK:
					_close_connection("Connection failed", "Could not send the join request.", true)
					return
				connection.flush()
			ENetConnection.EVENT_RECEIVE:
				var peer: ENetPacketPeer = event[1]
				var packet := peer.get_packet()
				if peer.get_packet_error() != OK:
					_close_connection("Invalid host reply", "The host sent an unexpected message.", true)
					return
				_receive_message(GameProtocol.decode(packet, event[3]))
				if connection == null:
					return
			ENetConnection.EVENT_DISCONNECT:
				if event[2] == GameProtocol.REJECT_PROTOCOL:
					_close_connection("Join rejected", "Check that the host and client use the same version.", true)
				elif event[2] == GameProtocol.REJECT_CONTENT:
					_close_connection("Update game content", "Your game content differs from the host. Use the same content files.", true)
				else:
					_close_connection("Host disconnected", "Start the host and connect again.", true)
				return
	if connection_state == ConnectionState.CONNECTING and Time.get_ticks_msec() - _connection_started_ms >= CONNECTION_TIMEOUT_MS:
		_close_connection("Connection timed out", "Check the address and port, and make sure the host is running.", true)


func _receive_message(message: GameProtocol.DecodedMessage) -> void:
	if not message.error_title.is_empty():
		_close_connection(message.error_title, message.error_detail, true)
		return
	match message.kind:
		GameProtocol.MessageKind.WELCOME:
			if connection_state == ConnectionState.CONNECTED and player_id != message.player_id:
				_close_connection("Invalid player ID", "The host sent an unexpected player identity.", true)
				return
			player_id = message.player_id
			audience_delay_ms = message.audience_delay_ms
			connection_state = ConnectionState.CONNECTED
			if player_id == 0:
				_set_status("Connected — Audience", "%s. Waiting for the spectator feed." % audience_timeline_label())
			else:
				_set_status("Connected — Player %d" % player_id, "Start character selection when both players are connected.")
		GameProtocol.MessageKind.SESSION_STATE:
			if connection_state != ConnectionState.CONNECTED:
				_close_connection("Invalid host reply", "The host sent an invalid session state.", true)
				return
			if player_id > 0 and (message.session.player_mask & (1 << (player_id - 1))) == 0:
				_close_connection("Invalid host reply", "The session state does not match this connection.", true)
				return
			if message.session.map_id != 0 and not content.arena_catalog.arenas_by_id.has(message.session.map_id):
				_close_connection("Update game content", "The host selected an unknown arena.", true)
				return
			for player in message.session.players:
				if player.character_id != 0 and not content.by_id.has(player.character_id):
					_close_connection("Update game content", "The host selected an unknown character.", true)
					return
			if session != null:
				# Unsigned serial comparison also handles u32 revision wraparound.
				var distance: int = (message.session.revision - session.revision) & 0xffffffff
				if distance >= 0x80000000:
					return
			if not _positions_valid(message.session, message.session.map_id):
				_close_connection("Invalid host reply", "A character position is outside the arena.", true)
				return
			# Channel 1 may have newer positions than reliable membership updates.
			if session != null and session.phase == SessionSnapshot.Phase.IN_ARENA and message.session.phase == session.phase and session.round_id == message.session.round_id and GameProtocol.serial_is_newer(session.server_tick, message.session.server_tick):
				message.session = message.session.with_world(session)
			# Replace the snapshot; screens only read the published state.
			var first_state := session == null
			session = message.session
			if first_state and player_id == 0:
				_set_status("Connected — Audience", "%s. Camera controls remain immediate." % audience_timeline_label())
			session_changed.emit(session)

		GameProtocol.MessageKind.WORLD_STATE:
			if session == null or session.phase != SessionSnapshot.Phase.IN_ARENA or session.round_id != message.session.round_id or not GameProtocol.serial_is_newer(message.session.server_tick, session.server_tick):
				return
			if not _positions_valid(message.session, session.map_id):
				_close_connection("Invalid host reply", "A character position is outside the arena.", true)
				return
			for character in message.session.characters:
				var matched := false
				for previous in session.characters:
					if previous.entity_id == character.entity_id and previous.definition_id == character.definition_id and previous.owner_id == character.owner_id:
						matched = true
				if not matched:
					_close_connection("Invalid host reply", "The host changed a character identity during play.", true)
					return
			session = session.with_world(message.session)
			world_changed.emit(session)

		GameProtocol.MessageKind.COMMAND_REJECTED:
			if connection_state != ConnectionState.CONNECTED:
				_close_connection("Invalid host reply", "A command reply arrived before Welcome.", true)
				return
			command_rejected.emit(message.rejection_reason)


func request_start_selection() -> void:
	_send_command(GameProtocol.MessageKind.START_SELECTION)


func request_character(character_id: int) -> void:
	_send_command(GameProtocol.MessageKind.SELECT_CHARACTER, character_id)


func request_set_ready(character_id: int, ready: bool) -> void:
	_send_command(GameProtocol.MessageKind.SET_READY, character_id, ready)


func request_arena(map_id: int) -> void:
	_send_command(GameProtocol.MessageKind.SELECT_ARENA, 0, false, map_id)


func _send_command(kind: int, character_id := 0, ready := false, map_id := 0) -> void:
	if connection_state != ConnectionState.CONNECTED or session == null:
		return
	var expected_map: int = map_id if kind == GameProtocol.MessageKind.SELECT_ARENA else session.map_id
	var packet := GameProtocol.encode_command(kind, session.round_id, character_id, ready, expected_map)
	if server_peer.send(0, packet, ENetPacketPeer.FLAG_RELIABLE) != OK:
		_close_connection("Connection failed", "Could not send your action. Connect again.", true)
		return
	connection.flush()


func _close_connection(message: String, detail: String, is_error := false) -> void:
	_release_connection()
	connection_state = ConnectionState.DISCONNECTED
	player_id = 0
	audience_delay_ms = 0
	session = null
	_set_status(message, detail, is_error)
	session_changed.emit(null)


func _release_connection() -> void:
	if server_peer != null and server_peer.is_active():
		server_peer.peer_disconnect_now()
	server_peer = null
	if connection != null:
		connection.destroy()
	connection = null


func _set_status(message: String, detail: String, is_error := false) -> void:
	status_message = message
	status_detail = detail
	status_error = is_error
	connection_changed.emit()
	print("[client] ", message)


func _exit_tree() -> void:
	_release_connection()


func request_return_to_lobby() -> void:
	_send_command(GameProtocol.MessageKind.RETURN_TO_LOBBY)


func send_input(sequence: int, mask: int) -> void:
	if connection_state != ConnectionState.CONNECTED or session == null:
		return
	if server_peer.send(1, GameProtocol.encode_input(session.round_id, sequence, mask), 0) != OK:
		_close_connection("Connection failed", "Could not send movement. Connect again.", true)
		return
	connection.flush()


func _positions_valid(snapshot: SessionSnapshot, map_id: int) -> bool:
	if snapshot.characters.is_empty():
		return true
	if not content.arena_catalog.arenas_by_id.has(map_id):
		return false
	var arena = content.arena_catalog.arenas_by_id[map_id]
	for character in snapshot.characters:
		if not content.by_id.has(character.definition_id):
			return false
		var radius: float = content.by_id[character.definition_id].footprint_radius
		# Fixed-point rounding can differ from the host by half of 1/256 unit.
		if character.position.x < radius - 0.004 or character.position.y < radius - 0.004 or character.position.x > arena.width * arena.tile_size - radius + 0.004 or character.position.y > arena.height * arena.tile_size - radius + 0.004:
			return false
	return true


func audience_timeline_label() -> String:
	return "Live audience view" if audience_delay_ms == 0 else "Audience delayed %s s" % ("%.3f" % (audience_delay_ms / 1000.0)).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".")
