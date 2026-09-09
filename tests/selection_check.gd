extends "./host_check.gd"

var rejections: Array[int] = []


func _check() -> String:
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null):
		return "P1 could not connect."
	first.network.command_rejected.connect(func(reason: int): rejections.append(reason))
	if not first.lobby.start_button.disabled:
		return "Start enabled with only one player."
	first.network.request_start_selection()
	if not await _rejected(GameProtocol.CommandRejectReason.NEED_TWO_PLAYERS):
		return "Host allowed selection with one player."
	var watcher = _new_client(true)
	var second = _new_client()
	if not await _wait_for(func(): return _all_states(0, 0, false, 0, false, 1)):
		return "Lobby membership did not converge."
	watcher.network.command_rejected.connect(func(reason: int): rejections.append(reason))
	second.network.command_rejected.connect(func(reason: int): rejections.append(reason))
	if first.lobby.start_button.disabled or second.lobby.start_button.disabled or not watcher.lobby.start_button.disabled:
		return "Start permissions were wrong in the lobby."
	# Both requests use round 0. Ordered processing must create only one round.
	first.lobby.start_button.pressed.emit()
	second.lobby.start_button.pressed.emit()
	if not await _wait_for(func(): return _all_states(1, 0, false, 0, false, 1)):
		return "Selection did not open for all three screens."
	if not await _rejected(GameProtocol.CommandRejectReason.STALE_ROUND):
		return "Simultaneous Start was not rejected against the new round."
	if first.network.session.round_id != 1:
		return "Start created multiple selection rounds."
	if watcher.selection.ready_button.visible or not first.selection.ready_button.disabled:
		return "Ready was visible for a viewer or enabled before choosing."
	for id in [1, 2, 3, 4]:
		if not watcher.selection.cards[id].disabled:
			return "Audience character cards are interactive."
		first.selection.cards[id].pressed.emit()
		if not await _wait_for(func(): return _all_states(1, id, false, id - 1, false, 1)):
			return "P1 choice %d did not reach all clients." % id
		if not _visible_pick_matches(0, id):
			return "P1 preview or badge did not match character %d." % id
		second.selection.cards[id].pressed.emit()
		if not await _wait_for(func(): return _all_states(1, id, false, id, false, 1)):
			return "P2 mirror choice %d did not reach all clients." % id
		if not _visible_pick_matches(1, id):
			return "P2 preview or badge did not match character %d." % id

	# Server checks still apply when a viewer bypasses disabled UI.
	var before = first.network.session
	watcher.network.request_character(1)
	watcher.network.request_set_ready(4, true)
	watcher.network.request_start_selection()
	for _index in 3:
		if not await _rejected(GameProtocol.CommandRejectReason.AUDIENCE_READ_ONLY):
			return "Host accepted an audience command."
	if first.network.session.revision != before.revision:
		return "Rejected audience commands changed shared state."
	first.network.request_character(65535)
	if not await _rejected(GameProtocol.CommandRejectReason.UNKNOWN_CHARACTER):
		return "Unknown character ID was accepted."

	first.selection.ready_button.pressed.emit()
	if not await _wait_for(func(): return _all_states(1, 4, true, 4, false, 1)):
		return "Ready did not reach all clients."
	# A duplicate desired Ready is a no-op; it cannot act as a toggle.
	before = first.network.session
	first.network.request_set_ready(4, true)
	if not await _wait_for(func(): return first.network.session != before):
		return "Host did not acknowledge a no-op with its current snapshot."
	if first.network.session.revision != before.revision or not first.network.session.players[0].ready:
		return "Duplicate Ready changed the revision or toggled readiness."
	first.selection.ready_button.pressed.emit()
	if not await _wait_for(func(): return _all_states(1, 4, false, 4, false, 1)):
		return "Unready did not reach all clients."
	first.selection.ready_button.pressed.emit()
	if not await _wait_for(func(): return _all_states(1, 4, true, 4, false, 1)):
		return "Player could not confirm their pick again."
	first.selection.cards[3].pressed.emit()
	first.network.request_set_ready(4, true) # In flight Ready for the previous pick.
	if not await _wait_for(func(): return _all_states(1, 3, false, 4, false, 1)):
		return "Changing character did not clear that player's Ready."
	if not await _rejected(GameProtocol.CommandRejectReason.SELECTION_CHANGED):
		return "In-flight Ready confirmed a different selection."
	second.selection.ready_button.pressed.emit()
	if not await _wait_for(func(): return _all_states(1, 3, false, 4, true, 1)):
		return "The other player could not ready."
	var late = _new_client(true)
	if not await _wait_for(func(): return _all_states(1, 3, false, 4, true, 2)):
		return "A late audience member did not receive current picks and Ready states."
	if not _visible_pick_matches(0, 3) or not _visible_pick_matches(1, 4):
		return "The late audience view did not match existing players."
	late.selection.get_node("%DisconnectButton").pressed.emit()
	if not await _wait_for(func(): return _all_states(1, 3, false, 4, true, 1)):
		return "An audience departure reset selection."

	# Older snapshots must not overwrite newer ones on an established connection.
	var old_message := GameProtocol.DecodedMessage.new()
	old_message.kind = GameProtocol.MessageKind.SESSION_STATE
	old_message.session = before
	first.network._receive_message(old_message)
	if first.network.session.players[0].character_id != 3:
		return "An older snapshot replaced a newer selection."
	var old_round: int = first.network.session.round_id
	second.selection.get_node("%DisconnectButton").pressed.emit()
	if not await _wait_for(func(): return first.lobby.visible and watcher.lobby.visible and first.network.session.player_mask == 1):
		return "Fighter departure did not return everyone to the lobby."
	if first.network.session.players[0].character_id != 0 or first.network.session.players[0].ready or watcher.network.player_id != 0:
		return "Reset retained a pick/Ready flag or promoted a viewer."
	second.lobby.connect_button.pressed.emit()
	if not await _wait_for(func(): return _all_states(0, 0, false, 0, false, 1)):
		return "Player slot could not be reclaimed after reset."
	var stale := GameProtocol.encode_command(GameProtocol.MessageKind.SELECT_CHARACTER, old_round, 1)
	second.network.server_peer.send(0, stale, ENetPacketPeer.FLAG_RELIABLE)
	second.network.connection.flush()
	if not await _rejected(GameProtocol.CommandRejectReason.STALE_ROUND):
		return "A command from the old round affected a reclaimed slot."
	second.lobby.start_button.pressed.emit()
	if not await _wait_for(func(): return _all_states(1, 0, false, 0, false, 1)):
		return "Player 2 could not start a fresh selection."

	# A different digest is rejected before consuming membership.
	var mismatch := GameConnection.new()
	mismatch.content = GameContent.new()
	if not mismatch.content.load_catalog().is_empty():
		mismatch.free()
		return "Could not load mismatch test content."
	mismatch.content.fingerprint[0] ^= 1
	root.add_child(mismatch)
	mismatch.connect_to_host("127.0.0.1", port)
	var rejected := await _wait_for(func(): return mismatch.status_message == "Update game content")
	mismatch.queue_free()
	if not rejected or not _all_states(1, 0, false, 0, false, 1):
		return "Mismatched content was accepted or changed membership."
	return ""


func _rejected(reason: int) -> bool:
	if not await _wait_for(func(): return rejections.has(reason)):
		return false
	rejections.erase(reason)
	return true


func _all_states(phase: int, p1: int, ready1: bool, p2: int, ready2: bool, audience: int) -> bool:
	var revision := -1
	for client in clients:
		if client.network.connection == null:
			continue
		var state: SessionSnapshot = client.network.session
		if state == null or state.player_mask != 3 or state.phase != phase or state.audience_count != audience:
			return false
		if state.players[0].character_id != p1 or state.players[0].ready != ready1 or state.players[1].character_id != p2 or state.players[1].ready != ready2:
			return false
		if revision != -1 and revision != state.revision:
			return false
		revision = state.revision
		if client.selection.visible != (phase == SessionSnapshot.Phase.SELECTING):
			return false
	return true


func _visible_pick_matches(slot: int, id: int) -> bool:
	for client in clients:
		if client.network.connection == null:
			continue
		var screen = client.selection
		if screen._previews[slot].visual.character_id != id or screen._previews[slot].player_id != slot + 1 or screen._names[slot].text != client.content.by_id[id].display_name:
			return false
		for other: int in screen.cards:
			if screen._badges[other][slot].visible != (other == id):
				return false
	return true
