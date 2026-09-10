extends "./host_check.gd"

var rejections: Array[int] = []

func _check() -> String:
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 could not join."
	var second = _new_client()
	var watcher = _new_client(true)
	if not await _wait_for(func(): return _maps_match(0, 1)): return "Lobby did not converge."
	for client in clients:
		client.network.command_rejected.connect(func(reason: int): rejections.append(reason))
	first.network.request_arena(2)
	if not await _rejected(GameProtocol.CommandRejectReason.WRONG_PHASE): return "Arena selection was accepted in Lobby."
	first.lobby.start_button.pressed.emit()
	if not await _wait_for(func(): return _maps_match(1, 1)): return "Selection did not choose the default arena."
	for client in clients:
		client.selection.get_node("%ArenaButton").pressed.emit()
		if not client.arena_selection.visible or client.selection.visible: return "Arena navigation did not work."
	for id in watcher.arena_selection.cards:
		if not watcher.arena_selection.cards[id].disabled: return "Audience can select an arena."
	watcher.network.request_arena(2)
	if not await _rejected(GameProtocol.CommandRejectReason.AUDIENCE_READ_ONLY): return "Host accepted audience arena selection."
	first.network.request_arena(65535)
	if not await _rejected(GameProtocol.CommandRejectReason.UNKNOWN_ARENA): return "Host accepted an unknown arena."
	first.network.request_character(3)
	second.network.request_character(4)
	if not await _wait_for(func(): return first.network.session.players[0].character_id == 3 and second.network.session.players[1].character_id == 4): return "Characters could not be selected."
	first.arena_selection.ready_button.pressed.emit()
	if not await _wait_for(func(): return first.network.session.players[0].ready and watcher.network.session.players[0].ready): return "P1 could not ready from the arena screen."
	var previous_round: int = first.network.session.round_id
	var stale_ready := GameProtocol.encode_command(GameProtocol.MessageKind.SET_READY, previous_round, 3, true, 1)
	second.arena_selection.cards[2].pressed.emit()
	if not await _wait_for(func(): return _maps_match(2, 1)): return "P2 map choice was not shared."
	for client in clients:
		var state: SessionSnapshot = client.network.session
		if state.players[0].ready or state.players[1].ready or state.players[0].character_id != 3 or state.players[1].character_id != 4: return "Map change did not clear both Ready flags while preserving picks."
		if state.round_id != previous_round + 1: return "Map change did not advance the selection round."
	first.network.server_peer.send(0, stale_ready, ENetPacketPeer.FLAG_RELIABLE)
	first.network.connection.flush()
	if not await _rejected(GameProtocol.CommandRejectReason.STALE_ROUND): return "In-flight Ready confirmed a changed arena."
	var wrong_map := GameProtocol.encode_command(GameProtocol.MessageKind.SET_READY, first.network.session.round_id, 3, true, 1)
	first.network.server_peer.send(0, wrong_map, ENetPacketPeer.FLAG_RELIABLE)
	first.network.connection.flush()
	if not await _rejected(GameProtocol.CommandRejectReason.ARENA_CHANGED): return "Ready with the wrong map ID was accepted."
	var before = first.network.session
	first.arena_selection.cards[2].pressed.emit()
	if not await _wait_for(func(): return first.network.session != before): return "Repeated arena choice did not receive an acknowledgment."
	if first.network.session.revision != before.revision or first.network.session.round_id != before.round_id: return "Repeated arena choice changed the round/revision."
	first.arena_selection.cards[3].pressed.emit()
	if not await _wait_for(func(): return _maps_match(3, 1)): return "P1 could not select the third arena."
	var late = _new_client(true)
	if not await _wait_for(func(): return _maps_match(3, 2)): return "Late audience did not receive the selected map."
	late.selection.get_node("%ArenaButton").pressed.emit()
	if late.arena_selection.preview.world.definition.id != 3 or not late.arena_selection.cards[3].button_pressed: return "Late audience preview did not show the host map."
	# Inspection is local and read-only, including for viewers.
	var preview = late.arena_selection.preview
	var cell := Vector2i(10, 3)
	var local_position: Vector2 = preview.world.position + preview.world.definition.cell_center(cell) * preview.world.scale
	if preview.cell_at_position(local_position) != cell: return "Preview pointer conversion returned the wrong tile."
	var motion := InputEventMouseMotion.new()
	motion.position = local_position
	preview._gui_input(motion)
	if late.arena_selection.terrain_label.text != "Tile (10, 3) · Cliff · Level 1 · Blocked": return "Terrain inspector did not display the shared terrain and elevation."
	late.arena_selection.get_node("%DisconnectButton").pressed.emit()
	if not await _wait_for(func(): return _maps_match(3, 1)): return "Viewer departure changed the map."
	first.arena_selection.cards[1].pressed.emit()
	if not await _wait_for(func(): return _maps_match(1, 1)): return "Could not return to the first arena."
	# Concurrent choices from the same round accept one decision; the other is stale.
	first.network.request_arena(2)
	second.network.request_arena(3)
	if not await _rejected(GameProtocol.CommandRejectReason.STALE_ROUND): return "Concurrent map choices did not reject the stale request."
	if not await _wait_for(func(): return first.network.session.map_id in [2, 3] and _maps_match(first.network.session.map_id, 1)): return "Concurrent map choices did not converge."
	first.arena_selection.get_node("%CharactersButton").pressed.emit()
	if not first.selection.visible or first.arena_selection.visible: return "Returning to characters did not work."
	if not first.selection.get_node("%ArenaButton").text.contains(first.content.arena_catalog.arenas_by_id[first.network.session.map_id].display_name): return "Character screen did not retain the arena choice."
	for client in [first, second]: client.network.request_set_ready(client.network.session.players[client.network.player_id - 1].character_id, true)
	if not await _wait_for(func(): return _all_ready() and first.game_arena.visible and watcher.game_arena.visible): return "Both Ready did not open the countdown for all clients."
	second.game_arena.get_node("%DisconnectButton").pressed.emit()
	if not await _wait_for(func(): return first.network.session.map_id == 0 and watcher.network.session.map_id == 0 and first.lobby.visible and watcher.lobby.visible): return "Fighter departure did not reset the shared arena and screens."
	if first.network.session.players[0].ready or first.network.session.players[0].character_id != 0: return "Reset retained stale player state."
	return ""

func _maps_match(id: int, audience: int) -> bool:
	var revision := -1
	for client in clients:
		if client.network.connection == null: continue
		var state: SessionSnapshot = client.network.session
		if state == null or state.map_id != id or state.player_mask != 3 or state.audience_count != audience: return false
		if revision >= 0 and revision != state.revision: return false
		revision = state.revision
		if id != 0:
			if client.arena_selection.preview.world.definition == null or client.arena_selection.preview.world.definition.id != id: return false
			for other: int in client.arena_selection.cards:
				if client.arena_selection.cards[other].button_pressed != (other == id): return false
	return true

func _all_ready() -> bool:
	for client in clients:
		if client.network.connection == null: continue
		if client.network.session == null or not client.network.session.both_ready(): return false
	return true

func _rejected(reason: int) -> bool:
	if not await _wait_for(func(): return rejections.has(reason)): return false
	rejections.erase(reason)
	return true
