package main

import "core:math"
import ai "ai"

// Explicit wire values. Animation names stay presentation bindings, not behavior IDs.
Character_Locomotion :: enum u8 { Idle = 0, Walk = 1 }
Character_Facing :: enum u8 { North = 0, North_East = 1, East = 2, South_East = 3, South = 4, South_West = 5, West = 6, North_West = 7 }

// Shared action timing, mirrored by GameProtocol for snapshot interpolation.
// Play the first step in place before translating. This is simulation time,
// independent of render FPS and private source-spritesheet frame names.
CHARACTER_WALK_START_TICKS :: u32(12)

Character_Action_Limits :: struct { speed, roam_radius: f32 }

character_resolve_intent :: proc(character: ^Character, session: ^Session, content: ^Game_Content, intent: ai.Intent,
    anchor: [2]f32, limits: Character_Action_Limits, can_move: bool) -> ai.Action_Result {
    result := ai.Action_Result{kind = .Held}
    if !can_move || session.phase != .In_Arena || session.summon_elapsed_ticks < SUMMON_DURATION_TICKS {
        result.kind = .Locked
    } else if intent.kind == .Move {
        direction := intent.direction
        length_sq := direction.x * direction.x + direction.y * direction.y
        if !(length_sq > 0 && length_sq <= 1.001) || !(limits.speed > 0 && limits.speed <= 180 && limits.roam_radius > 0 && limits.roam_radius <= 4096) {
            result.kind = .Invalid_Request
        } else {
            arena := content_arena(content, session.map_id)
            radius := content_character(content, character.definition_id).footprint_radius
            requested := direction * (limits.speed / SIMULATION_HZ)
            offset := character.position + requested - anchor
            if offset.x * offset.x + offset.y * offset.y > limits.roam_radius * limits.roam_radius {
                result.kind = .Anchor_Limit
            } else {
                next, blocked := movement_apply_delta(character.position, requested, radius, arena, content)
                // Axis sliding can curve the result away from the requested endpoint.
                offset = next - anchor
                if offset.x * offset.x + offset.y * offset.y > limits.roam_radius * limits.roam_radius {
                    result.kind = .Anchor_Limit
                } else {
                    result.displacement = next - character.position
                    if result.displacement.x * result.displacement.x + result.displacement.y * result.displacement.y > 0.000001 {
                        // Face the collision-resolved direction during preparation too.
                        angle := math.atan2(result.displacement.x, -result.displacement.y)
                        character.facing = Character_Facing((int(math.round(angle / (math.PI / 4))) + 8) % 8)
                        if character.locomotion != .Walk {
                            character.locomotion = .Walk
                            character.state_start_tick = session.server_tick
                        }
                        if session.server_tick - character.state_start_tick < CHARACTER_WALK_START_TICKS {
                            return {kind = .Preparing}
                        }
                    }
                    character.position = next
                    result.kind = .Terrain_Blocked if blocked else .Moved
                }
            }
        }
    } else if intent.kind != .Hold {
        result.kind = .Invalid_Request
    }
    moving := result.displacement.x * result.displacement.x + result.displacement.y * result.displacement.y > 0.000001
    locomotion: Character_Locomotion = .Walk if moving else .Idle
    if character.locomotion != locomotion {
        character.locomotion = locomotion
        character.state_start_tick = session.server_tick
    }
    return result
}
