package main

import ai "ai"
import "core:sync"
import "core:time"

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

battle_tick :: proc(battle: ^Battle_Runtime, session: ^Session, content: ^Game_Content, can_move: bool,
                    workers: ^Brain_Workers = nil, debug: ^AI_Debug = nil) {
    // Build both contexts before executing either action. Future sensing uses the
    // same start-of-tick world sample, never a partially moved opponent.
    contexts: [MAX_PLAYERS]ai.Decision_Context
    intents: [MAX_PLAYERS]ai.Intent
    before := battle.agents
    responses: [MAX_PLAYERS]Brain_Response
    for character, index in session.characters {
        contexts[index] = {entity_id = character.entity_id, round_id = session.round_id, tick = session.server_tick,
            position = character.position, anchor = battle.anchors[index], can_move = can_move}
    }
    if workers != nil {
        for ctx, index in contexts {
            brain_worker_submit(&workers.slots[index], {agent = before[index], ctx = ctx, config = battle.config, trace = debug != nil})
        }
        // Both independent threads have their input before either join.
        for index in 0..<MAX_PLAYERS {
            responses[index] = brain_worker_collect(&workers.slots[index])
            assert(responses[index].agent.entity_id == contexts[index].entity_id && responses[index].agent.last.tick == contexts[index].tick)
            battle.agents[index] = responses[index].agent
            intents[index] = responses[index].intent
        }
    } else {
        // Serial reference for deterministic tests and headless simulations.
        for ctx, index in contexts {
            trace: ^ai.Trace_Buffer
            if debug != nil { trace = &responses[index].trace }
            responses[index].started = time.tick_now()
            intents[index] = ai.agent_decide(&battle.agents[index], ctx, battle.config, trace)
            responses[index].worker_id = sync.current_thread_id()
            responses[index].compute_us = i64(time.tick_since(responses[index].started) / time.Microsecond)
        }
    }
    for intent, index in intents {
        decision_reason := battle.agents[index].last.reason
        facing := u8(session.characters[index].facing)
        result := character_resolve_intent(&session.characters[index], session, content, intent,
            battle.anchors[index], {battle.config.speed, battle.config.roam_radius}, can_move)
        ai.agent_record_result(&battle.agents[index], result, session.server_tick, battle.config)
        if debug != nil {
            response := &responses[index]
            ai.trace_add(&response.trace, 1, .Outcome, .Resolved, "Host resolved intent; inspect confirmed action result",
                direction = result.displacement)
            start_us := i64(time.tick_diff(debug.origin, response.started) / time.Microsecond)
            ai_debug_enqueue(debug, AI_Debug_Record{owner_id = index + 1, definition_id = session.characters[index].definition_id,
                map_id = session.map_id, facing = facing, input = contexts[index], config = battle.config, before = before[index], after = battle.agents[index],
                decision_reason = decision_reason, result = result, position_after = session.characters[index].position,
                worker_id = response.worker_id, queued_us = start_us - response.queue_us, started_us = start_us,
                finished_us = start_us + response.compute_us, trace = response.trace})
        }
    }
}
