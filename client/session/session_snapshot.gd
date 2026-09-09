class_name SessionSnapshot
extends RefCounted

enum Phase { LOBBY, SELECTING, COUNTDOWN, IN_ARENA }

class PlayerSlotState:
	extends RefCounted
	var present: bool
	var character_id := 0
	var ready := false

	func _init(is_present := false) -> void:
		present = is_present

class CharacterState:
	extends RefCounted
	var entity_id := 0
	var definition_id := 0
	var owner_id := 0
	var position := Vector2.ZERO
	var applied_input_sequence := 0
	var input_mask := 0

var countdown_seconds := 0
var server_tick := 0
var characters: Array[CharacterState] = []
var players: Array[PlayerSlotState] = []
var audience_count: int
var round_id := 0
var revision := 0
var map_id := 0
var phase := Phase.LOBBY
var player_mask: int:
	get:
		return int(players[0].present) | (int(players[1].present) << 1)


func _init(mask := 0, audience := 0) -> void:
	players = [PlayerSlotState.new((mask & 1) != 0), PlayerSlotState.new((mask & 2) != 0)]
	audience_count = audience


func player_count() -> int:
	return int(players[0].present) + int(players[1].present)


func both_ready() -> bool:
	return player_mask == 3 and players[0].ready and players[1].ready


# Published snapshots are replaced, never modified underneath a screen.
func with_world(world: SessionSnapshot) -> SessionSnapshot:
	var result := SessionSnapshot.new(player_mask, audience_count)
	result.round_id = round_id
	result.revision = revision
	result.map_id = map_id
	result.phase = phase
	result.countdown_seconds = countdown_seconds
	for index in 2:
		result.players[index].character_id = players[index].character_id
		result.players[index].ready = players[index].ready
	result.server_tick = world.server_tick
	result.characters = world.characters
	return result
