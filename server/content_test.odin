package main

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
