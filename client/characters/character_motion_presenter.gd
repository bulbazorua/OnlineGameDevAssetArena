class_name CharacterMotionPresenter
extends RefCounted

const Snapshot = preload("res://session/session_snapshot.gd")
const Protocol = preload("res://network/protocol.gd")
const View = preload("res://characters/character_view.gd")
var view: View
var previous: Snapshot.CharacterState
var current: Snapshot.CharacterState
var current_tick := 0
var from_position := Vector2.ZERO
var from_tick := 0.0
var target_tick := 0.0
var sample_tick := 0.0
var elapsed := 0.0
var interval := 0.0
var walk_start_ticks := Protocol.CHARACTER_WALK_START_TICKS


func _init(character_view: View, preparation_ticks := Protocol.CHARACTER_WALK_START_TICKS) -> void:
	view = character_view
	walk_start_ticks = preparation_ticks


func push(state: Snapshot.CharacterState, tick: int) -> void:
	if current != null and not Protocol.serial_is_newer(tick, current_tick): return
	var gap := 0 if current == null else ((tick - current_tick) & 0xffffffff)
	if current == null or gap > 30:
		previous = state
		from_position = state.position
		target_tick = float(tick)
		sample_tick = target_tick
	else:
		# Continue from the actually displayed time and pose. Retargeting from
		# the last packet's tick could skip the first step on an early packet.
		previous = _sample_state()
		from_position = view.position
		target_tick += float(gap)
	from_tick = sample_tick
	current = state
	current_tick = tick
	elapsed = 0.0
	interval = minf((target_tick - from_tick) / 60.0, 0.15)
	advance(0.0)


func advance(delta: float) -> void:
	if current == null: return
	elapsed = minf(elapsed + delta, interval)
	var weight := 1.0 if interval == 0.0 else elapsed / interval
	sample_tick = lerpf(from_tick, target_tick, weight)
	view.position = from_position.lerp(current.position, _position_weight())
	var sample := _sample_state()
	var age := maxf(sample_tick - _state_tick(sample), 0.0)
	view.present_locomotion(Protocol.LOCOMOTION_NAMES[sample.locomotion], Protocol.FACING_NAMES[sample.facing], age / 60.0)
	if not sample is Snapshot.TrainerState:
		var acquired := target_tick - float((current_tick - current.target_acquired_tick) & 0xffffffff)
		view.present_target_alert(current.target_alert, maxf(0, sample_tick - acquired) / 60.0)


func _state_tick(state: Snapshot.CharacterState) -> float:
	# Unwrap the u32 host clock around the latest received sample.
	return target_tick - float((current_tick - state.state_start_tick) & 0xffffffff)


func _sample_state() -> Snapshot.CharacterState:
	return current if sample_tick >= _state_tick(current) else previous


func _position_weight() -> float:
	var begin := from_tick
	var end := target_tick
	if current.locomotion != 0:
		# Tick N stores the result of movement over (N-1, N]. Do not smear
		# that first displacement backward over idle or the planted step.
		var movement_tick := _state_tick(current)
		if current is Snapshot.TrainerState: movement_tick = target_tick - float((current_tick - current.movement_start_tick) & 0xffffffff)
		begin = maxf(begin, movement_tick + walk_start_ticks - 1)
	elif previous.locomotion != 0:
		# Complete the last movement before displaying the idle pose.
		end = minf(end, _state_tick(current) - 1)
	if end <= begin:
		return 1.0 if sample_tick >= end else 0.0
	return clampf((sample_tick - begin) / (end - begin), 0.0, 1.0)
