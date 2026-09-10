# Checkpoint 3J: Tiny Swords Village

Implemented: a fourth arena, `tiny_swords_village`, using the supplied local Tiny Swords Free Pack. Character animation, combat states, and the general art pipeline are **proposals** in [phase 4](04-character-architecture-proposal.md).

## Run it

The reviewed subset is already installed in this workspace. After a fresh checkout, import your own copy of the pack:

```sh
make import_tiny_swords
# Optional alternate source directory:
make import_tiny_swords ASSET_SOURCE="/path/to/Tiny Swords (Free Pack)"

make dev_arena P1=triangle P2=diamond ARENA=tiny_swords_village AUDIENCE=1
```

The audience still defaults to a five-second delay. Append `AUDIENCE_DELAY=0` when testing simultaneous movement or building collision. The map also appears in normal shared arena selection, including the audience preview.

## World layout and rules

The village has 60×28 cells at 32 world units each: 1920×896 world units, the same dimensions as the other expanded arenas. Grass surrounds connecting ground paths, two ponds with sand banks, and a northern raised terrace with stairs. Blue and red castles mark the two sides. Twelve props include those castles, an archery building, barracks, monastery, two towers, and five houses.

Each cell retains `terrain_id`, `terrain_key`, `walkable`, and `elevation`. The new terrain is ID **10**, key **`building`**, glyph **`b`**, `walkable = false`. Grass, ground, sand, tall grass and stairs remain walkable; water, stone, cliff, forest and building cells block movement. The existing height/stair rules apply. Terrain effects are still future work.

Building ground footprints are baked into the shared map rows. Odin and client prediction therefore block the same cells using existing collision rules. Buildings are static obstacles; there are no entrances, interiors, health, or destruction in this checkpoint.

Roofs may extend above a building's footprint. Its sprite origin sits at the bottom-center of that footprint; the source feet anchor is offset to that origin. Characters and props share Y sorting by ground position. The camera continues to track the fighter's gameplay position, and each audience camera remains independent.

## Native pixels and world measurements

`AssetScale` converts an authored source measurement to the desired world span:

```text
render_scale = gameplay_size × 32 / reference_span_px
```

Tiny Swords' 64px terrain tiles use scale 0.5, while the existing 16px terrain uses scale 2. Both occupy a 32-unit cell. The village castle uses a 320px facade reference at gameplay size 5: 160 world units wide. Source PNGs remain unmodified.

The pack's terrain sheets provide grass color variants. The village applies rendering tints for brown ground paths and pale sand banks. Bushes use their first animation frame. North/south stairs use simple drawn treads because the supplied slope art faces sideways. Water, bushes and buildings are static for this phase.

Character `gameplay_size`, collision normalization and an import preview are described in the [sizing proposal](04b-gameplay-size-proposal.md). The four shapes still use their existing radius; this terrain checkpoint introduces the reusable conversion helper without migrating character data.

## Files and ownership

| File / type | Responsibility |
| --- | --- |
| `tools/import_tiny_swords.py` | Validate source files, dimensions and hashes before installing the selected PNGs locally |
| `client/assets/tiny_swords/manifest.json`, `SOURCE.md` | Pack inventory, provenance and source terms |
| `client/presentation/asset_scale.gd` / `AssetScale` | Source-reference-to-world conversion |
| `client/content/presentation/arenas/tiny_swords_village.json` | Theme, prop textures, reference spans, gameplay sizes, feet anchors and cell footprints |
| `client/content/arena_presentation.gd` / `ArenaPresentation` | Validate prop data, dimensions, matching blocked cells and complete footprint coverage |
| `tools/build_arena_maps.py` | Explicit map authoring; stamp the presentation's footprints into shared terrain rows |
| `client/content/data/arenas.json`, `terrains.json` | Authoritative map and terrain types, read by Odin and Godot |
| `client/content/game_content.gd` / `GameContent` | Load each arena presentation and build tile sets per theme |
| `client/world/tiny_swords_tileset.gd` / `TinySwordsTileset` | 64px atlas mapping and cliff/shore adjacency |
| `client/world/terrain_tileset.gd` / `TerrainTileset` | Shared tile construction, terrain/elevation metadata and optional rendering tint |
| `client/world/arena_world.gd` / `ArenaWorld` | Render the chosen theme, decorations and grounded building sprites |
| `client/ui/arena_preview.gd` / `ArenaPreview` | Fit the map and keep its ground layers visible over the selection background |
| `tests/tiny_swords_check.gd` | Real host, two fighters and audience: loading, collision, theme switching and normalized sprite bounds |
| `tests/land_arena_render.gd` | Full maps, selection visibility/layout and behind/in-front building occlusion |

To reposition or resize buildings, edit their presentation entries, then run `python3 tools/build_arena_maps.py` and the checks. A visual width inconsistent with its cell footprint, a missing texture, overlapping props, or an unmatched building cell fails validation. This generator is an explicit authoring command; startup does not rewrite content.

Shared map bytes continue to participate in the content fingerprint. Presentation JSON remains client-only. The wire layout stays at protocol 6 because no new message fields are needed. The development launcher sees map/presentation edits and validates/relaunches the scenario using its existing workflow.

## Source assets

The selected 18 PNG files came from the supplied local directory. Their SHA-256 values and dimensions are recorded in the manifest. The current pack has custom terms restricting raw-asset redistribution, so these runtime PNG copies are ignored by Git; the manifest, importer, source record, maps, and code can be versioned. See the [local source record](../client/assets/tiny_swords/SOURCE.md) and [publisher terms](https://pixelfrog-assets.itch.io/tiny-swords).

This is a local import requirement for a fresh checkout. Run the importer before launching or validating a client; a missing building texture reports that command. The host itself only needs the shared JSON catalogs.

## Verification

```sh
make check_tiny_swords_assets
make check_tiny_swords
make check_arena_content
make check

# Requires a graphical display; produces ignored PNG review artifacts.
godot --path client --script "$PWD/tests/land_arena_render.gd"
```

The content check covers all 6,720 cells across four maps. The host's existing land-connectivity checks include the village and its high ground. Rendering checks place a real `CharacterView` behind and in front of a castle, and inspect selection terrain pixels at default/minimum window sizes. Captures are written to `build/verification/land-previews/`.
