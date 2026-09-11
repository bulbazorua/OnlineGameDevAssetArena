package main

import "core:testing"
import "core:encoding/json"
import obs "observations"

@(test)
live_senses_drop_old_lifecycles_without_waiting_for_new_decisions :: proc(t: ^testing.T) {
    debug := new(AI_Debug)
    defer free(debug)
    debug.sense_world = {active = true, round_id = 4, map_id = 2, entities = {30, 31}}
    for owner in 0..<MAX_PLAYERS {
        r := &debug.history[owner][0]
        r.owner_id, r.map_id, r.definition_id = owner + 1, 2, 1
        r.input.round_id, r.input.entity_id = 4, u32(30 + owner)
        r.input.senses.vision.status = .Sampled
        r.input.senses.olfaction.status = .Sampled
        debug.totals[owner] = 1
        debug.delivery[owner].vision.delivered_us = 123
        debug.delivery[owner].olfaction.delivered_us = 456
    }
    records: [MAX_PLAYERS]Sense_Debug_Record
    testing.expect(t, sense_debug_collect(debug, &records) == 2)
    testing.expect(t, records[0].delivered_us == 123 && records[0].scent_delivered_us == 456)
    debug.sense_world.entities[0] = 99
    testing.expect(t, sense_debug_collect(debug, &records) == 1 && records[0].owner_id == 2)
    debug.sense_world.round_id += 1
    testing.expect(t, sense_debug_collect(debug, &records) == 0)
    debug.sense_world.round_id -= 1
    debug.sense_world.active = false
    testing.expect(t, sense_debug_collect(debug, &records) == 0)
}

@(test)
live_senses_clock_keeps_original_delivery_and_never_invents_a_missing_time :: proc(t: ^testing.T) {
    debug := new(AI_Debug)
    defer free(debug)
    record: AI_Debug_Record
    record.owner_id, record.queued_us = 1, 1000
    record.input.senses.vision = {status = .Sampled, sample_id = 1, observer = 7, round_id = 2}
    record.input.senses.vision_is_new = true
    record.input.senses.olfaction = {status = .Sampled, sample_id = 1, observer = 7, round_id = 2}
    record.input.senses.olfaction_is_new = true
    ai_debug_note_delivery(debug, &record)
    testing.expect(t, debug.delivery[0].vision.delivered_us == 1000 && debug.delivery[0].olfaction.delivered_us == 1000)
    record.queued_us = 2000
    record.input.senses.vision_is_new = false
    record.input.senses.olfaction_is_new = false
    ai_debug_note_delivery(debug, &record)
    testing.expect(t, debug.delivery[0].vision.delivered_us == 1000 && debug.delivery[0].olfaction.delivered_us == 1000)
    // A new nose sample gets its own clock without touching the eye's clock.
    record.input.senses.olfaction.sample_id, record.input.senses.olfaction_is_new = 2, true
    ai_debug_note_delivery(debug, &record)
    testing.expect(t, debug.delivery[0].vision.delivered_us == 1000 && debug.delivery[0].olfaction.delivered_us == 2000)
    record.input.senses.vision.sample_id += 1
    ai_debug_note_delivery(debug, &record)
    testing.expect(t, debug.delivery[0].vision.delivered_us == -1 && debug.delivery[0].olfaction.delivered_us == 2000)
}

@(test)
live_senses_envelope_fits_bounded_reader_at_maximum_evidence :: proc(t: ^testing.T) {
    widest: AI_Debug_Record
    widest.owner_id, widest.definition_id, widest.map_id = 2, 65535, 65535
    widest.input.entity_id, widest.input.round_id, widest.input.tick = 0xffffffff, 0xffffffff, 0xffffffff
    sample := &widest.input.senses.vision
    sample.sample_id, sample.observer, sample.round_id, sample.sample_tick, sample.delivered_tick = 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff
    sample.pose, sample.profile, sample.status = {{-1234.5677, -1234.5677}, .North_West}, {true, 2048, 179, 180, 0xffffffff}, .Sampled
    sample.focused_count, sample.cue_count = 3, 3
    for &sighting in sample.focused { sighting = {0xffffffff, 0xffffffff, .Creature, 65535, {-1234.5677, -1234.5677}, .North_West, .Walk} }
    for &cue in sample.cues { cue = {0xffffffff, 7, .Near} }
    widest.fan_count = len(widest.fan)
    for &point in widest.fan { point = {-1234.5677, -1234.5677} }
    nose := &widest.input.senses.olfaction
    nose^ = {sample_id = 0xffffffff, observer = 0xffffffff, round_id = 0xffffffff, sample_tick = 0xffffffff, delivered_tick = 0xffffffff,
        position = {-1234.5677, -1234.5677}, profile = {true, 1024, 0xffffffff, true}, status = .Sampled, reading_count = len(nose.readings)}
    for &reading, index in nose.readings {
        reading = {observation_id = 0xffffffff, class = obs.Scent_Class(index), strength = .Medium, freshness = .Very_Recent, bearing_valid = true, bearing = .North_West}
        for &zone in reading.zones { zone = .Medium }
    }
    widest.input.own_emitter = {true, .Human, 4}
    records := [MAX_PLAYERS]Sense_Debug_Record{sense_debug_record(&widest, 1000, 1000), sense_debug_record(&widest, 1000, 1000)}
    records[0].owner_id = 1
    snapshot := Sense_Debug_Snapshot{schema_version = SENSE_DEBUG_SCHEMA, run_id = "run/generation-100/attempt-100",
        fingerprint = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", published_us = 2000,
        origin_unix_us = 1800000000000000, records = records[:]}
    data, error := json.marshal(snapshot, {use_enum_names = true})
    defer delete(data)
    testing.expect(t, error == nil && len(data) <= SENSE_DEBUG_BYTES)
}
