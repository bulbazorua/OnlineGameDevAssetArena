package main

import ai "ai"
import obs "observations"
import "core:sync"
import "core:time"

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

battle_sync :: proc(battle: ^Battle_Runtime, session: ^Session, content: ^Game_Content, seed: u32 = 1, controller: ai.Controller = .Observe) {
    if session.phase != .In_Arena {
        if battle.bound { battle^ = {} }
        return
    }
    if !battle.bound || battle.round_id != session.round_id {
        // A new round starts every creature from nothing, on clean ground.
        battle^ = Battle_Runtime{bound = true, round_id = session.round_id, config = ai.observe_defaults(), limits = BATTLE_MOVE_LIMITS, seed = seed, controller = controller}
        assert(ai.observe_config_valid(battle.config))
        scent_environment_bind(&battle.scent, session, content)
        for index in 0..<MAX_PLAYERS { battle_bind_creature(battle, session, content, index) }
        return
    }
    // Replacing one creature clears only that creature; the other keeps its private state.
    for character, index in session.characters {
        if battle.agents[index].entity_id != character.entity_id { battle_bind_creature(battle, session, content, index) }
    }
}

// Fresh private runtime for one slot: empty mind, spawn anchor, bound receptors,
// a re-armed emitter and no turn timing. Old scent on the ground is untouched.
@(private)
battle_bind_creature :: proc(battle: ^Battle_Runtime, session: ^Session, content: ^Game_Content, index: int) {
    character := session.characters[index]
    battle.agents[index] = ai.agent_reset(character.entity_id, session.round_id, battle.controller, battle.seed)
    battle.anchors[index] = character.position
    receptor_bind(&battle.receptors[index], content_character(content, character.definition_id))
    scent_environment_bind_creature(&battle.scent, session, content, index)
    battle.actions[index] = {}
    session.characters[index].target_alert = false
    session.characters[index].target_acquired_tick = 0
}

battle_tick :: proc(battle: ^Battle_Runtime, session: ^Session, content: ^Game_Content, can_act: bool,
                    workers: ^Brain_Workers = nil, debug: ^AI_Debug = nil) {
    // Bodies mark the ground first, then one frozen world phase feeds both
    // observers before either creature acts. A worker receives only its own
    // samples, self condition and private agent: never the field or the map.
    scent_environment_tick(&battle.scent, session, content, can_act)
    inputs := senses_prepare(battle, session, content, can_act)
    contexts: [MAX_PLAYERS]ai.Decision_Context
    intents: [MAX_PLAYERS]ai.Intent
    before := battle.agents
    responses: [MAX_PLAYERS]Brain_Response
    for character, index in session.characters {
        contexts[index] = {entity_id = character.entity_id, round_id = session.round_id, tick = session.server_tick,
            position = character.position, facing = character_facing_to_observation(character.facing), can_act = can_act,
            turn_ready = character_turn_ready(&battle.actions[index], session.server_tick), senses = inputs[index],
            own_emitter = battle.scent.emitters[index].emitter}
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
            battle.anchors[index], battle.limits, can_act, &battle.actions[index])
        ai.agent_record_result(&battle.agents[index], result, session.server_tick, battle.config)
        search := battle.agents[index].search
        session.characters[index].target_alert = can_act && search.acquisition_count > 0 && session.server_tick - search.acquired_tick < 60
        session.characters[index].target_acquired_tick = search.acquired_tick
        if debug != nil {
            response := &responses[index]
            ai.trace_add(&response.trace, 1, .Outcome, .Resolved, "Host resolved intent; inspect confirmed action result",
                "confirmed_facing", f64(result.facing), 0, result.displacement)
            start_us := i64(time.tick_diff(debug.origin, response.started) / time.Microsecond)
            ai_debug_enqueue(debug, AI_Debug_Record{owner_id = index + 1, definition_id = session.characters[index].definition_id,
                map_id = session.map_id, facing = facing, input = contexts[index], config = battle.config, before = before[index], after = battle.agents[index],
                decision_reason = decision_reason, result = result, position_after = session.characters[index].position,
                facing_after = u8(session.characters[index].facing), audit = battle.receptors[index].vision.audit,
                scent_audit = battle.receptors[index].olfaction.audit,
                worker_id = response.worker_id, queued_us = start_us - response.queue_us, started_us = start_us,
                finished_us = start_us + response.compute_us, trace = response.trace})
        }
    }
}
