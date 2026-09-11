package main

import obs "observations"
import "perception"
import ai "ai"

// Creatures first, then trainers: every body that can leave scent on the ground.
SCENT_EMITTER_SLOTS :: 2 * MAX_PLAYERS

// Where an emitter was last seen by the field, so this tick's deposit covers the
// ground it actually crossed. A new entity re-arms here without painting a trail.
Scent_Emitter_State :: struct {
    entity_id: u32,
    position: [2]f32,
    armed: bool,
    emitter: obs.Scent_Emitter,
}

// The round's shared scent environment: the field plus the bookkeeping that
// turns confirmed body positions into deposits on simulation time.
Scent_Environment :: struct {
    field: perception.Scent_Field,
    emitters: [SCENT_EMITTER_SLOTS]Scent_Emitter_State,
    next_step_tick: u32,
    step_armed: bool,
}

scent_environment_bind :: proc(environment: ^Scent_Environment, session: ^Session, content: ^Game_Content) {
    environment^ = {}
    arena := content_arena(content, session.map_id)
    if arena == nil { return }
    perception.scent_field_init(&environment.field, arena.width, arena.height, f32(arena.tile_size), arena.scent_media)
    for index in 0..<MAX_PLAYERS { scent_environment_bind_creature(environment, session, content, index) }
    for trainer, index in session.trainers { scent_emitter_arm(&environment.emitters[MAX_PLAYERS + index], trainer.entity_id, trainer.position, content.trainer_emitter) }
}

// Only this creature's emitter starts over; the ground keeps every old deposit.
scent_environment_bind_creature :: proc(environment: ^Scent_Environment, session: ^Session, content: ^Game_Content, index: int) {
    character := session.characters[index]
    emitter: obs.Scent_Emitter
    if definition := content_character(content, character.definition_id); definition != nil { emitter = definition.emitter }
    scent_emitter_arm(&environment.emitters[index], character.entity_id, character.position, emitter)
}

@(private = "file")
scent_emitter_arm :: proc(state: ^Scent_Emitter_State, entity_id: u32, position: [2]f32, emitter: obs.Scent_Emitter) {
    state^ = {entity_id = entity_id, position = position, armed = true, emitter = emitter}
}

// Move one emitter's record to its confirmed position, painting the crossed ground
// only while the round is live. A changed entity means a new body: re-arm, no trail.
@(private = "file")
scent_emitter_follow :: proc(field: ^perception.Scent_Field, state: ^Scent_Emitter_State, entity_id: u32, position: [2]f32, emitter: obs.Scent_Emitter, emitting: bool) {
    if !state.armed || state.entity_id != entity_id {
        scent_emitter_arm(state, entity_id, position, emitter)
        return
    }
    if emitting && emitter.enabled {
        perception.scent_field_deposit_segment(field, emitter.class, state.position, position, perception.SCENT_EMISSION_PER_TICK * emitter.intensity)
    }
    state.position, state.emitter = position, emitter
}

// One tick of the environment: confirmed positions become deposits, then the
// field spreads and fades on its own fixed schedule. Nothing here reads a brain.
scent_environment_tick :: proc(environment: ^Scent_Environment, session: ^Session, content: ^Game_Content, emitting: bool) {
    field := &environment.field
    for character, index in session.characters {
        scent_emitter_follow(field, &environment.emitters[index], character.entity_id, character.position, environment.emitters[index].emitter, emitting)
    }
    for trainer, index in session.trainers {
        scent_emitter_follow(field, &environment.emitters[MAX_PLAYERS + index], trainer.entity_id, trainer.position, content.trainer_emitter, emitting)
    }
    if !environment.step_armed {
        environment.step_armed, environment.next_step_tick = true, session.server_tick + perception.SCENT_STEP_TICKS
        return
    }
    if ai.tick_due(session.server_tick, environment.next_step_tick) {
        perception.scent_field_advance(field)
        environment.next_step_tick = session.server_tick + perception.SCENT_STEP_TICKS
    }
}
