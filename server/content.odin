package main

import "core:crypto/sha2"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import obs "observations"

Game_Content :: struct {
    characters: [dynamic]Character_Definition,
    fingerprint: [32]u8,
    terrains: [dynamic]Terrain_Definition,
    arenas: [dynamic]Arena_Definition,
    senses: [dynamic]Sense_Profile,
    trainer_emitter: obs.Scent_Emitter,
}

content_destroy :: proc(content: ^Game_Content) {
    for character in content.characters {
        delete(character.key)
        delete(character.display_name)
    }
    delete(content.characters)
    for terrain in content.terrains { delete(terrain.key); delete(terrain.display_name) }
    for arena in content.arenas { delete(arena.key); delete(arena.display_name); delete(arena.cells); delete(arena.elevations); delete(arena.opaque); delete(arena.scent_media) }
    for profile in content.senses { delete(profile.key) }
    delete(content.terrains)
    delete(content.arenas)
    delete(content.senses)
    content^ = {}
}

content_character :: proc(content: ^Game_Content, id: u16) -> ^Character_Definition {
    for &character in content.characters {
        if character.id == id { return &character }
    }
    return nil
}

// Sorted relative paths define the cross-language compatibility fingerprint.
CONTENT_FILES :: [4]string{"arenas.json", "characters.json", "senses.json", "terrains.json"}

content_load :: proc(content: ^Game_Content, directory: string) -> (ok: bool) {
    defer if !ok { content_destroy(content) }
    files: [4][]u8
    defer for data in files { delete(data) }
    for relative_path, index in CONTENT_FILES {
        path := fmt.aprintf("%s/%s", directory, relative_path)
        defer delete(path)
        data, error := os.read_entire_file(path, context.allocator)
        files[index] = data
        if error != nil {
            fmt.eprintfln("[host] Cannot read %s: %v", path, error)
            return false
        }
    }
    if !content_parse(content, files[1]) {
        fmt.eprintln("[host] Invalid character catalog: characters.json")
        return false
    }
    if !content_parse_extra(content, files[3], .Terrains) {
        fmt.eprintln("[host] Invalid terrain catalog: terrains.json")
        return false
    }
    if !content_parse_extra(content, files[2], .Senses) {
        fmt.eprintln("[host] Invalid sense catalog or character bindings: senses.json")
        return false
    }
    if !content_parse_extra(content, files[0], .Arenas) {
        fmt.eprintln("[host] Invalid arena catalog or spawn clearance: arenas.json")
        return false
    }
    content.fingerprint = content_digest(files)
    fmt.printfln("[host] Loaded %d characters, %d terrains, %d sense profiles, %d arenas.", len(content.characters), len(content.terrains), len(content.senses), len(content.arenas))
    return true
}

Content_Kind :: enum { Terrains, Arenas, Senses }
content_parse_extra :: proc(content: ^Game_Content, data: []u8, kind: Content_Kind) -> bool {
    temporary: mem.Dynamic_Arena
    mem.dynamic_arena_init(&temporary, alignment = 64)
    defer mem.dynamic_arena_destroy(&temporary)
    parser := json.make_parser(data, spec = .JSON, parse_integers = true, allocator = mem.dynamic_arena_allocator(&temporary))
    value, error := json.parse_value(&parser)
    if error != nil || parser.curr_token.kind != .EOF { return false }
    root, root_ok := value.(json.Object)
    if !root_ok { return false }
    schema, schema_ok := content_integer(root["schema_version"])
    if !schema_ok { return false }
    switch kind {
    case .Terrains: return schema == 3 && content_parse_terrains(content, root)
    case .Arenas: return (schema == 1 || schema == 2) && content_parse_arenas(content, root)
    case .Senses: return schema == 2 && content_parse_senses(content, root)
    }
    return false
}

content_hash_file :: proc(hash: ^sha2.Context_256, path: string, data: []u8) {
    length: [4]u8
    protocol_write_u32(length[:], u32(len(path)))
    sha2.update(hash, length[:])
    sha2.update(hash, transmute([]u8)path)
    protocol_write_u32(length[:], u32(len(data)))
    sha2.update(hash, length[:])
    sha2.update(hash, data)
}

content_digest :: proc(files: [4][]u8) -> (digest: [32]u8) {
    hash: sha2.Context_256
    sha2.init_256(&hash)
    for path, index in CONTENT_FILES { content_hash_file(&hash, path, files[index]) }
    sha2.final(&hash, digest[:])
    return
}

// Parse character definitions. Full startup also requires terrain and arena catalogs.
content_parse :: proc(content: ^Game_Content, data: []u8) -> (ok: bool) {
    assert(len(content.characters) == 0)
    defer if !ok { content_destroy(content) }
    // Parsing uses temporary storage, including partially parsed invalid files.
    temporary: mem.Dynamic_Arena
    mem.dynamic_arena_init(&temporary, alignment = 64) // JSON object maps need cache-line alignment.
    defer mem.dynamic_arena_destroy(&temporary)
    parser := json.make_parser(data, spec = .JSON, parse_integers = true, allocator = mem.dynamic_arena_allocator(&temporary))
    value, error := json.parse_value(&parser)
    if error != nil || parser.curr_token.kind != .EOF { return false }
    root, root_ok := value.(json.Object)
    if !root_ok { return false }
    schema, schema_ok := content_integer(root["schema_version"])
    if !schema_ok || schema != 1 { return false }
    entries, entries_ok := root["characters"].(json.Array)
    if !entries_ok || len(entries) == 0 || len(entries) > 65535 { return false }
    for entry in entries {
        fields, fields_ok := entry.(json.Object)
        if !fields_ok { return false }
        id, id_ok := content_integer(fields["id"])
        key, key_ok := fields["key"].(json.String)
        name, name_ok := fields["display_name"].(json.String)
        radius: f64
        #partial switch number in fields["footprint_radius"] {
        case json.Integer: radius = f64(number)
        case json.Float: radius = f64(number)
        case: return false
        }
        if !id_ok || id < 1 || id > 65535 || !key_ok || len(key) == 0 || !name_ok || len(strings.trim_space(string(name))) == 0 {
            return false
        }
        if !(radius >= 1.401298464324817e-45 && radius <= 3.4028234663852886e38) { return false }
        for char in key {
            if !(char >= 'a' && char <= 'z' || char >= '0' && char <= '9' || char == '_') { return false }
        }
        for previous in content.characters {
            if previous.id == u16(id) || previous.key == string(key) { return false }
        }
        append(&content.characters, Character_Definition{
            id = u16(id), key = strings.clone(string(key)),
            display_name = strings.clone(string(name)), footprint_radius = f32(radius),
        })
    }
    hash: sha2.Context_256
    sha2.init_256(&hash)
    content_hash_file(&hash, "characters.json", data)
    sha2.final(&hash, content.fingerprint[:])
    return true
}

// JSON numbers such as 1, 1.0, and 1e0 denote the same catalog integer.
content_integer :: proc(value: json.Value) -> (i64, bool) {
    #partial switch number in value {
    case json.Integer: return i64(number), true
    case json.Float:
        if number >= 0 && number <= 65535 && math.floor(f64(number)) == f64(number) {
            return i64(number), true
        }
    }
    return 0, false
}
