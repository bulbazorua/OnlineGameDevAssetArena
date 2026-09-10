extends "./host_check.gd"

class WireObserver extends GameConnection:
	var received: Array[Dictionary] = []

	func _receive_message(message: GameProtocol.DecodedMessage) -> void:
		# Inspect every decoded packet BEFORE the connection or presentation can
		# discard/filter it. A display-only delay cannot pass these assertions.
		var entry := {"at": Time.get_ticks_msec(), "kind": message.kind, "round": message.round_id}
		if message.session != null:
			entry.merge({"round": message.session.round_id, "phase": message.session.phase,
				"positions": message.session.trainers.map(func(character): return character.position),
				"countdown": message.session.countdown_seconds,
				"picks": message.session.players.map(func(player): return player.character_id)}, true)
		received.append(entry)
		super._receive_message(message)


func _host_arguments() -> PackedStringArray:
	var arguments := super._host_arguments()
	arguments.remove_at(arguments.find("--audience-delay=0"))
	# Omit the flag to test the real production default: five seconds.
	return arguments


func _observer(content: GameContent, explicit_audience := true) -> WireObserver:
	var observer := WireObserver.new()
	observer.content = content
	root.add_child(observer)
	clients.append(observer)
	observer.connect_to_host("127.0.0.1", port, explicit_audience)
	return observer


func _check() -> String:
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 did not join."
	var second = _new_client()
	if not await _wait_for(func(): return second.network.session != null): return "P2 did not join."
	var audience = _new_client(true)
	var wire := _observer(first.content)
	var overflow := _observer(first.content, false)
	if not await _wait_for(func(): return audience.network.connection_state == GameConnection.ConnectionState.CONNECTED and wire.connection_state == GameConnection.ConnectionState.CONNECTED and overflow.connection_state == GameConnection.ConnectionState.CONNECTED): return "Audience Welcome waited for the delay."
	for connection in [audience.network, wire, overflow]:
		if connection.player_id != 0 or connection.audience_delay_ms != 5000 or connection.session != null: return "Default delay, overflow role, or initial buffering was wrong."
	if first.network.audience_delay_ms != 0 or second.network.audience_delay_ms != 0: return "Players were assigned an audience delay."
	if not audience.lobby.detail_label.text.contains("5 s"): return "Audience buffering screen did not explain the delay."

	var selection_at := Time.get_ticks_msec()
	first.network.request_start_selection()
	if not await _wait_for(func(): return first.network.session.phase == SessionSnapshot.Phase.SELECTING): return "Fighter selection was delayed."
	var pick_at := Time.get_ticks_msec()
	first.network.request_character(3)
	second.network.request_character(4)
	if not await _wait_for(func(): return first.network.session.players[0].character_id == 3 and first.network.session.players[1].character_id == 4): return "Fighter picks were delayed."
	await create_timer(0.15).timeout
	first.network.request_set_ready(3, true)
	second.network.request_set_ready(4, true)
	if not await _wait_for(func(): return first.network.session.phase == SessionSnapshot.Phase.COUNTDOWN): return "Fighter countdown did not start."
	if audience.network.session != null or wire.session != null or overflow.session != null: return "Early selection state leaked during buffer warmup."
	if not await _wait_for(func(): return first.network.session.phase == SessionSnapshot.Phase.IN_ARENA): return "Fighters did not spawn after countdown."
	if audience.network.session == null or audience.network.session.phase == SessionSnapshot.Phase.IN_ARENA: return "Spectator countdown did not follow its delayed timeline."
	if not await _wait_for(func(): return first.network.session.summon_elapsed_ticks == 90): return "Trainer summon lock did not finish."
	var spawn: Vector2 = first.network.session.trainers[0].position
	var move_at := Time.get_ticks_msec()
	_key(first, KEY_D, true)
	await create_timer(0.65).timeout
	_key(first, KEY_D, false)
	await create_timer(0.15).timeout
	if first.network.session.trainers[0].position.x <= spawn.x + 20: return "Live fighter movement was delayed."
	var late := _observer(first.content)
	if not await _wait_for(func(): return late.session != null): return "Late audience did not get mature history."
	if late.session.phase == SessionSnapshot.Phase.IN_ARENA: return "Late join leaked the live arena."
	_repeat_hello(wire, false)
	if not await _wait_for(func(): return audience.network.session.phase == SessionSnapshot.Phase.IN_ARENA): return "Delayed arena never arrived."
	var before_zoom: Vector2 = audience.game_arena.camera.zoom
	audience.game_arena.camera.zoom_by(1)
	if audience.game_arena.camera.zoom == before_zoom: return "Spectator delay blocked local camera controls."
	if not audience.game_arena.phase_label.text.contains("5 s"): return "Arena HUD omitted the delay label."
	if not await _wait_for(func(): return wire.session.phase == SessionSnapshot.Phase.IN_ARENA and wire.session.trainers[0].position.x > spawn.x + 20): return "Delayed movement never arrived."
	await create_timer(0.15).timeout
	for observer in [wire, overflow, late]:
		var saw_movement := false
		for entry in observer.received:
			if entry.kind == GameProtocol.MessageKind.SESSION_STATE and entry.phase != SessionSnapshot.Phase.LOBBY and entry.at < selection_at + 5000: return "Reliable session leaked selection early."
			if entry.has("picks") and entry.picks[0] == 3 and entry.at < pick_at + 5000: return "Character choice leaked early."
			if entry.has("positions") and not entry.positions.is_empty() and entry.positions[0].x > spawn.x:
				saw_movement = true
				if entry.at < move_at + 5000: return "A received packet leaked live movement before the delay."
		if not saw_movement: return "A spectator missed delayed movement."
	var countdowns: Array = []
	for entry in wire.received:
		if entry.kind == GameProtocol.MessageKind.SESSION_STATE and entry.phase == SessionSnapshot.Phase.COUNTDOWN:
			if countdowns.is_empty() or countdowns[-1] != entry.countdown: countdowns.append(entry.countdown)
	if countdowns != [5, 4, 3, 2, 1]: return "Spectator countdown was skipped or reordered: " + str(countdowns)

	# Reset is part of the delayed feed. New joins, reconnects, repeated Hello,
	# and rejected commands must not expose the next live round or its positions.
	var previous_round: int = wire.session.round_id
	var reset_at := Time.get_ticks_msec()
	first.network.request_return_to_lobby()
	if not await _wait_for(func(): return first.network.session.phase == SessionSnapshot.Phase.LOBBY): return "Fighter reset was delayed."
	var after_reset := _observer(first.content, false)
	overflow.disconnect_from_host()
	overflow.connect_to_host("127.0.0.1", port, false)
	if not await _wait_for(func(): return after_reset.session != null and overflow.session != null): return "Reconnect did not receive delayed history."
	for observer in [wire, overflow, after_reset]:
		_repeat_hello(observer, false)
		observer.server_peer.send(0, GameProtocol.encode_command(GameProtocol.MessageKind.START_SELECTION, first.network.session.round_id), ENetPacketPeer.FLAG_RELIABLE)
		observer.connection.flush()
	await create_timer(0.2).timeout
	for observer in [wire, overflow, after_reset]:
		if observer.player_id != 0 or observer.session.round_id != previous_round or observer.session.phase != SessionSnapshot.Phase.IN_ARENA: return "Rejoin or repeated Hello exposed a live reset."
		var rejected := false
		for entry in observer.received:
			if entry.at >= reset_at and entry.kind == GameProtocol.MessageKind.COMMAND_REJECTED:
				rejected = true
				if entry.round != previous_round: return "Command rejection leaked the live round."
		if not rejected: return "Audience command was not rejected."
	if not await _wait_for(func(): return wire.session.phase == SessionSnapshot.Phase.LOBBY): return "Delayed round reset never arrived."
	await create_timer(0.15).timeout
	for observer in [wire, overflow, late, after_reset]:
		for entry in observer.received:
			if entry.at >= reset_at and entry.kind == GameProtocol.MessageKind.SESSION_STATE and entry.round != previous_round and entry.at < reset_at + 5000: return "Session update leaked the round reset early."
	if audience.game_arena.camera.enabled: return "Delayed reset left the audience camera active."
	print("Default 5s host delay verified before presentation, including explicit/overflow/late/reconnecting viewers.")
	return ""


func _repeat_hello(connection: GameConnection, wants_audience: bool) -> void:
	connection.server_peer.send(0, GameProtocol.encode_hello(wants_audience, connection.content.fingerprint), ENetPacketPeer.FLAG_RELIABLE)
	connection.connection.flush()


func _key(client: Node, key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	client.game_arena._unhandled_key_input(event)
