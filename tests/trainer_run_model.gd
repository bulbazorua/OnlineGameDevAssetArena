extends RefCounted

const Motion = preload("res://players/trainer_movement.gd")
const Protocol = preload("res://network/protocol.gd")
const Catalog = preload("res://content/arena_catalog.gd")
const Player = preload("res://players/player_view.gd")
const Character = preload("res://characters/character_view.gd")
const Presenter = preload("res://characters/character_motion_presenter.gd")


static func check(content) -> String:
	var arena := Catalog.ArenaDefinition.new()
	arena.width = 64
	arena.height = 32
	arena.tile_size = 32
	arena.cells.resize(64 * 32)
	arena.cells.fill(1)
	var state := Motion.Snapshot.TrainerState.new()
	state.position = Vector2(256, 256)
	var saved: Motion.Snapshot.TrainerState
	var travelled := 0.0
	for step in 308:
		var previous := state.position
		Motion.step(state, _mask(step), 100 + step, arena, content.arena_catalog)
		travelled += state.position.distance_to(previous)
		if step < 8 and (state.energy != 600 or state.position != previous): return "Run preparation moved or consumed energy."
		if step >= 8 and state.energy != 600 - (step - 7) * 2: return "Run energy differs from the five-second host contract."
		if step == 157: saved = Motion.copy_state(state)
	if travelled != 1200 or state.energy != 0 or not state.run_exhausted: return "A full run did not cover five seconds at twice walking speed."
	var replay := Motion.copy_state(saved)
	for step in range(158, 308): Motion.step(replay, _mask(step), 100 + step, arena, content.arena_catalog)
	if replay.position != state.position or replay.energy != state.energy or replay.run_exhausted != state.run_exhausted or saved.energy == 0: return "Input replay lost stamina or changed the host snapshot."
	var last := state.position
	Motion.step(state, 18, 408, arena, content.arena_catalog)
	if state.position != last + Vector2(2, 0) or state.locomotion != 1: return "Exhaustion interrupted walking or kept run speed."
	for tick in range(409, 588): Motion.step(state, 18, tick, arena, content.arena_catalog)
	if state.energy != 120 or not state.run_exhausted or state.locomotion == 2: return "Holding Space bypassed the exhaustion lock."
	Motion.step(state, 2, 588, arena, content.arena_catalog)
	if state.run_exhausted: return "Release after recovery did not unlock running."
	Motion.step(state, 17, 589, arena, content.arena_catalog)
	if state.locomotion != 2 or state.movement_start_tick != 100: return "Walk/run switches repeated movement preparation."
	var view := Player.new()
	content.player_content.configure_view(view, 1, 1)
	view.present_locomotion("run", "east", 0.12)
	var binding: Dictionary = view.animation_set.binding_for("run", "east", "default")
	var frame: Dictionary = view.animation_set.sample(binding, 0.12)
	var correct: bool = view.body_sprite.visible and view.presented_frame == frame.frame and view.body_sprite.texture == frame.texture
	view.free()
	if not correct: return "Trainer did not use its real run clip."
	for definition_id in [5, 6]:
		var creature := Character.new()
		content.configure_character(creature, definition_id, 1, content.by_id[definition_id].footprint_radius)
		var error := _check_hop(creature)
		creature.free()
		if not error.is_empty(): return "%s: %s" % [content.by_id[definition_id].key, error]
	return ""


static func _mask(step: int) -> int:
	return (2 if (step / 75) % 2 == 0 else 1) | 16


static func _check_hop(view: Character) -> String:
	view.position = Vector2(72, 150)
	view.present_locomotion("idle", "east", 0)
	view.present_target_alert(true, 0)
	var baseline := view.body_sprite.position
	var marker_gap := view.body_bounds().position.y - view.target_alert.position.y
	view.present_target_alert(true, 0.18)
	if not view.body_sprite.visible or view.body_sprite.position.y >= baseline.y - 10: return "The creature body did not jump."
	if view.position != Vector2(72, 150) or view.radius != 12: return "The reaction moved the creature's ground position or footprint."
	if not view.surprise_hop.visible or view.surprise_hop.position != Vector2.ZERO: return "The shadow is not planted at the creature's feet."
	if not is_equal_approx(view.body_bounds().position.y - view.target_alert.position.y, marker_gap): return "The exclamation is hopping independently of the creature."
	view.present_locomotion("walk", "west", 0.15)
	if view.body_sprite.position.y >= baseline.y - 10: return "Changing the walk frame cancelled the creature's jump."
	view.present_target_alert(true, 0.36)
	if view.body_sprite.position != baseline or view.surprise_hop.visible or not view.target_alert.visible: return "The creature did not land while its exclamation stayed visible."
	view.present_target_alert(true, 0.18)
	var frozen := view.body_sprite.position
	view.present_target_alert(true, 0.18)
	if view.body_sprite.position != frozen: return "The same replay age changed the body pose."
	for active in [false, true]:
		view.present_target_alert(active, 1.0 if active else 0.1)
		if view.body_sprite.position != baseline or view.surprise_hop.visible or view.target_alert.visible: return "An expired or cleared reaction left the creature airborne."
	var state := Motion.Snapshot.CharacterState.new()
	state.position = view.position
	state.target_alert = true
	state.target_acquired_tick = 100
	var presenter := Presenter.new(view)
	presenter.push(state, 111)
	if view.body_sprite.position.y >= baseline.y - 10: return "The live motion presenter did not make the creature jump."
	frozen = view.body_sprite.position
	presenter.advance(2.0)
	if view.body_sprite.position != frozen: return "A frozen battle clock kept advancing the creature's hop."
	view.configure_art(view.animation_set, 1, view.preview_size, 0.375)
	if view.body_sprite.position != baseline or view.target_alert.visible or view.surprise_hop.visible: return "Reconfiguring a creature retained its previous hop."
	return ""
