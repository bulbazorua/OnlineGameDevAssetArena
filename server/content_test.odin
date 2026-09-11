package main

import "core:strings"
import "core:testing"

CONTENT_FIXTURE :: `{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":12}]}`
// Independently calculated using Python hashlib.sha256 and struct.pack("<I", length).
CONTENT_FIXTURE_DIGEST :: [32]u8{0x29, 0x16, 0x82, 0x31, 0xde, 0xa5, 0x9a, 0x12, 0xb1, 0x4e, 0x13, 0x48, 0x2d, 0x71, 0xa2, 0xa7, 0xc9, 0x03, 0x24, 0xdf, 0xdd, 0xac, 0xba, 0xcb, 0x50, 0xa5, 0x43, 0xb5, 0x88, 0x2f, 0x58, 0xe8}

@(test)
content_validates_and_matches_digest_fixture :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_parse(&content, transmute([]u8)string(CONTENT_FIXTURE)))
    testing.expect(t, content.fingerprint == CONTENT_FIXTURE_DIGEST)
    testing.expect(t, len(content.characters) == 1 && content.characters[0].key == "circle" && content.characters[0].footprint_radius == 12)
    content_destroy(&content)
    numeric := `{"schema_version":1.0,"characters":[{"id":1e0,"key":"circle","display_name":"Circle","footprint_radius":12.5}]}`
    testing.expect(t, content_parse(&content, transmute([]u8)numeric))
    testing.expect(t, content.characters[0].id == 1 && content.characters[0].footprint_radius == 12.5)
    content_destroy(&content)
}

@(test)
content_rejects_invalid_definitions_and_releases_partial_loads :: proc(t: ^testing.T) {
    for invalid in ([]string{
        `{`,
        `[]`,
        `{"schema_version":1,"characters":[]}`,
        `{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":12}]} false`,
        `{"schema_version":2,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":12}]}`,
        `{"schema_version":1,"characters":[{"id":0,"key":"circle","display_name":"Circle","footprint_radius":12}]}`,
        `{"schema_version":1,"characters":[{"id":65536,"key":"circle","display_name":"Circle","footprint_radius":12}]}`,
        `{"schema_version":1,"characters":[{"id":1.5,"key":"circle","display_name":"Circle","footprint_radius":12}]}`,
        `{"schema_version":1,"characters":[{"id":true,"key":"circle","display_name":"Circle","footprint_radius":12}]}`,
        `{"schema_version":1,"characters":[{"id":1,"key":"../circle","display_name":"Circle","footprint_radius":12}]}`,
        `{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":" ","footprint_radius":12}]}`,
        `{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":0}]}`,
        `{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":-2}]}`,
        `{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":1e100}]}`,
        `{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":1e-100}]}`,
        `{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":12},{"id":1,"key":"square","display_name":"Square","footprint_radius":12}]}`,
        `{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":12},{"id":2,"key":"circle","display_name":"Square","footprint_radius":12}]}`,
    }) {
        content: Game_Content
        testing.expect(t, !content_parse(&content, transmute([]u8)invalid), invalid)
        testing.expect(t, len(content.characters) == 0 && content.fingerprint == [32]u8{})
        content_destroy(&content)
    }
}

@(private = "file")
SENSES_FIXTURE :: `{"schema_version":2,"profiles":[{"key":"starter_senses","vision":{"enabled":true,"range_units":8.0,"focused_fov_degrees":60.0,"overall_fov_degrees":160.0,"sample_interval_ticks":6},"olfaction":{"receptor":{"enabled":true,"range_units":5.0,"sample_interval_ticks":12,"estimates_freshness":true},"emitter":{"enabled":true,"scent_class":"human","intensity":1.0}}}],"trainer_emitter":{"enabled":true,"scent_class":"human","intensity":1.0},"bindings":[{"character":"circle","profile":"starter_senses"}]}`

@(private = "file")
VISION_OK :: `"vision":{"enabled":true,"range_units":8,"focused_fov_degrees":60,"overall_fov_degrees":160,"sample_interval_ticks":6}`
@(private = "file")
OLFACTION_OK :: `"olfaction":{"receptor":{"enabled":true,"range_units":5,"sample_interval_ticks":12,"estimates_freshness":true},"emitter":{"enabled":true,"scent_class":"human","intensity":1}}`
@(private = "file")
TRAINER_OK :: `"trainer_emitter":{"enabled":true,"scent_class":"human","intensity":1}`

@(private = "file")
content_test_senses :: proc(senses: string, characters := CONTENT_FIXTURE) -> (ok: bool) {
    content: Game_Content
    defer content_destroy(&content)
    if !content_parse(&content, transmute([]u8)characters) { return false }
    return content_parse_extra(&content, transmute([]u8)senses, .Senses)
}

// One profile bound to circle, with the given vision/olfaction/trainer fragments.
// Built by concatenation because braces are format placeholders for fmt.
@(private = "file")
senses_with :: proc(vision := VISION_OK, olfaction := OLFACTION_OK, trainer := TRAINER_OK, bindings := `[{"character":"circle","profile":"p"}]`) -> string {
    return strings.concatenate({`{"schema_version":2,"profiles":[{"key":"p",`, vision, `,`, olfaction, `}],`, trainer, `,"bindings":`, bindings, `}`}, context.temp_allocator)
}

@(private = "file")
two_profiles :: proc(second_vision: string, trainer := TRAINER_OK) -> string {
    return strings.concatenate({`{"schema_version":2,"profiles":[{"key":"a",`, VISION_OK, `,`, OLFACTION_OK, `},{"key":"b",`, second_vision, `,`, OLFACTION_OK, `}],`, trainer, `,"bindings":[{"character":"square","profile":"b"},{"character":"circle","profile":"a"}]}`}, context.temp_allocator)
}

@(test)
sense_catalog_validates_profiles_bindings_and_bounds :: proc(t: ^testing.T) {
    content: Game_Content
    testing.expect(t, content_parse(&content, transmute([]u8)string(CONTENT_FIXTURE)))
    testing.expect(t, content_parse_extra(&content, transmute([]u8)string(SENSES_FIXTURE), .Senses))
    testing.expect(t, len(content.senses) == 1 && content.senses[0].key == "starter_senses" && content.senses[0].vision == {true, 256, 60, 160, 6})
    testing.expect(t, content.senses[0].olfaction == {true, 160, 12, true} && content.senses[0].emitter == {true, .Human, 1})
    testing.expect(t, content.characters[0].sense_profile == "starter_senses" && content.characters[0].vision.range == 256)
    testing.expect(t, content.characters[0].olfaction.range == 160 && content.characters[0].emitter.class == .Human && content.trainer_emitter == {true, .Human, 1})
    content_destroy(&content)
    valid_edges := []string{
        senses_with(vision = `"vision":{"enabled":false,"range_units":64,"focused_fov_degrees":45,"overall_fov_degrees":180,"sample_interval_ticks":1}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":1e-3,"focused_fov_degrees":45,"overall_fov_degrees":46,"sample_interval_ticks":60}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":false,"range_units":32,"sample_interval_ticks":60,"estimates_freshness":false},"emitter":{"enabled":false,"scent_class":"orc","intensity":4}}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":true,"range_units":1e-3,"sample_interval_ticks":1,"estimates_freshness":true},"emitter":{"enabled":true,"scent_class":"orc","intensity":1e-3}}`),
        senses_with(trainer = `"trainer_emitter":{"enabled":false,"scent_class":"orc","intensity":2}`),
    }
    for edge in valid_edges { testing.expect(t, content_test_senses(edge), edge) }
    two := `{"schema_version":1,"characters":[{"id":1,"key":"circle","display_name":"Circle","footprint_radius":12},{"id":2,"key":"square","display_name":"Square","footprint_radius":12}]}`
    testing.expect(t, content_test_senses(two_profiles(`"vision":{"enabled":false,"range_units":2,"focused_fov_degrees":90,"overall_fov_degrees":120,"sample_interval_ticks":12}`), two))
    for invalid in ([]string{
        `{`,
        `{"schema_version":1,"profiles":[],"bindings":[]}`,
        `{"schema_version":2,"profiles":[],"bindings":[]}`,
        SENSES_FIXTURE + " x",
        strings.concatenate({`{"schema_version":2,"profiles":[{"key":"Starter",`, VISION_OK, `,`, OLFACTION_OK, `}],`, TRAINER_OK, `,"bindings":[{"character":"circle","profile":"Starter"}]}`}, context.temp_allocator),
        senses_with(vision = `"vision":{"enabled":1,"range_units":8,"focused_fov_degrees":60,"overall_fov_degrees":160,"sample_interval_ticks":6}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":0,"focused_fov_degrees":60,"overall_fov_degrees":160,"sample_interval_ticks":6}`),
        senses_with(vision = `"vision":{"enabled":false,"range_units":0,"focused_fov_degrees":60,"overall_fov_degrees":160,"sample_interval_ticks":6}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":64.5,"focused_fov_degrees":60,"overall_fov_degrees":160,"sample_interval_ticks":6}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":1e400,"focused_fov_degrees":60,"overall_fov_degrees":160,"sample_interval_ticks":6}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":8,"focused_fov_degrees":44.9,"overall_fov_degrees":160,"sample_interval_ticks":6}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":8,"focused_fov_degrees":160,"overall_fov_degrees":160,"sample_interval_ticks":6}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":8,"focused_fov_degrees":60,"overall_fov_degrees":180.1,"sample_interval_ticks":6}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":8,"focused_fov_degrees":60,"overall_fov_degrees":160,"sample_interval_ticks":0}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":8,"focused_fov_degrees":60,"overall_fov_degrees":160,"sample_interval_ticks":61}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":8,"focused_fov_degrees":60,"overall_fov_degrees":160,"sample_interval_ticks":1.5}`),
        senses_with(vision = `"vision":{"enabled":true,"range_units":8,"focused_fov_degrees":60,"overall_fov_degrees":160}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":true,"range_units":5,"sample_interval_ticks":12,"estimates_freshness":true}}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":true,"range_units":0,"sample_interval_ticks":12,"estimates_freshness":true},"emitter":{"enabled":true,"scent_class":"human","intensity":1}}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":false,"range_units":32.5,"sample_interval_ticks":12,"estimates_freshness":true},"emitter":{"enabled":true,"scent_class":"human","intensity":1}}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":true,"range_units":5,"sample_interval_ticks":0,"estimates_freshness":true},"emitter":{"enabled":true,"scent_class":"human","intensity":1}}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":true,"range_units":5,"sample_interval_ticks":12,"estimates_freshness":"yes"},"emitter":{"enabled":true,"scent_class":"human","intensity":1}}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":true,"range_units":5,"sample_interval_ticks":12,"estimates_freshness":true},"emitter":{"enabled":true,"scent_class":"robot","intensity":1}}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":true,"range_units":5,"sample_interval_ticks":12,"estimates_freshness":true},"emitter":{"enabled":false,"scent_class":"human","intensity":0}}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":true,"range_units":5,"sample_interval_ticks":12,"estimates_freshness":true},"emitter":{"enabled":true,"scent_class":"human","intensity":4.5}}`),
        senses_with(olfaction = `"olfaction":{"receptor":{"enabled":true,"range_units":5,"sample_interval_ticks":12,"estimates_freshness":true},"emitter":{"enabled":true,"intensity":1}}`),
        senses_with(trainer = `"trainer_emitter":{"enabled":true,"scent_class":"human"}`),
        strings.concatenate({`{"schema_version":2,"profiles":[{"key":"p",`, VISION_OK, `,`, OLFACTION_OK, `}],"bindings":[{"character":"circle","profile":"p"}]}`}, context.temp_allocator),
        strings.concatenate({`{"schema_version":2,"profiles":[{"key":"p",`, VISION_OK, `,`, OLFACTION_OK, `},{"key":"p",`, VISION_OK, `,`, OLFACTION_OK, `}],`, TRAINER_OK, `,"bindings":[{"character":"circle","profile":"p"}]}`}, context.temp_allocator),
        senses_with(bindings = `[]`),
        senses_with(bindings = `[{"character":"square","profile":"p"}]`),
        senses_with(bindings = `[{"character":"circle","profile":"missing"}]`),
        senses_with(bindings = `[{"character":"circle","profile":"p"},{"character":"circle","profile":"p"}]`),
        senses_with(bindings = `{"circle":"p"}`),
    }) {
        testing.expect(t, !content_test_senses(invalid), invalid)
    }
    // Two characters need two bindings: a missing one is rejected.
    testing.expect(t, !content_test_senses(SENSES_FIXTURE, two))
}

@(test)
terrain_catalog_requires_schema_three_with_explicit_sight_and_scent_rules :: proc(t: ^testing.T) {
    for terrains in ([]string{
        `{"schema_version":2,"terrains":[{"id":1,"key":"grass","display_name":"Grass","symbol":".","walkable":true,"blocks_vision":false,"scent":"open"}]}`,
        `{"schema_version":3,"terrains":[{"id":1,"key":"grass","display_name":"Grass","symbol":".","walkable":true,"scent":"open"}]}`,
        `{"schema_version":3,"terrains":[{"id":1,"key":"grass","display_name":"Grass","symbol":".","walkable":true,"blocks_vision":"no","scent":"open"}]}`,
        `{"schema_version":3,"terrains":[{"id":1,"key":"grass","display_name":"Grass","symbol":".","walkable":true,"blocks_vision":false}]}`,
        `{"schema_version":3,"terrains":[{"id":1,"key":"grass","display_name":"Grass","symbol":".","walkable":true,"blocks_vision":false,"scent":"mud"}]}`,
        `{"schema_version":4,"terrains":[{"id":1,"key":"grass","display_name":"Grass","symbol":".","walkable":true,"blocks_vision":false,"scent":"open"}]}`,
    }) {
        content: Game_Content
        testing.expect(t, !content_parse_extra(&content, transmute([]u8)terrains, .Terrains), terrains)
        content_destroy(&content)
    }
    content: Game_Content
    defer content_destroy(&content)
    testing.expect(t, content_parse_extra(&content, transmute([]u8)string(`{"schema_version":3,"terrains":[{"id":4,"key":"water","display_name":"Water","symbol":"w","walkable":false,"blocks_vision":false,"scent":"water"},{"id":5,"key":"stone","display_name":"Stone","symbol":"#","walkable":false,"blocks_vision":true,"scent":"solid"},{"id":9,"key":"tall_grass","display_name":"Tall grass","symbol":"t","walkable":true,"blocks_vision":true,"scent":"open"}]}`), .Terrains))
    testing.expect(t, !content.terrains[0].walkable && !content.terrains[0].blocks_vision && content.terrains[0].scent == .Water)
    testing.expect(t, content.terrains[1].blocks_vision && content.terrains[1].scent == .Solid)
    // Scent is authored on its own: sight-blocking tall grass can still carry scent.
    testing.expect(t, content.terrains[2].blocks_vision && content.terrains[2].scent == .Open)
}
