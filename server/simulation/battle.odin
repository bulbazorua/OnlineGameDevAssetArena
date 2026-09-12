package simulation

import ai "../ai"
import "../content"

// Private per-round creature runtime: agents, receptors, action state and the
// shared scent environment. It is a sibling of Session, never copied into
// audience history or public packets.
Battle_Runtime :: struct {
    round_id: u32,
    agents: [MAX_PLAYERS]ai.Agent,
    anchors: [MAX_PLAYERS][2]f32,
    receptors: [MAX_PLAYERS]Receptor,
    actions: [MAX_PLAYERS]Character_Action_Runtime,
    scent: Scent_Environment,
    config: ai.Observe_Config,
    limits: Character_Action_Limits,
    bound: bool,
    seed: u32,
    controller: ai.Controller,
}

// Searching has no spawn leash; the host still enforces terrain and arena edges.
BATTLE_MOVE_LIMITS :: Character_Action_Limits{64, 0}

battle_sync :: proc(battle: ^Battle_Runtime, session: ^Session, catalog: ^content.Game_Content, seed: u32 = 1, controller: ai.Controller = .Observe) {
    if session.phase != .In_Arena {
        if battle.bound { battle^ = {} }
        return
    }
    if !battle.bound || battle.round_id != session.round_id {
        // A new round starts every creature from nothing, on clean ground.
        battle^ = Battle_Runtime{bound = true, round_id = session.round_id, config = ai.observe_defaults(), limits = BATTLE_MOVE_LIMITS, seed = seed, controller = controller}
        assert(ai.observe_config_valid(battle.config))
        scent_environment_bind(&battle.scent, session, catalog)
        for index in 0..<MAX_PLAYERS { battle_bind_creature(battle, session, catalog, index) }
        return
    }
    // Replacing one creature clears only that creature; the other keeps its private state.
    for character, index in session.characters {
        if battle.agents[index].entity_id != character.entity_id { battle_bind_creature(battle, session, catalog, index) }
    }
}

// Fresh private runtime for one slot: empty mind, spawn anchor, bound receptors,
// a re-armed emitter and no turn timing. Old scent on the ground is untouched.
@(private)
battle_bind_creature :: proc(battle: ^Battle_Runtime, session: ^Session, catalog: ^content.Game_Content, index: int) {
    character := session.characters[index]
    battle.agents[index] = ai.agent_reset(character.entity_id, session.round_id, battle.controller, battle.seed)
    battle.anchors[index] = character.position
    receptor_bind(&battle.receptors[index], content.find_character(catalog, character.definition_id))
    scent_environment_bind_creature(&battle.scent, session, catalog, index)
    battle.actions[index] = {}
    session.characters[index].target_alert = false
    session.characters[index].target_acquired_tick = 0
}

// What one creature's decision came to this tick. Host diagnostics read it; the
// simulation itself never looks back at it.
Decision_Outcome :: struct {
    decision_reason: ai.Decision_Reason,
    result: ai.Action_Result,
    position_after: [2]f32,
    facing_after: u8,
}

// Bodies mark the ground first, then one frozen world phase feeds both observers
// before either creature acts. A request carries only that creature's own samples,
// self condition and private agent: never the field or the map.
battle_prepare_decisions :: proc(battle: ^Battle_Runtime, session: ^Session, catalog: ^content.Game_Content, can_act: bool, trace: bool) -> (requests: [MAX_PLAYERS]Brain_Request) {
    scent_environment_tick(&battle.scent, session, catalog, can_act)
    inputs := senses_prepare(&battle.receptors, &battle.scent.field, session, catalog, can_act)
    for character, index in session.characters {
        ctx := ai.Decision_Context{entity_id = character.entity_id, round_id = session.round_id, tick = session.server_tick,
            position = character.position, facing = character_facing_to_observation(character.facing), can_act = can_act,
            turn_ready = character_turn_ready(&battle.actions[index], session.server_tick), senses = inputs[index],
            own_emitter = battle.scent.emitters[index].emitter,
            motion = {maximum_speed = battle.limits.speed,
                footprint_radius = content.find_character(catalog, character.definition_id).footprint_radius,
                tick_seconds = 1.0 / SIMULATION_HZ}}
        requests[index] = {agent = battle.agents[index], ctx = ctx, config = battle.config, trace = trace}
    }
    return
}

// Adopt both decided minds, then resolve each intent in slot order so every
// creature gets its own confirmed result before the next creature moves.
battle_resolve_decisions :: proc(battle: ^Battle_Runtime, session: ^Session, catalog: ^content.Game_Content, can_act: bool, responses: [MAX_PLAYERS]Brain_Response) -> (outcomes: [MAX_PLAYERS]Decision_Outcome) {
    for response, index in responses {
        assert(response.agent.entity_id == session.characters[index].entity_id && response.agent.last.tick == session.server_tick)
        battle.agents[index] = response.agent
    }
    for response, index in responses {
        outcomes[index] = battle_resolve_creature(battle, session, catalog, index, response.intent, can_act)
    }
    return
}

// The resolver alone moves the body; the agent then learns what really happened.
@(private)
battle_resolve_creature :: proc(battle: ^Battle_Runtime, session: ^Session, catalog: ^content.Game_Content, index: int, intent: ai.Intent, can_act: bool) -> Decision_Outcome {
    agent := &battle.agents[index]
    character := &session.characters[index]
    decision_reason := agent.last.reason
    result := character_resolve_intent(character, session, catalog, intent, battle.anchors[index], battle.limits, can_act, &battle.actions[index])
    ai.agent_record_result(agent, result, session.server_tick, battle.config)
    search := agent.search
    character.target_alert = can_act && search.acquisition_count > 0 && session.server_tick - search.acquired_tick < 60
    character.target_acquired_tick = search.acquired_tick
    return {decision_reason, result, character.position, u8(character.facing)}
}
