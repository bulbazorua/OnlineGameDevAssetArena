// Coding-agent coverage regressions for 6B.2 R3. Each test samples a real field with
// the production nose and writes the delivered sample for the rendered probe.
package olfaction_coverage

import obs "../../server/observations"
import perception "../../server/perception"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:testing"

FIXTURE_DIRECTORY :: "build/verification/olfaction-fix-20260911/fixtures"

Coverage_Fixture :: struct {
    label: string,
    sample: obs.Scent_Sample,
    tile_size: f32,
    cells_sampled, cells_blind, cells_excluded: int,
}

field_init :: proc(field: ^perception.Scent_Field, width, height: int, tile_size: f32, solid: [][2]int = {}) {
    media := make([]perception.Scent_Medium, width * height)
    defer delete(media)
    for cell in solid { media[cell.y * width + cell.x] = .Solid }
    perception.scent_field_init(field, width, height, tile_size, media)
}

query_at :: proc(field: ^perception.Scent_Field, position: obs.Vector, range: f32 = 160) -> perception.Olfaction_Query {
    return {field = field, observer = {entity_id = 1, round_id = 1, pose = {position, .North}},
        profile = {enabled = true, range = range, sample_interval = 12, estimates_freshness = true}}
}

count_coverage :: proc(sample: obs.Scent_Sample, coverage: obs.Scent_Coverage) -> (count: int) {
    for zone in sample.coverage { if zone == coverage { count += 1 } }
    return
}

// Scent may only appear in zones the nose measured; a sample never leaks host counts.
expect_honest :: proc(t: ^testing.T, sample: obs.Scent_Sample) {
    testing.expect(t, sample.status == .Sampled)
    readings := sample.readings
    for reading in readings[:sample.reading_count] {
        for band, zone in reading.zones { testing.expect(t, band == .None || sample.coverage[zone] != .Unsampled, "scent reported in a zone the nose never measured") }
    }
}

write_fixture :: proc(t: ^testing.T, fixture: Coverage_Fixture) {
    data, error := json.marshal(fixture, {use_enum_names = true})
    defer delete(data)
    testing.expect(t, error == nil)
    if error != nil { return }
    path := fmt.aprintf("%s/%s.json", FIXTURE_DIRECTORY, fixture.label)
    defer delete(path)
    testing.expectf(t, os.write_entire_file(path, data) == nil, "cannot write %s; create the evidence directory first", path)
}

@(test)
a_nose_that_measured_nothing_reports_every_zone_unknown :: proc(t: ^testing.T) {
    field := new(perception.Scent_Field)
    defer free(field)
    field_init(field, 12, 12, 128)
    perception.scent_field_deposit(field, .Human, {4, 3}, 1)
    sample, audit := perception.olfaction_sample(query_at(field, {448, 448}, 32), 1, 1200, 1200)
    expect_honest(t, sample)
    testing.expect(t, sample.reading_count == 0 && audit.cells_sampled == 0 && audit.cells_blind == 1)
    testing.expect(t, count_coverage(sample, .Unsampled) == obs.SCENT_ZONES, "zero measured cells must not read as sampled absence anywhere")
    write_fixture(t, {"zero-coverage", sample, field.tile_size, audit.cells_sampled, audit.cells_blind, audit.cells_excluded})
}

@(test)
a_nose_beside_the_map_edge_reports_partial_and_unknown_zones_with_scent_only_on_measured_ground :: proc(t: ^testing.T) {
    field := new(perception.Scent_Field)
    defer free(field)
    field_init(field, 20, 20, 32)
    // A fresh human trail runs south-east of the nose, well inside the map.
    for y in 3..=6 { perception.scent_field_deposit(field, .Human, {13, y}, 0.8) }
    sample, audit := perception.olfaction_sample(query_at(field, {336, 48}), 2, 1200, 1200)
    expect_honest(t, sample)
    testing.expect(t, sample.reading_count == 1 && sample.readings[0].class == .Human && sample.readings[0].bearing_valid)
    for sector in ([3]int{7, 0, 1}) {
        testing.expect(t, sample.coverage[obs.scent_zone_index(sector, true)] == .Unsampled && sample.coverage[obs.scent_zone_index(sector, false)] == .Partial)
    }
    testing.expect(t, count_coverage(sample, .Sampled) == 10 && count_coverage(sample, .Partial) == 3 && count_coverage(sample, .Unsampled) == 3)
    testing.expect(t, audit.cells_excluded > 0)
    write_fixture(t, {"partial-coverage", sample, field.tile_size, audit.cells_sampled, audit.cells_blind, audit.cells_excluded})
}

@(test)
a_nose_in_open_ground_reports_every_zone_measured_even_without_scent :: proc(t: ^testing.T) {
    field := new(perception.Scent_Field)
    defer free(field)
    field_init(field, 20, 20, 32)
    sample, audit := perception.olfaction_sample(query_at(field, {336, 336}), 3, 1200, 1200)
    expect_honest(t, sample)
    testing.expect(t, sample.reading_count == 0 && count_coverage(sample, .Sampled) == obs.SCENT_ZONES && audit.cells_excluded == 0)
    write_fixture(t, {"full-coverage-empty", sample, field.tile_size, audit.cells_sampled, audit.cells_blind, audit.cells_excluded})
}

@(test)
a_solid_column_inside_reach_makes_its_zones_partial :: proc(t: ^testing.T) {
    field := new(perception.Scent_Field)
    defer free(field)
    field_init(field, 20, 20, 32, solid = {{12, 8}, {12, 9}, {12, 10}, {12, 11}, {12, 12}})
    sample, audit := perception.olfaction_sample(query_at(field, {336, 336}), 4, 1200, 1200)
    expect_honest(t, sample)
    testing.expect(t, sample.coverage[obs.scent_zone_index(2, false)] == .Partial && sample.coverage[obs.scent_zone_index(6, false)] == .Sampled)
    testing.expect(t, audit.cells_excluded == 5 && count_coverage(sample, .Unsampled) == 0)
}
