package main

import ai "ai"

Battle_Runtime :: struct {
    round_id: u32,
    agents: [MAX_PLAYERS]ai.Agent,
    anchors: [MAX_PLAYERS][2]f32,
    config: ai.Wander_Config,
    bound: bool,
}

battle_sync :: proc(battle: ^Battle_Runtime, session: ^Session, seed: u32) {
    if session.phase != .In_Arena { battle^ = {}; return }
    same := battle.bound && battle.round_id == session.round_id
    for c, index in session.characters { same = same && battle.agents[index].entity_id == c.entity_id }
    if same { return }
    battle^ = Battle_Runtime{bound = true, round_id = session.round_id, config = ai.wander_defaults()}
    assert(ai.wander_config_valid(battle.config))
    for character, index in session.characters {
        battle.agents[index] = ai.agent_reset(character.entity_id, session.round_id, seed)
        battle.anchors[index] = character.position
    }
}

battle_tick :: proc(battle: ^Battle_Runtime, session: ^Session, content: ^Game_Content, can_move: bool) {
    // Build both contexts before executing either action. Future sensing uses the
    // same start-of-tick world sample, never a partially moved opponent.
    contexts: [MAX_PLAYERS]ai.Decision_Context
    intents: [MAX_PLAYERS]ai.Intent
    for character, index in session.characters {
        contexts[index] = {entity_id = character.entity_id, round_id = session.round_id, tick = session.server_tick,
            position = character.position, anchor = battle.anchors[index], can_move = can_move}
    }
    for ctx, index in contexts {
        intents[index] = ai.agent_decide(&battle.agents[index], ctx, battle.config)
    }
    for intent, index in intents {
        result := character_resolve_intent(&session.characters[index], session, content, intent,
            battle.anchors[index], {battle.config.speed, battle.config.roam_radius}, can_move)
        ai.agent_record_result(&battle.agents[index], result, session.server_tick, battle.config)
    }
}
