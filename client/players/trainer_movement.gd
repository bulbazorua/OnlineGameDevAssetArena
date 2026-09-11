class_name TrainerMovement
extends RefCounted

const Snapshot = preload("res://session/session_snapshot.gd")
const Protocol = preload("res://network/protocol.gd")
const Movement = preload("res://world/character_movement.gd")


static func copy_state(source: Snapshot.TrainerState) -> Snapshot.TrainerState:
	var state := Snapshot.TrainerState.new()
	for field in ["entity_id", "definition_id", "owner_id", "position", "applied_input_sequence", "input_mask", "locomotion", "facing", "state_start_tick", "energy", "energy_recovery_ticks", "run_exhausted", "movement_start_tick"]:
		state.set(field, source.get(field))
	return state


# Replayable fixed-step counterpart of server/trainers.odin. Input chooses an
# action immediately; the action's first planted step gates translation.
static func step(state: Snapshot.TrainerState, mask: int, tick: int, arena, catalog) -> void:
	state.input_mask = mask
	var wants_run := (mask & Protocol.TRAINER_RUN_INPUT) != 0
	if not wants_run and state.energy >= Protocol.TRAINER_RECOVERY_THRESHOLD: state.run_exhausted = false
	var running := wants_run and not state.run_exhausted and state.energy >= Protocol.TRAINER_RUN_COST
	var speed := Protocol.TRAINER_RUN_SPEED if running else Movement.SPEED
	var next := Movement.move(state.position, mask, Protocol.TRAINER_RADIUS, arena, catalog, speed)
	var displacement := next - state.position
	var locomotion := 1 if displacement.length_squared() > 0.000001 else 0
	if locomotion == 1 and running: locomotion = 2
	if state.locomotion == 0 and locomotion != 0: state.movement_start_tick = tick
	if state.locomotion != locomotion:
		state.locomotion = locomotion
		state.state_start_tick = tick
	var moving := locomotion != 0 and ((tick - state.movement_start_tick) & 0xffffffff) >= Protocol.TRAINER_WALK_START_TICKS
	if locomotion != 0:
		state.facing = (roundi(atan2(displacement.x, -displacement.y) / (PI / 4.0)) + 8) % 8
		if moving: state.position = next
	_tick_energy(state, moving and running)


static func _tick_energy(state: Snapshot.TrainerState, running: bool) -> void:
	if running:
		state.energy -= Protocol.TRAINER_RUN_COST
		state.energy_recovery_ticks = Protocol.TRAINER_RECOVERY_DELAY
		if state.energy < Protocol.TRAINER_RUN_COST: state.run_exhausted = true
	elif state.energy_recovery_ticks > 0: state.energy_recovery_ticks -= 1
	else: state.energy = mini(Protocol.TRAINER_ENERGY_MAX, state.energy + 1)
