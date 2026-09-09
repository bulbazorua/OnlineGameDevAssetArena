extends "./host_check.gd"


func _check() -> String:
	# An audience member can arrive before either fighter, without taking a slot.
	var watcher = _new_client(true)
	if not await _wait_for(func(): return watcher.network.session != null):
		return "The audience could not join an empty arena."
	if watcher.network.player_id != 0 or watcher.network.session.player_mask != 0 or watcher.network.session.audience_count != 1:
		return "The first audience member consumed a fighter slot."
	if watcher.lobby.get_node("%StatusLabel").text != "Connected — Audience":
		return "The audience role was not displayed."
	var initial_snapshot = watcher.network.session

	var first = _new_client()
	if not await _wait_for(func(): return first.network.player_id == 1):
		return "The first client did not receive Player 1."
	if first.lobby.get_node("%StatusLabel").text != "Connected — Player 1":
		return "The client did not display its assigned identity."

	var second = _new_client()
	if not await _wait_for(func(): return second.network.player_id == 2 and _all_rosters_match(3, 1)):
		return "The second connection did not receive a distinct identity."
	if watcher.network.session == initial_snapshot or initial_snapshot.player_mask != 0 or initial_snapshot.audience_count != 1:
		return "Receiving a roster mutated an earlier snapshot."
	if first.lobby.get_node("%Arena").local_player_id != 1 or second.lobby.get_node("%Arena").local_player_id != 2:
		return "The arena did not identify each client's own shape."
	if watcher.lobby.get_node("%Arena").local_player_id != 0:
		return "The audience was assigned a shape."

	# Overflow joins automatically watch; later viewers receive the full roster.
	for _index in 12:
		var extra = _new_client()
		if not await _wait_for(func(): return extra.network.session != null):
			return "An additional audience connection could not join."
		if extra.network.player_id != 0:
			return "An extra connection became a third fighter."
	if not await _wait_for(func(): return _all_rosters_match(3, 13)):
		return "Clients disagreed about the two fighters and thirteen viewers."

	first.lobby.get_node("%ConnectButton").pressed.emit()
	if first.network.player_id != 0 or first.network.connection != null:
		return "Disconnect did not release the client connection."
	if first.network.session != null or first.lobby.get_node("%Arena").player_mask != 0:
		return "The disconnected screen retained stale shapes."
	if not await _wait_for(func(): return _all_rosters_match(2, 13)):
		return "A departed fighter was not removed from every arena."
	if watcher.network.player_id != 0:
		return "An existing audience member was promoted without reconnecting."
	first.lobby.get_node("%ConnectButton").pressed.emit()
	if not await _wait_for(func(): return first.network.player_id == 1 and _all_rosters_match(3, 13)):
		return "Reconnect did not reuse the released slot."

	watcher.lobby.get_node("%ConnectButton").pressed.emit()
	if not await _wait_for(func(): return _all_rosters_match(3, 12)):
		return "The audience count did not update after a viewer left."
	second.lobby.get_node("%ConnectButton").pressed.emit()
	if not await _wait_for(func(): return _all_rosters_match(1, 12)):
		return "Player 2 did not leave the arena."
	watcher.lobby.get_node("%JoinAsAudience").button_pressed = false
	watcher.lobby.get_node("%ConnectButton").pressed.emit()
	if not await _wait_for(func(): return watcher.network.player_id == 2 and _all_rosters_match(3, 12)):
		return "A reconnecting viewer could not take the vacant fighter slot."

	# Repeat Hello with a different preference; role remains fixed for a connection.
	var duplicate := GameProtocol.encode_hello(true, watcher.content.fingerprint)
	watcher.network.server_peer.send(0, duplicate, ENetPacketPeer.FLAG_RELIABLE)
	watcher.network.connection.flush()
	await create_timer(0.2).timeout
	if watcher.network.player_id != 2 or not _all_rosters_match(3, 12):
		return "A duplicate Hello changed an established role or roster."

	var invalid_preference := duplicate.duplicate()
	invalid_preference[6] = 2
	var invalid_kind := duplicate.duplicate()
	invalid_kind[5] = 99
	var invalid_magic := duplicate.duplicate()
	invalid_magic[0] = 0
	var extra_byte := duplicate.duplicate()
	extra_byte.append(0)
	for invalid_hello in [PackedByteArray(), PackedByteArray([79, 71, 65, 65, 2, 1, 0]), invalid_preference, invalid_kind, invalid_magic, extra_byte, duplicate.slice(0, 38)]:
		if not await _invalid_hello_is_rejected(invalid_hello):
			return "The host did not reject malformed Hello: %s" % invalid_hello
	if not OS.is_process_running(host_pid) or first.network.player_id != 1 or not _all_rosters_match(3, 12):
		return "Rejecting bad protocol disturbed established clients or the roster."
	# The extracted connection works without an AppController or lobby scene.
	var standalone := GameConnection.new()
	standalone.content = first.content
	root.add_child(standalone)
	standalone.connect_to_host("127.0.0.1", port, true)
	var standalone_joined := await _wait_for(func(): return standalone.session != null and standalone.session.player_mask == 3 and _all_rosters_match(3, 13))
	standalone.disconnect_from_host()
	standalone.queue_free()
	if not standalone_joined or not await _wait_for(func(): return _all_rosters_match(3, 12)):
		return "The connection could not operate independently of the lobby screen."

	# Removing an already welcomed viewer must release membership exactly once.
	var rejected_viewer = clients[3]
	rejected_viewer.network.server_peer.send(0, PackedByteArray([0]), ENetPacketPeer.FLAG_RELIABLE)
	rejected_viewer.network.connection.flush()
	if not await _wait_for(func(): return rejected_viewer.network.connection == null and _all_rosters_match(3, 11)):
		return "Rejecting an established viewer left incorrect membership."
	if rejected_viewer.lobby.get_node("%StatusLabel").text != "Join rejected":
		return "The protocol rejection was not shown in the lobby."
	rejected_viewer.lobby.get_node("%ConnectButton").pressed.emit()
	if not await _wait_for(func(): return rejected_viewer.network.session != null and _all_rosters_match(3, 12)):
		return "A rejected viewer could not reconnect cleanly."

	OS.kill(host_pid)
	host_pid = -1
	if not await _wait_for(func(): return first.lobby.get_node("%StatusLabel").text == "Host disconnected"):
		return "The client did not detect the stopped host."
	if not await _wait_for(func(): return clients[3].network.connection == null):
		return "An audience member did not detect host loss."
	if clients[3].network.session != null or clients[3].lobby.get_node("%Arena").player_mask != 0:
		return "Host loss left stale audience state."
	first.lobby.get_node("%ConnectButton").pressed.emit()
	if not await _wait_for(func(): return first.lobby.get_node("%StatusLabel").text == "Connection timed out"):
		return "Connecting to an absent host did not time out."
	return ""


func _all_rosters_match(mask: int, count: int) -> bool:
	for client in clients:
		if client.network.connection == null:
			continue
		if client.network.session == null or client.network.session.player_mask != mask or client.network.session.audience_count != count:
			return false
		if client.lobby.get_node("%Arena").player_mask != mask:
			return false
	return true


func _invalid_hello_is_rejected(payload: PackedByteArray) -> bool:
	var transport := ENetConnection.new()
	if transport.create_host(1, 1) != OK:
		return false
	transport.compress(ENetConnection.COMPRESS_NONE)
	var peer := transport.connect_to_host("127.0.0.1", port, 1)
	if peer == null:
		transport.destroy()
		return false
	var deadline := Time.get_ticks_msec() + 5000
	var rejected := false
	while Time.get_ticks_msec() < deadline:
		var event := transport.service(0)
		if event[0] == ENetConnection.EVENT_CONNECT:
			peer.send(0, payload, ENetPacketPeer.FLAG_RELIABLE)
			transport.flush()
		elif event[0] == ENetConnection.EVENT_DISCONNECT:
			rejected = event[2] == 1
			break
		elif event[0] == ENetConnection.EVENT_ERROR:
			break
		await create_timer(0.01).timeout
	transport.destroy()
	return rejected
