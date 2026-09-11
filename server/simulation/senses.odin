package simulation

import "../content"
import ai "../ai"
import obs "../observations"
import "../perception"

// Every receptor keeps its own clock: when it next samples and how many
// samples it has taken. A non-due receptor retains its last sample unchanged.
Receptor_Schedule :: struct {
    armed: bool,
    next_sample_tick: u32,
    sample_counter: u32,
}

Vision_Receptor :: struct {
    profile: obs.Vision_Profile,
    schedule: Receptor_Schedule,
    last: obs.Vision_Sample,
    audit: perception.Vision_Audit, // Host-only; never reaches a worker.
}

Olfaction_Receptor :: struct {
    profile: obs.Olfaction_Profile,
    schedule: Receptor_Schedule,
    last: obs.Scent_Sample,
    audit: perception.Olfaction_Audit, // Host-only; never reaches a worker.
}

// Host-owned receptor state for one creature. Only the samples reach the worker.
Receptor :: struct {
    vision: Vision_Receptor,
    olfaction: Olfaction_Receptor,
}

@(private)
receptor_bind :: proc(receptor: ^Receptor, definition: ^content.Character_Definition) {
    receptor^ = {}
    if definition == nil { return }
    receptor.vision.profile = definition.vision
    receptor.olfaction.profile = definition.olfaction
}

// The same gate for every sense: is it usable, is the creature summoned, and
// is a new sample due, or should the last one be handed over again?
Receptor_Gate :: enum { Disabled, Waiting, Retained, Due }

@(private = "file")
receptor_gate :: proc(schedule: ^Receptor_Schedule, usable, can_act: bool, tick: u32) -> Receptor_Gate {
    if !usable { schedule.armed = false; return .Disabled }
    if !can_act { schedule.armed = false; return .Waiting }
    if !schedule.armed || ai.tick_due(tick, schedule.next_sample_tick) { return .Due }
    return .Retained
}

@(private = "file")
schedule_next :: proc(schedule: ^Receptor_Schedule, tick, interval: u32) -> (sample_id: u32) {
    schedule.sample_counter += 1
    schedule.armed = true
    schedule.next_sample_tick = tick + interval
    return schedule.sample_counter
}

@(private = "file")
vision_status_sample :: proc(receptor: ^Vision_Receptor, self: Character, round, tick: u32, status: obs.Sense_Status) -> obs.Vision_Sample {
    return {observer = self.entity_id, round_id = round, sample_tick = tick, delivered_tick = tick,
        pose = {self.position, character_facing_to_observation(self.facing)}, profile = receptor.profile, status = status}
}

@(private = "file")
scent_status_sample :: proc(receptor: ^Olfaction_Receptor, self: Character, round, tick: u32, status: obs.Sense_Status) -> obs.Scent_Sample {
    return {observer = self.entity_id, round_id = round, sample_tick = tick, delivered_tick = tick,
        position = self.position, profile = receptor.profile, status = status}
}

// One frozen copy of everything an eye may look at this tick.
Vision_World :: struct {
    characters: [MAX_PLAYERS]Character,
    trainers: [MAX_PLAYERS]Trainer,
    grid: perception.Opacity_Grid,
}

@(private = "file")
vision_receptor_sample :: proc(receptor: ^Vision_Receptor, world: ^Vision_World, index: int, round, tick: u32, can_act: bool) -> (sample: obs.Vision_Sample, is_new: bool) {
    self := world.characters[index]
    usable := receptor.profile.enabled && perception.vision_profile_valid(receptor.profile)
    switch receptor_gate(&receptor.schedule, usable, can_act, tick) {
    case .Disabled: receptor.last = vision_status_sample(receptor, self, round, tick, .Disabled)
    case .Waiting: receptor.last = vision_status_sample(receptor, self, round, tick, .Waiting_For_Summon)
    case .Retained:
    case .Due:
        sample_id := schedule_next(&receptor.schedule, tick, receptor.profile.sample_interval)
        query := perception.Vision_Query{observer = {entity_id = self.entity_id, round_id = round,
            pose = {self.position, character_facing_to_observation(self.facing)}}, profile = receptor.profile, grid = world.grid}
        other := world.characters[1 - index]
        query.candidates[0] = {entity_id = other.entity_id, kind = .Creature, appearance_id = other.definition_id, position = other.position,
            facing = character_facing_to_observation(other.facing), locomotion = obs.Locomotion(u8(other.locomotion))}
        for trainer, slot in world.trainers {
            query.candidates[1 + slot] = {entity_id = trainer.entity_id, kind = .Trainer, appearance_id = trainer.definition_id, position = trainer.position,
                facing = character_facing_to_observation(trainer.facing), locomotion = .Idle if trainer.locomotion == .Idle else .Walk}
        }
        query.candidate_count = 1 + MAX_PLAYERS
        receptor.last, receptor.audit = perception.vision_sample(query, sample_id, tick, tick)
        is_new = true
    }
    return receptor.last, is_new
}

@(private = "file")
olfaction_receptor_sample :: proc(receptor: ^Olfaction_Receptor, field: ^perception.Scent_Field, self: Character, round, tick: u32, can_act: bool) -> (sample: obs.Scent_Sample, is_new: bool) {
    usable := receptor.profile.enabled && perception.olfaction_profile_valid(receptor.profile) && perception.scent_field_valid(field)
    switch receptor_gate(&receptor.schedule, usable, can_act, tick) {
    case .Disabled: receptor.last = scent_status_sample(receptor, self, round, tick, .Disabled)
    case .Waiting: receptor.last = scent_status_sample(receptor, self, round, tick, .Waiting_For_Summon)
    case .Retained:
    case .Due:
        sample_id := schedule_next(&receptor.schedule, tick, receptor.profile.sample_interval)
        query := perception.Olfaction_Query{observer = {entity_id = self.entity_id, round_id = round,
            pose = {self.position, character_facing_to_observation(self.facing)}}, profile = receptor.profile, field = field}
        receptor.last, receptor.audit = perception.olfaction_sample(query, sample_id, tick, tick)
        is_new = true
    }
    return receptor.last, is_new
}

// Sample every due receptor from one frozen world phase, after the session and
// scent updates and before either creature acts. Only the receptors change here;
// a non-due receptor hands over its last sample unchanged.
@(private)
senses_prepare :: proc(receptors: ^[MAX_PLAYERS]Receptor, field: ^perception.Scent_Field, session: ^Session, catalog: ^content.Game_Content, can_act: bool) -> (inputs: [MAX_PLAYERS]obs.Sense_Input) {
    world := Vision_World{characters = session.characters, trainers = session.trainers}
    if arena := content.find_arena(catalog, session.map_id); arena != nil { world.grid = content.arena_opacity_grid(arena) }
    for index in 0..<MAX_PLAYERS {
        receptor := &receptors[index]
        input := &inputs[index]
        input.vision, input.vision_is_new = vision_receptor_sample(&receptor.vision, &world, index, session.round_id, session.server_tick, can_act)
        input.olfaction, input.olfaction_is_new = olfaction_receptor_sample(&receptor.olfaction, field, world.characters[index], session.round_id, session.server_tick, can_act)
    }
    return
}
