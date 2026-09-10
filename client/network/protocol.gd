class_name GameProtocol
extends RefCounted

const SessionSnapshot = preload("res://session/session_snapshot.gd")
enum MessageKind { HELLO = 1, WELCOME = 2, SESSION_STATE = 3, START_SELECTION = 4, SELECT_CHARACTER = 5, SET_READY = 6, RETURN_TO_LOBBY = 7, COMMAND_REJECTED = 8, SELECT_ARENA = 9, INPUT = 10, WORLD_STATE = 11 }
enum CommandRejectReason { NONE, AUDIENCE_READ_ONLY, WRONG_PHASE, STALE_ROUND, UNKNOWN_CHARACTER, SELECTION_CHANGED, NEED_TWO_PLAYERS, UNKNOWN_ARENA, ARENA_CHANGED }
const HEADER := [79, 71, 65, 65, 6]
const REJECT_PROTOCOL := 1
const REJECT_CONTENT := 2

class DecodedMessage:
	extends RefCounted
	var kind := 0
	var player_id := 0
	var audience_delay_ms := 0
	var session: SessionSnapshot
	var round_id := 0
	var rejected_kind := 0
	var rejection_reason := 0
	var error_title := ""
	var error_detail := ""


static func encode_hello(wants_audience: bool, fingerprint: PackedByteArray) -> PackedByteArray:
	assert(fingerprint.size() == 32)
	var packet := PackedByteArray(HEADER + [MessageKind.HELLO, int(wants_audience)])
	packet.append_array(fingerprint)
	return packet


static func encode_command(kind: int, round_id: int, character_id := 0, ready := false, map_id := 0) -> PackedByteArray:
	var packet := PackedByteArray(HEADER + [kind])
	_append_integer(packet, round_id, 4)
	if kind == MessageKind.SELECT_CHARACTER or kind == MessageKind.SET_READY:
		_append_integer(packet, character_id, 2)
	if kind == MessageKind.SELECT_ARENA:
		_append_integer(packet, map_id, 2)
	if kind == MessageKind.SET_READY:
		_append_integer(packet, map_id, 2)
		packet.append(int(ready))
	return packet


static func _append_integer(packet: PackedByteArray, value: int, length: int) -> void:
	for index in length:
		packet.append((value >> (index * 8)) & 255)


static func _read_integer(packet: PackedByteArray, offset: int, length: int) -> int:
	var result := 0
	for index in length:
		result |= packet[offset + index] << (index * 8)
	return result


static func decode(packet: PackedByteArray, channel: int) -> DecodedMessage:
	if packet.size() < 6 or packet.slice(0, 5) != PackedByteArray(HEADER):
		return _invalid("The host and client must use the same protocol.")
	var expected_channel := 1 if packet[5] == MessageKind.WORLD_STATE else 0
	if channel != expected_channel:
		return _invalid("The host used the wrong message channel.")
	var message := DecodedMessage.new()
	message.kind = packet[5]
	match message.kind:
		MessageKind.WELCOME:
			if packet.size() != 11 or packet[6] > 2:
				return _invalid("The host sent an invalid player identity.")
			message.player_id = packet[6]
			message.audience_delay_ms = _read_integer(packet, 7, 4)
			if message.audience_delay_ms > 60000 or (message.player_id > 0 and message.audience_delay_ms != 0):
				return _invalid("The host sent an invalid audience delay.")
		MessageKind.SESSION_STATE:
			if packet.size() < 32 or packet[14] > SessionSnapshot.Phase.IN_ARENA or packet[15] > 3 or packet[31] not in [0, 2] or packet.size() != 32 + packet[31] * 20:
				return _invalid("The host sent an invalid session state.")
			var snapshot := SessionSnapshot.new(packet[15], _read_integer(packet, 16, 2))
			if snapshot.audience_count + snapshot.player_count() > 4095:
				return _invalid("The host sent an invalid connection count.")
			snapshot.round_id = _read_integer(packet, 6, 4)
			snapshot.revision = _read_integer(packet, 10, 4)
			snapshot.phase = packet[14]
			snapshot.map_id = _read_integer(packet, 18, 2)
			snapshot.countdown_seconds = packet[26]
			snapshot.server_tick = _read_integer(packet, 27, 4)
			if (snapshot.phase == SessionSnapshot.Phase.LOBBY) != (snapshot.map_id == 0):
				return _invalid("Arena selection does not match the session phase.")
			if snapshot.phase != SessionSnapshot.Phase.LOBBY and snapshot.player_mask != 3:
				return _invalid("Selection requires both players.")
			for index in 2:
				var offset := 20 + index * 3
				var player := snapshot.players[index]
				player.character_id = _read_integer(packet, offset, 2)
				if packet[offset + 2] > 1:
					return _invalid("The host sent an invalid Ready value.")
				player.ready = packet[offset + 2] == 1
				if player.ready and player.character_id == 0:
					return _invalid("A Ready player must have a character.")
				if (not player.present or snapshot.phase == SessionSnapshot.Phase.LOBBY) and (player.character_id != 0 or player.ready):
					return _invalid("Character selection does not match the session phase.")
			if snapshot.phase == SessionSnapshot.Phase.COUNTDOWN:
				if not snapshot.both_ready() or snapshot.countdown_seconds < 1 or snapshot.countdown_seconds > 5:
					return _invalid("The host sent an invalid countdown.")
			elif snapshot.countdown_seconds != 0:
				return _invalid("Countdown does not match the phase.")
			if snapshot.phase == SessionSnapshot.Phase.IN_ARENA:
				if not snapshot.both_ready() or packet[31] != 2 or not _read_characters(packet, 32, snapshot):
					return _invalid("The host sent invalid characters.")
				for character in snapshot.characters:
					if character.definition_id != snapshot.players[character.owner_id - 1].character_id:
						return _invalid("Spawned characters differ from the selections.")
			elif packet[31] != 0:
				return _invalid("Characters arrived before arena entry.")
			message.session = snapshot
		MessageKind.WORLD_STATE:
			if packet.size() != 55 or packet[14] != 2:
				return _invalid("The host sent an invalid world state.")
			message.session = SessionSnapshot.new()
			message.session.round_id = _read_integer(packet, 6, 4)
			message.session.server_tick = _read_integer(packet, 10, 4)
			if not _read_characters(packet, 15, message.session):
				return _invalid("The host sent invalid character positions.")
		MessageKind.COMMAND_REJECTED:
			if packet.size() != 12 or packet[10] not in [MessageKind.START_SELECTION, MessageKind.SELECT_CHARACTER, MessageKind.SET_READY, MessageKind.SELECT_ARENA, MessageKind.RETURN_TO_LOBBY, MessageKind.INPUT] or packet[11] < 1 or packet[11] > CommandRejectReason.ARENA_CHANGED:
				return _invalid("The host sent an invalid command rejection.")
			message.round_id = _read_integer(packet, 6, 4)
			message.rejected_kind = packet[10]
			message.rejection_reason = packet[11]
		_:
			return _invalid("The host sent an unknown message.")
	return message


static func rejection_text(reason: int) -> String:
	match reason:
		CommandRejectReason.AUDIENCE_READ_ONLY: return "Audience members can watch both players' selections."
		CommandRejectReason.WRONG_PHASE: return "The session has moved on. Try your action again."
		CommandRejectReason.STALE_ROUND: return "The round changed. Try your action again."
		CommandRejectReason.UNKNOWN_CHARACTER: return "That character is not in the host's catalog."
		CommandRejectReason.SELECTION_CHANGED: return "Choose a character, then confirm that selection with Ready."
		CommandRejectReason.NEED_TWO_PLAYERS: return "Waiting for a second player."
		CommandRejectReason.UNKNOWN_ARENA: return "That arena is not in the host catalog."
		CommandRejectReason.ARENA_CHANGED: return "The arena changed. Review it before pressing Ready."
	return "The host could not accept that action."


static func _invalid(detail: String) -> DecodedMessage:
	var message := DecodedMessage.new()
	message.error_title = "Invalid host reply"
	message.error_detail = detail
	return message


static func encode_input(round_id: int, sequence: int, mask: int) -> PackedByteArray:
	var packet := PackedByteArray(HEADER + [MessageKind.INPUT])
	_append_integer(packet, round_id, 4)
	_append_integer(packet, sequence, 4)
	packet.append(mask)
	return packet


static func serial_is_newer(value: int, previous: int) -> bool:
	var distance := (value - previous) & 0xffffffff
	return distance > 0 and distance < 0x80000000


static func _read_characters(packet: PackedByteArray, start: int, snapshot: SessionSnapshot) -> bool:
	var ids: Dictionary = {}
	var owners: Dictionary = {}
	for index in 2:
		var offset := start + index * 20
		var character := SessionSnapshot.CharacterState.new()
		character.entity_id = _read_integer(packet, offset, 4)
		character.definition_id = _read_integer(packet, offset + 4, 2)
		character.owner_id = packet[offset + 6]
		character.position = Vector2(_read_integer(packet, offset + 7, 4), _read_integer(packet, offset + 11, 4)) / 256.0
		character.applied_input_sequence = _read_integer(packet, offset + 15, 4)
		character.input_mask = packet[offset + 19]
		if character.entity_id == 0 or character.definition_id == 0 or character.owner_id not in [1, 2] or character.input_mask > 15 or ids.has(character.entity_id) or owners.has(character.owner_id) or character.position.x > 16384 or character.position.y > 16384:
			return false
		ids[character.entity_id] = true
		owners[character.owner_id] = true
		snapshot.characters.append(character)
	return true
