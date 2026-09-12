package perception

import obs "../observations"
import "core:math"

MAX_CANDIDATES :: 3
// Display fan: 63 evenly spaced rays across the overall field plus both focused
// edges. Per-subject exact segments decide detection; this is presentation only.
FAN_RAYS :: 65

// Small tolerance so subjects exactly on a boundary count as inside. Range uses
// world units; angular comparisons use cosine units.
BOUNDARY_TOLERANCE :: f32(1e-4)
// Gameplay ruler: one gameplay unit is 32 world units.
WORLD_UNITS_PER_GAMEPLAY_UNIT :: f32(32)
// Longest vision range both content readers accept, in gameplay units.
MAX_RANGE_GAMEPLAY_UNITS :: 64

Candidate :: struct {
    entity_id: u32,
    kind: obs.Subject_Kind,
    appearance_id: u16,
    position: obs.Vector,
    facing: obs.Facing,
    locomotion: obs.Locomotion,
}

Observer :: struct {
    entity_id, round_id: u32,
    pose: obs.Pose,
}

// Everything the host may know for one observer's sample. Values only.
Vision_Query :: struct {
    observer: Observer,
    profile: obs.Vision_Profile,
    grid: Opacity_Grid,
    terrain: []u8,
    terrain_revision: u32,
    candidates: [MAX_CANDIDATES]Candidate,
    candidate_count: int,
}

Candidate_Verdict :: enum u8 { Not_Evaluated, Self, Invalid, Out_Of_Range, Outside_Field, Occluded, Focused, Peripheral }

Candidate_Audit :: struct {
    entity_id: u32,
    verdict: Candidate_Verdict,
    distance, alignment: f32,
    position: obs.Vector,
}

// Host-only developer evidence. It records why hidden candidates failed and is
// never placed inside Decision_Context, Sense_Input or an agent.
Vision_Audit :: struct {
    sample_id: u32,
    origin_opaque: bool,
    candidates: [MAX_CANDIDATES]Candidate_Audit,
    candidate_count: int,
    sight_tests, merged_cues: int,
}

vision_profile_valid :: proc(p: obs.Vision_Profile) -> bool {
    finite :: proc(v: f32) -> bool { return !math.is_nan(v) && !math.is_inf(v) }
    if !finite(p.range) || !finite(p.focused_fov_degrees) || !finite(p.overall_fov_degrees) { return false }
    return p.range > 0 && p.range <= MAX_RANGE_GAMEPLAY_UNITS * WORLD_UNITS_PER_GAMEPLAY_UNIT &&
        p.focused_fov_degrees >= 45 && p.focused_fov_degrees < p.overall_fov_degrees && p.overall_fov_degrees <= 180 &&
        p.sample_interval >= 1 && p.sample_interval <= 60
}

@(private)
vision_add_cue :: proc(sample: ^obs.Vision_Sample, audit: ^Vision_Audit, sector: u8, band: obs.Range_Band) {
    for existing in sample.cues[:sample.cue_count] {
        if existing.sector == sector && existing.band == band { audit.merged_cues += 1; return }
    }
    if sample.cue_count == len(sample.cues) { audit.merged_cues += 1; return }
    sample.cues[sample.cue_count] = {sector = sector, band = band}
    sample.cue_count += 1
}

// Classify every candidate against range, field and terrain occlusion. Focused
// sightings keep observed detail; peripheral detections become anonymous cues
// quantized to a 45° sector and a two-band range before delivery.
vision_sample :: proc(query: Vision_Query, sample_id, sample_tick, delivered_tick: u32, terrain_cache: ^Terrain_Cache = nil) -> (sample: obs.Vision_Sample, audit: Vision_Audit) {
    sample.sample_id, audit.sample_id = sample_id, sample_id
    sample.observer, sample.round_id = query.observer.entity_id, query.observer.round_id
    sample.sample_tick, sample.delivered_tick = sample_tick, delivered_tick
    sample.pose, sample.profile = query.observer.pose, query.profile
    if !query.profile.enabled || !vision_profile_valid(query.profile) { sample.status = .Disabled; return }
    sample.status = .Sampled
    eye := query.observer.pose.position
    forward := obs.facing_direction(query.observer.pose.facing)
    cos_focus := f32(math.cos(f64(query.profile.focused_fov_degrees) * 0.5 * math.PI / 180))
    cos_field := f32(math.cos(f64(query.profile.overall_fov_degrees) * 0.5 * math.PI / 180))
    limit := query.profile.range + BOUNDARY_TOLERANCE
    audit.origin_opaque = !grid_contains_point(query.grid, eye) || grid_cell_opaque(query.grid, grid_cell_of(query.grid, eye))
    sample.terrain = vision_terrain_cached(query, terrain_cache)
    count := clamp(query.candidate_count, 0, MAX_CANDIDATES)
    audit.candidate_count = count
    candidates := query.candidates
    for candidate, index in candidates[:count] {
        entry := &audit.candidates[index]
        entry.entity_id, entry.position = candidate.entity_id, candidate.position
        if candidate.entity_id == query.observer.entity_id { entry.verdict = .Self; continue }
        if !obs.vector_finite(candidate.position) || !obs.vector_finite(eye) { entry.verdict = .Invalid; continue }
        d := candidate.position - eye
        distance_sq := d.x * d.x + d.y * d.y
        entry.distance = math.sqrt(distance_sq)
        if distance_sq > limit * limit { entry.verdict = .Out_Of_Range; continue }
        if audit.origin_opaque { entry.verdict = .Occluded; continue }
        alignment := f32(1)
        if distance_sq > 1e-8 {
            alignment = (d.x * forward.x + d.y * forward.y) / entry.distance
            entry.alignment = alignment
            if alignment < cos_field - BOUNDARY_TOLERANCE { entry.verdict = .Outside_Field; continue }
            audit.sight_tests += 1
            if !line_of_sight(query.grid, eye, candidate.position) { entry.verdict = .Occluded; continue }
        } else {
            entry.alignment = 1
        }
        if alignment >= cos_focus - BOUNDARY_TOLERANCE {
            entry.verdict = .Focused
            if sample.focused_count < len(sample.focused) {
                sample.focused[sample.focused_count] = {subject = obs.Subject_Handle(candidate.entity_id), kind = candidate.kind,
                    appearance_id = candidate.appearance_id, position = candidate.position, facing = candidate.facing, locomotion = candidate.locomotion}
                sample.focused_count += 1
            }
            continue
        }
        entry.verdict = .Peripheral
        // Signed angle from forward to the subject; positive is clockwise on screen.
        cross := forward.x * d.y - forward.y * d.x
        angle := math.atan2(f64(cross), f64(d.x * forward.x + d.y * forward.y))
        sector := u8((int(math.round(angle / (math.PI / 4))) + 8) % 8)
        band: obs.Range_Band = .Near if entry.distance <= query.profile.range * 0.5 + BOUNDARY_TOLERANCE else .Far
        vision_add_cue(&sample, &audit, sector, band)
    }
    // Deliver cues ordered by their quantized fields only; number after filtering.
    for i in 1..<sample.cue_count {
        for j := i; j > 0; j -= 1 {
            a, b := sample.cues[j - 1], sample.cues[j]
            if int(a.band) < int(b.band) || (a.band == b.band && a.sector <= b.sector) { break }
            sample.cues[j - 1], sample.cues[j] = b, a
        }
    }
    for &sighting, index in sample.focused[:sample.focused_count] { sighting.observation_id = sample_id * 8 + u32(index) + 1 }
    for &cue, index in sample.cues[:sample.cue_count] { cue.observation_id = sample_id * 8 + u32(sample.focused_count + index) + 1 }
    return
}

// Clipped display fan for developer views. Ray endpoints lie on the nominal range
// or on the first opaque cell they touch. Generated off the simulation thread.
vision_fan :: proc(grid: Opacity_Grid, pose: obs.Pose, profile: obs.Vision_Profile, out: ^[FAN_RAYS]obs.Vector) -> int {
    if !vision_profile_valid(profile) || !grid_contains_point(grid, pose.position) { return 0 }
    half := f64(profile.overall_fov_degrees) * 0.5 * math.PI / 180
    focus := f64(profile.focused_fov_degrees) * 0.5 * math.PI / 180
    angles: [FAN_RAYS]f64
    for i in 0..<FAN_RAYS - 2 { angles[i] = -half + 2 * half * f64(i) / f64(FAN_RAYS - 3) }
    angles[FAN_RAYS - 2], angles[FAN_RAYS - 1] = -focus, focus
    for i in 1..<FAN_RAYS {
        for j := i; j > 0 && angles[j - 1] > angles[j]; j -= 1 { angles[j - 1], angles[j] = angles[j], angles[j - 1] }
    }
    forward := obs.facing_direction(pose.facing)
    base := math.atan2(f64(forward.x), f64(-forward.y))
    extent := [2]f32{f32(grid.width) * grid.tile_size, f32(grid.height) * grid.tile_size}
    for angle, i in angles {
        direction := obs.Vector{f32(math.sin(base + angle)), f32(-math.cos(base + angle))}
        end := pose.position + direction * profile.range
        // Clip to the map first; outside is opaque, so the boundary is the end.
        scale := f32(1)
        if end.x < 0 { scale = min(scale, pose.position.x / (pose.position.x - end.x)) }
        if end.y < 0 { scale = min(scale, pose.position.y / (pose.position.y - end.y)) }
        if end.x > extent.x { scale = min(scale, (extent.x - pose.position.x) / (end.x - pose.position.x)) }
        if end.y > extent.y { scale = min(scale, (extent.y - pose.position.y) / (end.y - pose.position.y)) }
        end = pose.position + (end - pose.position) * scale
        _, reach := sight_probe(grid, pose.position, end)
        out[i] = pose.position + (end - pose.position) * reach
    }
    return FAN_RAYS
}
