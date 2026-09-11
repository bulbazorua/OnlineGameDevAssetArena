package ai

import obs "../observations"

// How much a smell alone is trusted, by strength; always below a visual cue.
@(private = "file")
scent_confidence :: proc(strength: obs.Scent_Strength, freshness: obs.Scent_Freshness) -> f32 {
    base: f32
    switch strength {
    case .None: base = 0
    case .Weak: base = 0.2
    case .Medium: base = 0.3
    case .Strong: base = 0.4
    }
    if freshness == .Old { base *= 0.7 }
    return base
}

@(private = "file")
scent_strength_weight :: proc(strength: obs.Scent_Strength) -> f32 {
    switch strength {
    case .None: return 0
    case .Weak: return 1
    case .Medium: return 2
    case .Strong: return 3
    }
    return 0
}

@(private = "file")
scent_freshness_rank :: proc(freshness: obs.Scent_Freshness) -> int {
    switch freshness {
    case .Unknown: return 0
    case .Old: return 1
    case .Recent: return 2
    case .Very_Recent: return 3
    }
    return 0
}

// Ground the searcher itself walked over recently: same-class scent there is
// most likely its own trail. Nothing here identifies anybody else.
@(private = "file")
search_visited_recently :: proc(search: ^Search_Runtime, point: Vector, tick: u32) -> bool {
    region := search_region(point, search.profile.region_size)
    for visit in search.visits[:search.visit_count] {
        if search_region(visit.position, search.profile.region_size) == region && tick - visit.visited_tick < search.profile.self_trail_ticks { return true }
    }
    return false
}

// Rebuild strength and bearing from the zones that survived the self-trail discount.
@(private = "file")
scent_summarize_zones :: proc(zones: [obs.SCENT_ZONES]obs.Scent_Strength) -> (strength: obs.Scent_Strength, bearing: Facing, bearing_valid: bool) {
    pull: Vector
    weight: f32
    for band, zone in zones {
        if band == .None { continue }
        if int(band) > int(strength) { strength = band }
        share := scent_strength_weight(band) * (0.7 if obs.scent_zone_is_far(zone) else 1)
        pull += obs.facing_direction(Facing(obs.scent_zone_sector(zone))) * share
        weight += share
    }
    if weight == 0 { return }
    coherence := (pull.x * pull.x + pull.y * pull.y) / (weight * weight)
    if coherence >= 0.35 * 0.35 { bearing, bearing_valid = obs.facing_toward({}, pull) }
    return
}

// One remembered class reading, with own-trail zones explained away.
@(private = "file")
scent_candidate :: proc(search: ^Search_Runtime, entry: Scent_Memory_Entry, own: obs.Scent_Emitter, tick: u32) -> Scent_Evidence {
    candidate := Scent_Evidence{valid = true, class = entry.class, strength = entry.strength, freshness = entry.freshness,
        bearing_valid = entry.bearing_valid, bearing = entry.bearing, observation_id = entry.observation_id, observed_tick = entry.observed_tick}
    if !own.enabled || own.class != entry.class { return candidate }
    zones := entry.zones
    for band, zone in zones {
        if band == .None { continue }
        reach := entry.range * (0.75 if obs.scent_zone_is_far(zone) else 0.25)
        probe := entry.origin + obs.facing_direction(Facing(obs.scent_zone_sector(zone))) * reach
        if search_visited_recently(search, probe, tick) {
            zones[zone] = .None
            candidate.discounted_zones += 1
        }
    }
    if candidate.discounted_zones == 0 { return candidate }
    candidate.strength, candidate.bearing, candidate.bearing_valid = scent_summarize_zones(zones)
    candidate.valid = candidate.strength != .None
    return candidate
}

@(private = "file")
scent_candidate_better :: proc(candidate, best: Scent_Evidence) -> bool {
    if !best.valid { return true }
    if candidate.strength != best.strength { return int(candidate.strength) > int(best.strength) }
    return scent_freshness_rank(candidate.freshness) > scent_freshness_rank(best.freshness)
}

// Turn remembered smells into the one smell worth acting on. The brain owns this
// interpretation; the sensor delivered only anonymous class readings.
search_interpret_scent :: proc(agent: ^Agent, ctx: Decision_Context, trace: ^Trace_Buffer, parent: int) {
    search := &agent.search
    best: Scent_Evidence
    for entry in agent.scent.entries[:agent.scent.count] {
        candidate := scent_candidate(search, entry, ctx.own_emitter, ctx.tick)
        label := "Candidate scent reading" if candidate.discounted_zones == 0 else "Candidate scent reading with own-trail zones discounted"
        chosen := candidate.valid && scent_candidate_better(candidate, best)
        trace_add(trace, parent, .Branch, .Selected if chosen else .Rejected, label, "strength / discounted_zones", f64(candidate.strength), f64(candidate.discounted_zones),
            obs.facing_direction(candidate.bearing) if candidate.bearing_valid else {}, entry.observation_id)
        if chosen { best = candidate }
    }
    search.scent = best
}

// Act on the chosen smell: a bearing starts investigation, mere presence starts a
// local search around the nose. Returns false when there is nothing to follow.
search_follow_scent :: proc(search: ^Search_Runtime, agent: ^Agent, ctx: Decision_Context) -> bool {
    scent := search.scent
    if !scent.valid { return false }
    index := scent_memory_find(&agent.scent, scent.class)
    if index < 0 { return false }
    entry := agent.scent.entries[index]
    if !search.weak_episode_active {
        search.weak_episode_active, search.weak_episode_tick = true, ctx.tick
        search.center = entry.origin
        search.scent_episodes += 1
    }
    current := scent_memory_is_current(&agent.scent, entry, ctx.tick, ctx.senses.olfaction.profile.sample_interval)
    search.evidence = .Scent if current else .Scent_Memory
    search.observation_id, search.evidence_tick = scent.observation_id, scent.observed_tick
    search.confidence = scent_confidence(scent.strength, scent.freshness) * search_memory_strength(ctx.tick, scent.observed_tick, SCENT_RETENTION_TICKS)
    search.center_valid = true
    if scent.bearing_valid {
        // Re-steer only for a real change of direction, not for sample-to-sample wobble.
        if !search.cue_valid || !search.cue_from_scent || abs(obs.facing_step(search.cue_direction, scent.bearing)) >= 2 { search.leg_active = false }
        search.cue_valid, search.cue_tick, search.cue_direction, search.cue_origin = true, scent.observed_tick, scent.bearing, entry.origin
        search.cue_from_scent = true
        search_set_state(search, .Investigate, .Scent_Trail, ctx.tick)
    } else {
        search.cue_valid, search.cue_from_scent = false, false
        search_set_state(search, .Intensive_Search, .Scent_Presence, ctx.tick)
    }
    return true
}
