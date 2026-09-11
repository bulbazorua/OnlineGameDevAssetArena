package simulation

import "core:math"
import ai "../ai"
import obs "../observations"
import "../content"

// Shared action timing, mirrored by GameProtocol for snapshot interpolation.
// Play the first step in place before translating. This is simulation time,
// independent of render FPS and private source-spritesheet frame names.
CHARACTER_WALK_START_TICKS :: u32(12)

// Motor limit for turning in place: one 45° step per interval. The first legal
// turn is immediate; later steps wait. A simulation rule, never worker CPU time.
CHARACTER_TURN_INTERVAL_TICKS :: u32(6)

Character_Action_Limits :: struct { speed, roam_radius: f32 }

// Private per-creature resolver state. It lives beside the agent in the battle
// runtime: not in the worker's copied agent and not in the public session.
Character_Action_Runtime :: struct {
    turn_started: bool,
    next_turn_tick: u32,
}

@(private)
character_turn_ready :: proc(runtime: ^Character_Action_Runtime, tick: u32) -> bool {
    return runtime == nil || !runtime.turn_started || ai.tick_due(tick, runtime.next_turn_tick)
}

// The single owner of voluntary character actions. Sensing, strategies, UI and
// diagnostics request; only this resolver changes position, facing or locomotion.
@(private)
character_resolve_intent :: proc(character: ^Character, session: ^Session, catalog: ^content.Game_Content, intent: ai.Intent,
    anchor: [2]f32, limits: Character_Action_Limits, can_act: bool, runtime: ^Character_Action_Runtime = nil) -> ai.Action_Result {
    result := ai.Action_Result{kind = .Held}
    if !can_act || session.phase != .In_Arena || session.summon_elapsed_ticks < SUMMON_DURATION_TICKS {
        result.kind = .Locked
    } else if intent.kind == .Move {
        direction := intent.direction
        length_sq := direction.x * direction.x + direction.y * direction.y
        if !(length_sq > 0 && length_sq <= 1.001) || !(limits.speed > 0 && limits.speed <= 180 && limits.roam_radius >= 0 && limits.roam_radius <= 4096) {
            result.kind = .Invalid_Request
        } else {
            arena := content.find_arena(catalog, session.map_id)
            radius := content.find_character(catalog, character.definition_id).footprint_radius
            requested := direction * (limits.speed / SIMULATION_HZ)
            offset := character.position + requested - anchor
            if limits.roam_radius > 0 && offset.x * offset.x + offset.y * offset.y > limits.roam_radius * limits.roam_radius {
                result.kind = .Anchor_Limit
            } else {
                next, blocked := movement_apply_delta(character.position, requested, radius, arena, catalog)
                // Axis sliding can curve the result away from the requested endpoint.
                offset = next - anchor
                if limits.roam_radius > 0 && offset.x * offset.x + offset.y * offset.y > limits.roam_radius * limits.roam_radius {
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
                            return {kind = .Preparing, facing = character_facing_to_observation(character.facing)}
                        }
                    }
                    character.position = next
                    result.kind = .Terrain_Blocked if blocked else .Moved
                }
            }
        }
    } else if intent.kind == .Face {
        // Turn in place: bounded to one 45° step per interval, no translation, no
        // walk preparation. The 180° case turns clockwise by the shared tie rule.
        if int(intent.facing) < 0 || int(intent.facing) > 7 {
            result.kind = .Invalid_Request
        } else if !character_turn_ready(runtime, session.server_tick) {
            result.kind = .Turn_Pending
        } else if u8(intent.facing) == u8(character.facing) {
            result.kind = .Held
        } else {
            current := character_facing_to_observation(character.facing)
            step := obs.facing_step(current, intent.facing)
            character.facing = Character_Facing(u8(obs.facing_rotate(current, 1 if step > 0 else -1)))
            if runtime != nil {
                runtime.turn_started = true
                runtime.next_turn_tick = session.server_tick + CHARACTER_TURN_INTERVAL_TICKS
            }
            result.kind = .Turned
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
    result.facing = character_facing_to_observation(character.facing)
    return result
}
