class_name TrainerMovement
extends RefCounted

const Snapshot = preload("res://session/session_snapshot.gd")
const Protocol = preload("res://network/protocol.gd")
const Movement = preload("res://world/character_movement.gd")


static func copy_state(source: Snapshot.TrainerState) -> Snapshot.TrainerState:
	var state := Snapshot.TrainerState.new()
	for field in ["entity_id", "definition_id", "owner_id", "position", "applied_input_sequence", "input_mask", "locomotion", "facing", "state_start_tick"]:
		state.set(field, source.get(field))
	return state


# Replayable fixed-step counterpart of server/trainers.odin. Input chooses an
# action immediately; the action's first planted step gates translation.
static func step(state: Snapshot.TrainerState, mask: int, tick: int, arena, catalog) -> void:
	state.input_mask = mask
	var next := Movement.move(state.position, mask, Protocol.TRAINER_RADIUS, arena, catalog)
	var displacement := next - state.position
	var locomotion := 1 if displacement.length_squared() > 0.000001 else 0
	if state.locomotion != locomotion:
		state.locomotion = locomotion
		state.state_start_tick = tick
	if locomotion == 0: return
	state.facing = (roundi(atan2(displacement.x, -displacement.y) / (PI / 4.0)) + 8) % 8
	if ((tick - state.state_start_tick) & 0xffffffff) >= Protocol.TRAINER_WALK_START_TICKS:
		state.position = next
