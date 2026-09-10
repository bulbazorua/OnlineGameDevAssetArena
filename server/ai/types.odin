// Pure decision contracts. This package cannot query the world or execute effects.
package ai

Vector :: [2]f32
Controller :: enum { Idle_Wander }
Intent_Kind :: enum { Hold, Move }
Intent :: struct { kind: Intent_Kind, direction: Vector }
Result_Kind :: enum { Held, Moved, Terrain_Blocked, Anchor_Limit, Locked, Invalid_Request, Preparing }
Action_Result :: struct { kind: Result_Kind, displacement: Vector }
Decision_Reason :: enum { Waiting, Walking, Choosing_Direction, Walk_Completed, No_Direction, Action_Blocked, Locked }
Decision_Context :: struct {
    entity_id, round_id, tick: u32,
    position, anchor: Vector,
    can_move: bool,
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
    random: Random_State,
    wander: Wander_Runtime,
    intent: Intent,
    last: Decision_Record,
}

tick_due :: proc(now, deadline: u32) -> bool { return now - deadline < 0x80000000 }
