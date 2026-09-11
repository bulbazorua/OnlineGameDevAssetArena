package ai

import obs "../observations"
import "core:testing"

scent_test_reading :: proc(id: u32, class: obs.Scent_Class, strength: obs.Scent_Strength, bearing: Facing, valid := true, freshness: obs.Scent_Freshness = .Recent) -> obs.Scent_Reading {
    reading := obs.Scent_Reading{observation_id = id, class = class, strength = strength, freshness = freshness, bearing_valid = valid, bearing = bearing}
    reading.zones[obs.scent_zone_index(int(bearing), false)] = strength
    return reading
}

scent_test_input :: proc(sample_id, tick: u32, readings: ..obs.Scent_Reading) -> obs.Sense_Input {
    input := obs.Sense_Input{olfaction_is_new = true, olfaction = {sample_id = sample_id, observer = 3, round_id = 1, sample_tick = tick, delivered_tick = tick,
        position = {100, 100}, profile = {true, 160, 12, true}, status = .Sampled}}
    for reading, index in readings { input.olfaction.readings[index] = reading }
    input.olfaction.reading_count = len(readings)
    return input
}

@(test)
scent_memory_ingests_once_keeps_original_times_and_expires :: proc(t: ^testing.T) {
    memory: Scent_Memory
    input := scent_test_input(5, 100, scent_test_reading(0x80000029, .Human, .Medium, .East), scent_test_reading(0x8000002a, .Orc, .Weak, .North))
    testing.expect(t, scent_memory_ingest(&memory, input, 180) && memory.count == 2 && memory.ingested_samples == 1)
    testing.expect(t, memory.entries[0].class == .Human && memory.entries[0].expires_tick == 280 && memory.entries[0].origin == Vector{100, 100} && memory.entries[0].range == 160)
    testing.expect(t, !scent_memory_ingest(&memory, input, 180), "the same sample is never experienced twice")
    retained := input
    retained.olfaction_is_new = false
    retained.olfaction.sample_id = 6
    testing.expect(t, !scent_memory_ingest(&memory, retained, 180) && memory.ingested_samples == 1, "a non-new sample teaches nothing")
    testing.expect(t, scent_memory_is_current(&memory, memory.entries[0], 124, 12) && !scent_memory_is_current(&memory, memory.entries[0], 125, 12))
    // A newer sample with only orc scent replaces the orc entry; the human entry keeps its old time.
    later := scent_test_input(6, 112, scent_test_reading(0x80000031, .Orc, .Strong, .South))
    testing.expect(t, scent_memory_ingest(&memory, later, 180) && memory.count == 2)
    testing.expect(t, memory.entries[0].observed_tick == 100 && !scent_memory_is_current(&memory, memory.entries[0], 112, 12))
    testing.expect(t, memory.entries[1].observed_tick == 112 && memory.entries[1].strength == .Strong && scent_memory_is_current(&memory, memory.entries[1], 112, 12))
    testing.expect(t, scent_memory_expire(&memory, 279) == 0 && scent_memory_expire(&memory, 280) == 1 && memory.count == 1 && memory.entries[0].class == .Orc)
    testing.expect(t, scent_memory_expire(&memory, 292) == 1 && memory.count == 0 && memory.entries[0] == Scent_Memory_Entry{})
    // A fresh empty sample is remembered as empty; a disabled sample is not a sample.
    empty := scent_test_input(7, 124)
    testing.expect(t, scent_memory_ingest(&memory, empty, 180) && memory.last_sample_empty && memory.last_sample_id == 7)
    disabled := scent_test_input(8, 136)
    disabled.olfaction.status = .Disabled
    testing.expect(t, !scent_memory_ingest(&memory, disabled, 180) && memory.last_sample_id == 7)
    // Wrap-safe expiry near the tick limit.
    wrapped: Scent_Memory
    wrap := scent_test_input(9, 0xffffff00, scent_test_reading(0x80000049, .Human, .Weak, .West))
    testing.expect(t, scent_memory_ingest(&wrapped, wrap, 0x200) && wrapped.entries[0].expires_tick == 0x100)
    testing.expect(t, scent_memory_expire(&wrapped, 0xff) == 0 && scent_memory_expire(&wrapped, 0x100) == 1)
}

@(test)
directional_scent_drives_investigation_then_local_search_and_abandonment :: proc(t: ^testing.T) {
    a := agent_reset(3, 1, .Search, 42)
    config := observe_defaults()
    ctx := search_test_context(100)
    ctx.own_emitter = {true, .Orc, 1}
    ctx.senses.olfaction_is_new = true
    ctx.senses.olfaction = scent_test_input(1, 100, scent_test_reading(0x80000009, .Human, .Medium, .North)).olfaction
    trace: Trace_Buffer
    agent_decide(&a, ctx, config, &trace)
    testing.expect(t, a.search.state == .Investigate && a.search.transition == .Scent_Trail && a.search.evidence == .Scent)
    testing.expect(t, a.search.cue_direction == .North && a.search.observation_id == 0x80000009 && a.search.evidence_tick == 100)
    testing.expect(t, a.search.target == 0 && a.search.acquisition_count == 0 && a.search.center == ctx.position, "smell never becomes a target or a source position")
    testing.expect(t, a.search.confidence > 0 && a.search.confidence < 0.45 && a.search.scent_episodes == 1)
    north := a.search.choices[int(Facing.North)].evidence
    testing.expect(t, a.intent.kind == .Move && north > 0, "the scent bearing pulls the direction scores north")
    for choice in a.search.choices { testing.expect(t, choice.evidence <= north, "no other direction gets a stronger scent pull") }
    referenced := false
    for node in trace.nodes[:trace.count] { if node.reference == 0x80000009 && node.status == .Selected { referenced = true } }
    testing.expect(t, referenced, "the trace names the scent observation that drove the transition")
    // The nose keeps re-sampling the same reading: no re-steer jitter, same episode.
    heading := a.search.heading
    deadline := a.search.leg_deadline
    for tick in u32(101)..<130 {
        ctx = search_test_context(tick)
        ctx.own_emitter = {true, .Orc, 1}
        if tick % 12 == 4 {
            ctx.senses.olfaction_is_new = true
            ctx.senses.olfaction = scent_test_input(1 + (tick - 100) / 12, tick, scent_test_reading(0x80000009 + 8 * ((tick - 100) / 12), .Human, .Medium, .North_East)).olfaction
        }
        agent_decide(&a, ctx, config)
        testing.expect(t, a.search.state == .Investigate && a.search.scent_episodes == 1 && a.search.weak_episode_tick == 100)
        if tick < deadline { testing.expect(t, a.search.heading == heading, "a one-sector wobble must not re-steer mid-leg") }
    }
    // Silence: the retained reading keeps the investigation until it ages out, then
    // the local-search budget takes over with a fade transition.
    // The last wobble sample was at tick 124, so its three-second retention ends at 304.
    testing.expect(t, a.scent.last_sample_tick == 124 && a.scent.ingested_samples == 3)
    expiry := a.scent.last_sample_tick + SCENT_RETENTION_TICKS
    for tick in u32(130)..<310 {
        ctx = search_test_context(tick)
        ctx.own_emitter = {true, .Orc, 1}
        agent_decide(&a, ctx, config)
        if tick == 160 { testing.expect(t, a.search.state == .Investigate && a.search.evidence == .Scent_Memory, "an ageing reading is retained memory, not a current detection") }
        if tick == expiry - 1 { testing.expect(t, a.search.state == .Investigate && a.scent.count == 1) }
        if tick == expiry { testing.expect(t, a.search.state == .Intensive_Search && a.search.transition == .Scent_Faded && a.search.evidence == .Scent_Memory && a.scent.count == 0, "expired scent hands over to the local-search budget") }
    }
    // Presence without a direction: intensive search around the nose, not a march.
    ctx = search_test_context(310)
    ctx.own_emitter = {true, .Orc, 1}
    ctx.senses.olfaction_is_new = true
    ctx.senses.olfaction = scent_test_input(20, 310, scent_test_reading(0x800000a1, .Human, .Weak, .North, valid = false)).olfaction
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.state == .Intensive_Search && a.search.evidence == .Scent && !a.search.cue_valid && a.search.center_valid && a.search.scent_episodes == 1)
    b := agent_reset(9, 1, .Search, 3)
    presence := search_test_context(100, 9)
    presence.own_emitter = {true, .Orc, 1}
    presence.senses.olfaction_is_new = true
    presence.senses.olfaction = scent_test_input(1, 100, scent_test_reading(0x80000009, .Human, .Weak, .North, valid = false)).olfaction
    presence.senses.olfaction.observer = 9
    agent_decide(&b, presence, config)
    testing.expect(t, b.search.state == .Intensive_Search && b.search.transition == .Scent_Presence && b.search.center == presence.position && !b.search.cue_valid)
    // An empty sample clears current detection but keeps the retained memory.
    ctx = search_test_context(322)
    ctx.own_emitter = {true, .Orc, 1}
    ctx.senses.olfaction_is_new = true
    ctx.senses.olfaction = scent_test_input(21, 322).olfaction
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.evidence == .Scent_Memory && a.scent.last_sample_empty && a.scent.count == 1)
    for tick in u32(323)..<700 {
        ctx = search_test_context(tick)
        ctx.own_emitter = {true, .Orc, 1}
        agent_decide(&a, ctx, config)
    }
    testing.expect(t, a.search.state == .Extensive_Search && a.search.transition == .Investigation_Abandoned && a.search.abandoned_count == 1 && a.search.cue_cooldown)
    // During the cooldown the same smell is ignored; after it, a new episode can start.
    ctx = search_test_context(700)
    ctx.own_emitter = {true, .Orc, 1}
    ctx.senses.olfaction_is_new = true
    ctx.senses.olfaction = scent_test_input(30, 700, scent_test_reading(0x800000f1, .Human, .Strong, .West)).olfaction
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.state == .Extensive_Search && a.search.scent.valid && a.search.evidence == .None, "weak leads stay ignored during the cooldown")
    for tick in u32(701)..<1700 {
        ctx = search_test_context(tick)
        ctx.own_emitter = {true, .Orc, 1}
        if tick == 1650 {
            ctx.senses.olfaction_is_new = true
            ctx.senses.olfaction = scent_test_input(31, tick, scent_test_reading(0x800000f9, .Human, .Strong, .West)).olfaction
        }
        agent_decide(&a, ctx, config)
    }
    testing.expect(t, a.search.state == .Investigate && a.search.scent_episodes == 2 && a.search.cue_direction == .West)
}

@(test)
scent_never_acquires_or_moves_a_visual_fix_and_loses_to_current_cues :: proc(t: ^testing.T) {
    a := agent_reset(3, 1, .Search, 42)
    config := observe_defaults()
    // A focused opponent, then it is lost: the last-known position is fixed.
    ctx := search_test_context(100)
    ctx.senses.vision.focused_count = 1
    ctx.senses.vision.focused[0] = {102, 8, .Creature, 5, {200, 100}, .West, .Walk}
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.state == .Pursue && a.search.acquisition_count == 1)
    ctx = search_test_context(112)
    ctx.senses.olfaction_is_new = true
    ctx.senses.olfaction = scent_test_input(1, 112, scent_test_reading(0x80000009, .Orc, .Strong, .North)).olfaction
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.state == .Last_Known_Position && a.search.target_position == Vector{200, 100} && a.search.evidence == .Focused_Memory)
    testing.expect(t, a.search.acquisition_count == 1 && a.scent.count == 1, "a strong smell neither refreshes the fix nor counts as a sighting")
    // A visual cue and a smell together: the cue is followed, the smell waits.
    b := agent_reset(4, 1, .Search, 7)
    ctx = search_test_context(100, 4)
    ctx.senses.vision.cue_count = 1
    ctx.senses.vision.cues[0] = {101, 1, .Far}
    ctx.senses.olfaction_is_new = true
    ctx.senses.olfaction = scent_test_input(1, 100, scent_test_reading(0x80000009, .Orc, .Strong, .West)).olfaction
    ctx.senses.olfaction.observer = 4
    agent_decide(&b, ctx, config)
    testing.expect(t, b.search.state == .Investigate && b.search.evidence == .Cue && b.search.cue_direction == .South_East && b.search.scent.valid)
    for tick in u32(101)..<140 {
        ctx = search_test_context(tick, 4)
        agent_decide(&b, ctx, config)
    }
    testing.expect(t, b.search.evidence == .Scent_Memory && b.search.cue_direction == .West && b.search.cue_from_scent && b.search.state == .Investigate, "the retained smell takes over once the cue is gone")
    testing.expect(t, b.search.acquisition_count == 0 && b.search.target == 0)
}

@(test)
own_trail_is_explained_away_while_other_same_class_scent_still_counts :: proc(t: ^testing.T) {
    a := agent_reset(3, 1, .Search, 42)
    config := observe_defaults()
    // Walk east for a while so the visits behind the creature are its own recent ground.
    for tick in u32(100)..<220 {
        ctx := search_test_context(tick)
        ctx.own_emitter = {true, .Human, 1}
        ctx.position = {100 + f32(tick - 100), 100}
        agent_decide(&a, ctx, config)
    }
    testing.expect(t, a.search.visit_count >= 2)
    // A human reading that points back west, where it just walked: explained away.
    ctx := search_test_context(220)
    ctx.own_emitter = {true, .Human, 1}
    ctx.position = {220, 100}
    ctx.senses.olfaction_is_new = true
    behind := scent_test_reading(0x80000009, .Human, .Strong, .West)
    ctx.senses.olfaction = scent_test_input(1, 220, behind).olfaction
    ctx.senses.olfaction.position = {220, 100}
    trace: Trace_Buffer
    agent_decide(&a, ctx, config, &trace)
    testing.expect(t, !a.search.scent.valid && a.search.evidence != .Scent && a.search.evidence != .Scent_Memory, "own trail behind must not start an investigation")
    discounted := false
    for node in trace.nodes[:trace.count] { if node.reference == 0x80000009 && node.threshold > 0 { discounted = true } }
    testing.expect(t, discounted, "the trace shows the discounted zones")
    // The same class ahead, on ground never visited, is a real lead.
    ctx = search_test_context(232)
    ctx.own_emitter = {true, .Human, 1}
    ctx.position = {220, 100}
    ctx.senses.olfaction_is_new = true
    ahead := scent_test_reading(0x80000011, .Human, .Medium, .North)
    ahead.zones[obs.scent_zone_index(6, false)] = .Strong // own trail west
    ahead.zones[obs.scent_zone_index(0, true)] = .Medium  // somebody north
    ahead.bearing, ahead.bearing_valid = .West, true       // the sensor's blended bearing points at own trail
    ctx.senses.olfaction = scent_test_input(2, 232, ahead).olfaction
    ctx.senses.olfaction.position = {220, 100}
    agent_decide(&a, ctx, config)
    testing.expect(t, a.search.scent.valid && a.search.scent.discounted_zones == 1 && a.search.scent.bearing_valid && a.search.scent.bearing == .North, "discounting own zones leaves the other human's bearing")
    testing.expect(t, a.search.state == .Investigate && a.search.transition == .Scent_Trail && a.search.cue_direction == .North)
    // A scentless creature discounts nothing: every human reading is somebody else.
    c := agent_reset(5, 1, .Search, 9)
    ctx = search_test_context(300, 5)
    ctx.own_emitter = {false, .Human, 1}
    ctx.senses.olfaction_is_new = true
    ctx.senses.olfaction = scent_test_input(1, 300, behind).olfaction
    ctx.senses.olfaction.observer = 5
    agent_decide(&c, ctx, config)
    testing.expect(t, c.search.scent.valid && c.search.scent.discounted_zones == 0 && c.search.state == .Investigate)
}

@(test)
an_old_trail_sampled_again_stays_old_in_memory_and_evidence :: proc(t: ^testing.T) {
    a := agent_reset(3, 1, .Search, 42)
    ctx := search_test_context(100)
    ctx.own_emitter = {true, .Orc, 1}
    for sample_id in u32(1)..=3 {
        ctx.tick = 100 + (sample_id - 1) * 12
        ctx.senses.olfaction_is_new = true
        ctx.senses.olfaction = scent_test_input(sample_id, ctx.tick, scent_test_reading(0x80000001 + 8 * sample_id, .Human, .Medium, .North, freshness = .Old)).olfaction
        trace: Trace_Buffer
        scent_update_memory(&a, ctx, &trace, 0)
        search_interpret_scent(&a, ctx, &trace, 0)
        testing.expect(t, a.scent.count == 1 && a.scent.entries[0].freshness == .Old && a.scent.entries[0].observed_tick == ctx.tick, "re-sampling an old trail keeps the receptor's Old band")
        testing.expect(t, a.search.scent.valid && a.search.scent.freshness == .Old && a.search.scent.observed_tick == ctx.tick)
    }
}
