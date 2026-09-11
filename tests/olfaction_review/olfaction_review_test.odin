package olfaction_review

import obs "../../server/observations"
import perception "../../server/perception"
import "core:encoding/json"
import "core:os"
import "core:testing"

field_init :: proc(field: ^perception.Scent_Field, tile_size: f32 = 32) {
    media: [144]perception.Scent_Medium
    perception.scent_field_init(field, 12, 12, tile_size, media[:])
}

query_at :: proc(field: ^perception.Scent_Field, position: obs.Vector, range: f32 = 160) -> perception.Olfaction_Query {
    return {field = field, observer = {entity_id = 1, round_id = 1, pose = {position, .North}},
        profile = {enabled = true, range = range, sample_interval = 12, estimates_freshness = true}}
}

@(test)
short_diagonal_steps_deposit_on_the_intermediate_crossed_cell :: proc(t: ^testing.T) {
    field := new(perception.Scent_Field)
    defer free(field)
    start := obs.Vector{63.8, 63.5}
    finish := obs.Vector{64.55, 64.25}
    for reverse in ([2]bool{false, true}) {
        field_init(field)
        from, to := start, finish
        if reverse { from, to = finish, start }
        perception.scent_field_deposit(field, .Human, perception.scent_field_cell_of(field, from), 0.5)
        perception.scent_field_deposit_segment(field, .Human, from, to, perception.SCENT_EMISSION_PER_TICK)
        testing.expectf(t, perception.scent_field_level(field, .Human, {2, 1}) > 0,
            "The segment %v -> %v crosses the interior of cell (2,1), but leaves no scent there", from, to)
        testing.expect(t, perception.scent_field_level(field, .Human, {1, 2}) == 0,
            "The opposite corner cell was never crossed")
    }
}

@(test)
an_undetectable_trace_cannot_freshen_a_detected_old_trail :: proc(t: ^testing.T) {
    field := new(perception.Scent_Field)
    defer free(field)
    field_init(field)
    query := query_at(field, {112, 112})
    perception.scent_field_deposit(field, .Human, {3, 5}, 0.005)
    faint, _ := perception.olfaction_sample(query, 1, 1200, 1200)
    testing.expect(t, faint.reading_count == 0, "The fresh control trace is below detection")
    perception.scent_field_clear(field)
    perception.scent_field_deposit(field, .Human, {5, 3}, 0.4)
    field.ages[.Human][3 * field.width + 5] = 200
    old, _ := perception.olfaction_sample(query, 1, 1200, 1200)
    testing.expect(t, old.reading_count == 1 && old.readings[0].freshness == .Old)
    perception.scent_field_deposit(field, .Human, {3, 5}, 0.005)
    combined, _ := perception.olfaction_sample(query, 1, 1200, 1200)
    testing.expect(t, combined.reading_count == 1 && combined.readings[0].zones == old.readings[0].zones &&
        combined.readings[0].strength == old.readings[0].strength && combined.readings[0].bearing == old.readings[0].bearing)
    testing.expectf(t, combined.readings[0].freshness == .Old,
        "An undetectable fresh trace changed the old trail's freshness from %v to %v",
        old.readings[0].freshness, combined.readings[0].freshness)
}

Coverage_Fixture :: struct {
    sample: obs.Scent_Sample,
    tile_size: f32,
    cells_sampled, cells_blind: int,
}

@(test)
a_supported_small_nose_can_have_no_sampled_cells :: proc(t: ^testing.T) {
    field := new(perception.Scent_Field)
    defer free(field)
    field_init(field, 128)
    query := query_at(field, {448, 448}, 32)
    testing.expect(t, perception.olfaction_profile_valid(query.profile))
    sample, audit := perception.olfaction_sample(query, 1, 1200, 1200)
    testing.expect(t, sample.status == .Sampled && sample.reading_count == 0 && audit.cells_sampled == 0 && audit.cells_blind == 1)
    fixture := Coverage_Fixture{sample, field.tile_size, audit.cells_sampled, audit.cells_blind}
    data, error := json.marshal(fixture, {use_enum_names = true})
    defer delete(data)
    testing.expect(t, error == nil)
    if error == nil {
        testing.expect(t, os.write_entire_file("build/verification/olfaction-review-20260911/no-sampled-cells.json", data) == nil)
    }
}
