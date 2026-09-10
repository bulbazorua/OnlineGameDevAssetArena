# Larger land arenas and elevation

All three arenas now contain **60×28 tiles**, up from 20×14: **six times the total area** (3× width and 2× height). Tiles remain 32 world units, so each map measures 1,920×896 units. The change adds actual traversable space rather than enlarging the sprites.

```sh
make dev_arena P1=triangle P2=diamond ARENA=meadow_crossing AUDIENCE=1
```

## Layouts

The layouts use broad grassy clearings, connected dirt paths, forest borders, small ponds, and raised terraces inspired by classic top-down adventure games.

| Arena key | Design | Land (non-water) | Walkable area |
| --- | --- | --- | --- |
| `meadow_crossing` | Crossing paths, two offset terraces, two small ponds | 96.7% | 70.0% |
| `sandbar` | Grassland with small beaches and ponds, a broad northern terrace | 95.4% | 68.5% |
| `stone_garden` | Two northern terraces and a central southern terrace, with rock landmarks | 98.0% | 68.0% |

Forest, rocks, and cliff faces account for the difference between land and walkable area. Every walkable tile, including the high ground, connects to the player spawn region through legal land/stair routes. Both characters spawn on the broad central path, at cells `(12,14)` and `(47,14)`.

The layout recipes are in `tools/build_arena_maps.py`. Running that tool explicitly rewrites `client/content/data/arenas.json`; the game reads the saved JSON directly and never generates a new random map on startup. Hand-edit the JSON for local experiments, or change the recipes and regenerate when maintaining these baseline maps.

## Terrain and elevation

Terrain type and height are separate. Grass stays grass whether it is on the valley floor or a terrace.

| ID | Key | Symbol | Walkable |
| --- | --- | --- | --- |
| 1 | `grass` | `.` | Yes |
| 2 | `ground` | `g` | Yes |
| 3 | `sand` | `s` | Yes |
| 4 | `water` | `w` | No |
| 5 | `stone` | `#` | No |
| 6 | `cliff` | `c` | No |
| 7 | `stairs` | `=` | Yes |
| 8 | `forest` | `t` | No |
| 9 | `tall_grass` | `"` | Yes |

`arenas.json` uses **schema version 2**. Each arena has `elevation_rows` alongside its terrain `rows`, with matching dimensions. Each character is an integer level `0`–`3`; the current layouts use levels 0 and 1. Both Odin and Godot validate dimensions and values. Legacy schema-1 fixtures still load as flat maps; older builds reject the new schema instead of silently ignoring height.

The host and client prediction both block elevation changes unless the transition is exactly one level and touches a stairs tile. Cliff faces are also blocked by the normal circular-footprint collision. Stairs allow ascent and descent; walking off ledges, jumping, falling, height combat bonuses, and line-of-sight rules are outside this phase.

Each primary TileMap tile exposes `terrain_id`, `terrain_key`, `walkable`, and `elevation` custom data. The arena-selection inspector displays the level as well as terrain type. The lower `Ground` TileMapLayer supplies grass behind transparent art; gameplay and inspection use the primary `Terrain` layer and shared data. Flowers and weathering are decorative.

## Cameras

Camera behavior is now defined by [checkpoint 3H](03h-player-and-audience-cameras.md). Fighters stay centered on their own character at fixed zoom, including at map edges. Each audience member has independent pan/zoom controls, whole-map reset, and optional player follow.

Camera changes are local and never change character ownership, inputs, or authoritative positions. Audience still receives both players' states. The HUD has backdrops so labels remain readable while terrain scrolls beneath it.

## Art and implementation

Five original tilesheets were downloaded from Pixel-Boy's [Ninja Adventure asset pack](https://pixel-boy.itch.io/ninja-adventure-asset-pack), released under CC0. They provide grass, paths, trees, tall grass, rocks, water edges, cliffs, and stairs. The original license, source/version information, and SHA-256 hashes are in [the asset directory](../client/assets/ninja_adventure/SOURCE.md). These are independently released assets, not artwork extracted from Pokémon or Zelda.

| File | Responsibility |
| --- | --- |
| `client/content/data/arenas.json` | Larger maps, spawn cells, elevation rows |
| `client/content/data/terrains.json` | Nine terrain definitions |
| `client/content/arena_catalog.gd`, `server/arena.odin` | Matching schema validation, height queries, stair transition rules |
| `client/world/character_movement.gd`, `server/movement.odin` | Apply elevation and footprint collision together |
| `client/world/terrain_tileset.gd` | Atlas regions, connected edges, per-level tile alternatives and metadata |
| `client/world/arena_world.gd` / `.tscn` | Grass underlay, terrain rendering, decorative details |
| `client/world/game_arena.gd` / `.tscn`, `arena_camera.gd` | Arena presentation and role-specific camera controls |
| `server/elevation_test.odin` | Connectivity, land coverage, height validation, stair rules |
| `tests/land_movement_check.gd` | Real host/client stair traversal and camera controls |
| `tests/land_arena_render.gd` | Rendered map previews and selection-layout checks |

The ENet packet format remains version 5. Height comes from the shared map at a character's position; no new position fields are needed. Arena schema 2 and the existing content fingerprint require compatible data readers. Restart the host and clients together after this update; `make dev_arena` handles that automatically on relevant saves. Movement packets remain the same size on the larger maps.

## Checks and previews

```sh
make check_land
make check
godot --path client --script ../tests/land_arena_render.gd
python3 tests/dev_workflow_check.py --graphical
```

Checks cover all 5,040 primary terrain cells, elevation metadata, matching content readers, connected land/high-ground routes, movement into cliff/forest barriers, stair ascent/descent across two players and audience, follow/overview switching, and the existing launcher/reload behavior. The old 20×14 collision layout is retained only as a dedicated test fixture so its independent collision/wire examples remain stable.

The render command writes full-map previews and default/minimum-size arena-selection captures under `build/verification/land-previews/`. Graphical reload checks also capture the real player and audience windows. Input in these checks is synthesized; this is not an Internet latency or large-audience load benchmark.
