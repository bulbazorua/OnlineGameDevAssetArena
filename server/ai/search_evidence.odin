package ai

import obs "../observations"

search_set_state :: proc(search: ^Search_Runtime, state: Search_State, reason: Search_Transition, tick: u32) {
    if search.state == state && search.started { return }
    if state == .Extensive_Search && search.started { search.abandoned_count += 1 }
    search.state, search.transition, search.state_tick = state, reason, tick
    search.leg_active, search.relocating = false, false
}

search_focused_opponent :: proc(search: ^Search_Runtime, sample: obs.Vision_Sample, position: Vector) -> int {
    chosen := -1
    sightings := sample.focused
    for sighting, i in sightings[:sample.focused_count] {
        if sighting.kind != .Creature { continue }
        if sighting.subject == search.target { return i }
        if chosen < 0 || distance_between(position, sighting.position) < distance_between(position, sample.focused[chosen].position) { chosen = i }
    }
    return chosen
}

search_accept_target :: proc(search: ^Search_Runtime, sample: obs.Vision_Sample, index: int, tick: u32) {
    sighting := sample.focused[index]
    if search.acquisition_count == 0 || search.target != sighting.subject || sample.sample_tick - search.target_tick > 18 {
        search.acquired_tick = tick
        search.acquisition_count += 1
    }
    search.target, search.target_position, search.target_tick = sighting.subject, sighting.position, sample.sample_tick
    search.weak_episode_active, search.cue_cooldown = false, false
    search.target_visible, search.center_valid = true, true
    search.center, search.evidence_tick, search.observation_id = sighting.position, sample.sample_tick, sighting.observation_id
    search.evidence, search.confidence, search.cue_valid = .Focused, 1, false
    search_set_state(search, .Pursue, .Focused_Opponent, tick)
}

search_read_evidence :: proc(agent: ^Agent, ctx: Decision_Context, config: Observe_Config) {
    search := &agent.search
    sample := ctx.senses.vision
    was_visible := search.target_visible
    search.target_visible = false
    current := sample.status == .Sampled && ctx.tick - sample.sample_tick <= max(1, sample.profile.sample_interval * 2)
    if current {
        chosen := search_focused_opponent(search, sample, ctx.position)
        if chosen >= 0 { search_accept_target(search, sample, chosen, ctx.tick); return }
    }
    if search.target != 0 && ctx.tick - search.target_tick < config.memory.focused_retention_ticks {
        search.evidence = .Focused_Memory
        search.confidence = search_memory_strength(ctx.tick, search.target_tick, config.memory.focused_retention_ticks)
        if distance_between(ctx.position, search.target_position) > search.profile.arrival_radius {
            search_set_state(search, .Last_Known_Position, .Target_Lost, ctx.tick)
        } else { search_set_state(search, .Intensive_Search, .Reached_Last_Position, ctx.tick) }
        return
    }
    search.target, search.target_position, search.target_tick = 0, {}, 0
    if search.cue_cooldown && tick_due(ctx.tick, search.ignore_cues_until) { search.cue_cooldown = false }
    // One budget for every weak lead, visual or smelled: eight seconds without an
    // opponent ends the episode and weak evidence is ignored for a while.
    if search.weak_episode_active && ctx.tick - search.weak_episode_tick >= search.profile.evidence_ticks {
        search.weak_episode_active, search.cue_cooldown = false, true
        search.ignore_cues_until = ctx.tick + search.profile.relocation_ticks * 3
        search.cue_valid, search.center_valid, search.center = false, false, {}
        search.evidence, search.observation_id, search.confidence = .None, 0, 0
        search_set_state(search, .Extensive_Search, .Investigation_Abandoned, ctx.tick)
    }
    if current && sample.cue_count > 0 && !search.cue_cooldown {
        if !search.weak_episode_active {
            search.weak_episode_active, search.weak_episode_tick = true, ctx.tick
            search.center = sample.pose.position
        }
        cue := sample.cues[observe_choose_cue(ctx, sample)]
        direction := obs.cue_absolute_facing(sample.pose.facing, cue.sector)
        if !search.cue_valid || search.cue_from_scent || search.cue_direction != direction { search.leg_active = false }
        search.cue_valid, search.cue_tick, search.cue_direction = true, sample.sample_tick, direction
        search.cue_origin, search.cue_from_scent = sample.pose.position, false
        search.evidence, search.observation_id, search.evidence_tick = .Cue, cue.observation_id, sample.sample_tick
        search.center_valid = true
    }
    // Eyes first: a current or briefly remembered visual cue outranks any smell.
    if search.cue_valid && !search.cue_from_scent && ctx.tick - search.cue_tick < config.memory.peripheral_retention_ticks {
        search.confidence = 0.45 * search_memory_strength(ctx.tick, search.cue_tick, config.memory.peripheral_retention_ticks)
        search.evidence = .Cue if current && sample.cue_count > 0 else .Cue_Memory
        search_set_state(search, .Investigate, .Directional_Cue, ctx.tick)
        return
    }
    if search.scent.valid && !search.cue_cooldown && search_follow_scent(search, agent, ctx) { return }
    search.cue_valid, search.cue_from_scent = false, false
    if search.center_valid && ctx.tick - search.evidence_tick < search.profile.evidence_ticks {
        search.confidence = 0.25 * search_memory_strength(ctx.tick, search.evidence_tick, search.profile.evidence_ticks)
        smelled := search.evidence == .Scent || search.evidence == .Scent_Memory
        search.evidence = .Focused_Memory if was_visible || search.evidence == .Focused_Memory || search.evidence == .Focused else (.Scent_Memory if smelled else .Cue_Memory)
        search_set_state(search, .Intensive_Search, .Scent_Faded if smelled else .Cue_Expired, ctx.tick)
        return
    }
    search.center_valid, search.center, search.confidence = false, {}, 0
    search.evidence, search.observation_id = .None, 0
    search_set_state(search, .Extensive_Search, .Evidence_Expired if search.started else .No_Evidence, ctx.tick)
}
