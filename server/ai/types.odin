// Pure decision contracts. This package cannot query the world or execute effects.
// It imports only the data-only observations contract; every field a brain can
// read arrives by value from the host, already limited to permitted evidence.
package ai

import obs "../observations"

Vector :: obs.Vector
Facing :: obs.Facing
Controller :: enum { Observe, Search }
Intent_Kind :: enum { Hold, Move, Face }
Intent :: struct { kind: Intent_Kind, direction: Vector, facing: Facing }
Result_Kind :: enum { Held, Moved, Terrain_Blocked, Anchor_Limit, Locked, Invalid_Request, Preparing, Turned, Turn_Pending }
Action_Result :: struct { kind: Result_Kind, displacement: Vector, facing: Facing }
Decision_Reason :: enum { Locked, Scan, Orient, Observe, Reacquire, Search_Extensive, Search_Intensive, Investigate, Last_Known_Position, Pursue }
Attention_State :: enum { Scan, Orient, Observe, Reacquire }
Evidence_Kind :: enum u8 { None, Focused, Cue, Focused_Memory, Cue_Memory, Scent, Scent_Memory }

// Private attention context: what the creature is attending to and why. It holds
// evidence references, never a live subject pointer.
Attention :: struct {
    state: Attention_State,
    evidence: Evidence_Kind,
    subject: obs.Subject_Handle,
    observation_id, evidence_tick: u32,
    desired_facing: Facing,
    scan_deadline: u32,
    scan_armed: bool,
}

// Self-condition plus permitted evidence. No opponent record, map, candidate list
// or host diagnostic is reachable from here.
Decision_Context :: struct {
    entity_id, round_id, tick: u32,
    position: Vector,
    facing: Facing,
    can_act: bool,    // Summon/action lock state as legal feedback.
    turn_ready: bool, // The resolver's turn interval has elapsed.
    senses: obs.Sense_Input,
    own_emitter: obs.Scent_Emitter, // What this body itself smells like: own knowledge.
}
Decision_Record :: struct {
    tick: u32,
    reason: Decision_Reason,
    requested: Intent,
    result: Action_Result,
}
Agent :: struct {
    entity_id, round_id: u32,
    controller: Controller,
    memory: Visual_Memory,
    scent: Scent_Memory,
    search: Search_Runtime,
    attention: Attention,
    intent: Intent,
    last: Decision_Record,
}

tick_due :: proc(now, deadline: u32) -> bool { return now - deadline < 0x80000000 }
