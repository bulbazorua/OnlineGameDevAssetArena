// Data-only brain input contract shared by the pure decision package and the
// host sensing adapter. Nothing here can query a world, a session, a tilemap or
// another creature: the host builds these values and the brain only reads them.
package observations

import "core:math"

Vector :: [2]f32

// Clockwise from north, matching the public locomotion record and the host's
// Character_Facing wire values. Converted explicitly at the package boundary.
Facing :: enum u8 { North = 0, North_East = 1, East = 2, South_East = 3, South = 4, South_West = 5, West = 6, North_West = 7 }
Locomotion :: enum u8 { Idle = 0, Walk = 1 }
Subject_Kind :: enum u8 { Creature, Trainer }
// Disabled, waiting and an empty completed sample are different facts.
Sense_Status :: enum u8 { Unsupported, Disabled, Waiting_For_Summon, Sampled }
// Coarse distance bands: Near is [0, R/2], Far is (R/2, R]. No midpoint is a position.
Range_Band :: enum u8 { Near, Far }

MAX_OBSERVATIONS :: 3

Pose :: struct { position: Vector, facing: Facing }

// Receptor tuning as delivered to the observer. Range is already in world units.
Vision_Profile :: struct {
    enabled: bool,
    range: f32,
    focused_fov_degrees, overall_fov_degrees: f32,
    sample_interval: u32,
}

// v1 approximation: the handle is the subject's public runtime entity ID, which
// every client already receives in world packets. It supports re-identification
// of a previously focused subject within a round and offers no lookup API.
Subject_Handle :: distinct u32

Focused_Sighting :: struct {
    observation_id: u32,
    subject: Subject_Handle,
    kind: Subject_Kind,
    appearance_id: u16, // Public definition ID: what the subject visibly is.
    position: Vector,   // Observed ground position at the sample tick.
    facing: Facing,
    locomotion: Locomotion,
}

// A peripheral cue carries no coordinates, identity, kind, facing or action.
Peripheral_Cue :: struct {
    observation_id: u32,
    sector: u8, // 45° sector clockwise from the sampled observer facing, 0..7.
    band: Range_Band,
}

Vision_Sample :: struct {
    sample_id: u32,
    observer, round_id: u32,
    sample_tick, delivered_tick: u32,
    pose: Pose,
    profile: Vision_Profile,
    status: Sense_Status,
    focused: [MAX_OBSERVATIONS]Focused_Sighting,
    focused_count: int,
    cues: [MAX_OBSERVATIONS]Peripheral_Cue,
    cue_count: int,
}

// Anonymous scent categories. A class says what kind of thing left a trace,
// never which individual, owner or opponent.
Scent_Class :: enum u8 { Human, Orc }
SCENT_CLASS_COUNT :: len(Scent_Class)
Scent_Strength :: enum u8 { None, Weak, Medium, Strong }
// Unknown means the receptor cannot estimate age from permitted evidence.
Scent_Freshness :: enum u8 { Unknown, Old, Recent, Very_Recent }
// Eight compass sectors (0 = north, clockwise) times a near and a far band.
SCENT_SECTORS :: 8
SCENT_ZONES :: SCENT_SECTORS * 2
MAX_SCENT_READINGS :: SCENT_CLASS_COUNT

// Receptor tuning as delivered to the observer. Range is already in world units.
Olfaction_Profile :: struct {
    enabled: bool,
    range: f32,
    sample_interval: u32,
    estimates_freshness: bool,
}

// What a body gives off. A creature may know this about itself; it is never a
// hidden fact about somebody else.
Scent_Emitter :: struct {
    enabled: bool,
    class: Scent_Class,
    intensity: f32,
}

// One anonymous class reading: coarse strength, uncertain freshness, a bearing
// only when the sampled zones agree, and the sampled zones themselves. No
// coordinates, count of sources or identity can be recovered from it.
Scent_Reading :: struct {
    observation_id: u32,
    class: Scent_Class,
    strength: Scent_Strength,
    freshness: Scent_Freshness,
    bearing_valid: bool,
    bearing: Facing,
    zones: [SCENT_ZONES]Scent_Strength,
}

// What the nose measured in one zone. Unsampled ground is unknown, never "no
// scent"; Partial means part of the zone was solid or off the map and stayed unknown.
Scent_Coverage :: enum u8 { Unsampled, Partial, Sampled }

Scent_Sample :: struct {
    sample_id: u32,
    observer, round_id: u32,
    sample_tick, delivered_tick: u32,
    position: Vector, // Where the nose sampled: the observer's own ground point.
    profile: Olfaction_Profile,
    status: Sense_Status,
    coverage: [SCENT_ZONES]Scent_Coverage, // The nose's own sampling footprint, zone by zone.
    readings: [MAX_SCENT_READINGS]Scent_Reading,
    reading_count: int,
}

// Everything a brain may perceive this tick. Each `*_is_new` flag is independent
// of status: re-reading a retained sample is not a new experience.
Sense_Input :: struct {
    vision: Vision_Sample,
    vision_is_new: bool,
    olfaction: Scent_Sample,
    olfaction_is_new: bool,
}

scent_zone_index :: proc(sector: int, far: bool) -> int { return sector * 2 + (1 if far else 0) }
scent_zone_sector :: proc(zone: int) -> int { return zone / 2 }
scent_zone_is_far :: proc(zone: int) -> bool { return zone % 2 == 1 }

// Unit forward vectors, clockwise from north in the Y-down world.
DIRECTIONS :: [8]Vector{{0, -1}, {0.70710678, -0.70710678}, {1, 0}, {0.70710678, 0.70710678},
    {0, 1}, {-0.70710678, 0.70710678}, {-1, 0}, {-0.70710678, -0.70710678}}

facing_direction :: proc(facing: Facing) -> Vector {
    directions := DIRECTIONS
    return directions[int(facing) & 7]
}

vector_finite :: proc(v: Vector) -> bool {
    return !math.is_nan(v.x) && !math.is_nan(v.y) && !math.is_inf(v.x) && !math.is_inf(v.y)
}

// Nearest eight-way facing from one ground point toward another. Coincident or
// invalid points have no bearing; the caller must not normalize zero.
facing_toward :: proc(from, to: Vector) -> (facing: Facing, ok: bool) {
    if !vector_finite(from) || !vector_finite(to) { return .North, false }
    d := to - from
    if d.x * d.x + d.y * d.y <= 1e-12 { return .North, false }
    angle := math.atan2(d.x, -d.y)
    return Facing((int(math.round(angle / (math.PI / 4))) + 8) % 8), true
}

// Signed number of 45° steps from one facing to another: positive is clockwise,
// range -3..4. The 180° case always resolves clockwise (+4), a fixed tie rule.
facing_step :: proc(from, to: Facing) -> int {
    delta := (int(to) - int(from) + 8) % 8
    if delta > 4 { delta -= 8 }
    return delta
}

facing_rotate :: proc(facing: Facing, steps: int) -> Facing {
    return Facing(((int(facing) + steps) % 8 + 8) % 8)
}

// Absolute bearing of a cue that was quantized relative to a sampled facing.
cue_absolute_facing :: proc(reference: Facing, sector: u8) -> Facing {
    return facing_rotate(reference, int(sector & 7))
}
