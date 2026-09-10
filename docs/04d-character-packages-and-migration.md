# Proposal: character package layout and phased migration

Status: **checkpoints 4A through 4C implemented; combat work remains proposed**. The user's subsequent request makes animation-complete characters selectable in the movement sandbox now; [4C](04i-playable-characters.md) supersedes the earlier isolated-only movement/admission ordering below. The full combat package layout and certification commands remain proposed.

The intervening [4A.1 processing checkpoint](04g-character-asset-processing.md) now supplies raw/processed separation and failure tracing. Its preview artifacts live under `build/processed/characters/`; the runtime `generated/` resource layout below remains a later integration.

Each character requires its own custom-built importer and exporter. The current movement sandbox requires all five art roles before loading real characters into selection. The [Basic Combat v1 harness](04e-character-harness-and-base-contract.md) additionally proposes full gameplay verification before combat certification.

## Current source evidence

Inspected `client/assets/Characters` on 2026-09-10. It currently contains **Archer, Lancer, Monk, Orc and Warrior**. These are available assets; `characters.json` still registers only Circle, Square, Triangle and Diamond, with IDs 1–4. `CharacterVisual` and its loader still validate shape placeholders.

| Package candidate | Files and observed image dimensions | Character-owned import decisions |
| --- | --- | --- |
| Archer | Idle 1152×192; Run 768×192; Shoot 1536×192; Arrow 64×64; added Hurt/Death 2172×724 each | 192px body frames: 6 idle, 4 walk, 8 shoot; custom normalized crops for 6 hurt/7 death poses; Arrow is a separate projectile visual |
| Warrior | Idle 1536×192; Run/Guard 1152×192; Attack1/2 768×192 | Candidate 192px frames: 8 idle, 6 walk/guard, 4 per attack; assign explicit attack variants |
| Lancer | Idle 3840×320; Run 1920×320; five Attack files 960×320; five Defence files 1920×320 | Candidate 320px frames; directional bindings for Down, DownRight, Right, UpRight and Up; mirrored directions need review |
| Monk | Idle/Run 1152×192 / 768×192; Heal and Heal_Effect 2112×192 | Candidate 192px frames; generic filenames are scoped to Monk; body cast and separate effect layer |
| Orc | Combined sheet 800×600; Idle 600×100; Walk 800×100; Attack01/02 600×100; Hurt/Death 400×100 | Candidate 100px frames; choose split strips first, combined atlas as an alternative source, not duplicate animations |

The idle images and Orc's combined sheet were visually inspected. The [4B implementation](04h-archer-and-orc-modules.md) now verifies Archer/Orc frame extraction, preview playback, declared facing fallbacks and neutral-body calibration; the other characters remain inventory candidates. Action markers and authoritative timing remain later combat work. Per-module source inventories record local provenance for Archer and Orc; their packs have separate source records.

The different layouts are the reason for a package-owned adapter boundary. There must be no global 192px frame assumption, no folder-wide alphabetical animation ordering and no global filename-to-state inference.

## Proposed source layout

Keep existing PNG paths during the first migration. Co-locate each character's authored gameplay and import decisions in a package; declare references to the existing asset roots. The package is self-contained in behavior/configuration and can later bundle its assets when appropriate.

```text
client/
├── assets/Characters/                       Existing source PNGs, initially unchanged
├── characters/
│   ├── packages/
│   │   ├── registry.json                    Candidate module/exporter paths; no frame/layout logic
│   │   ├── archer/
│   │   │   ├── importer.gd                  Required Archer-specific source interpretation
│   │   │   ├── exporter.gd                  Required public CharacterExports assembly
│   │   │   ├── definition.json              Private authored identity, metrics and loadout
│   │   │   ├── art.json                     Private art configuration, interpreted by this module
│   │   │   ├── ai.json                      Private AI configuration or explicit player_only policy
│   │   │   └── generated/
│   │   │       ├── visual.tres              CharacterVisual referencing the normalized animation set
│   │   │       └── animations.tres          CharacterAnimationSet / SpriteFrames and binding resources
│   │   ├── orc/                             Own required importer/exporter; same public contracts
│   │   ├── warrior/
│   │   ├── lancer/
│   │   └── monk/
│   ├── import/
│   │   ├── character_importer.gd            Build-time CharacterImporter interface
│   │   ├── character_module_exporter.gd     CharacterModuleExporter interface
│   │   ├── character_exports.gd             Public art/state/gameplay/AI export schema
│   │   ├── character_package_builder.gd     Module dispatch, output validation and artifact writing
│   │   ├── sprite_sheet_reader.gd           Shared grid/region/image-sequence extraction helpers
│   │   └── normalized_character_art.gd     Common intermediate output, independent of filenames
│   ├── animation_role.gd                    Canonical role/facing/variant definitions
│   ├── animation_binding.gd                 Clip lookup, anchor, fallback and phase ranges
│   ├── character_animation_set.gd           Immutable normalized animation resource
│   ├── character_animation.gd               Per-instance state-to-role and phase playback
│   ├── character_visual.gd                  Evolve existing resource; retain shape fallback
│   └── character_view.gd / .tscn            Shared ground-root presentation composition
├── presentation/asset_scale.gd              Existing pixel-to-world helper
├── content/
│   ├── character_metrics.gd                 Shared character measurement validation/derivation
│   ├── character_catalog.gd                 Admitted catalog assembly and normalized component reader
│   ├── game_content.gd                      Existing application content entry point
│   └── data/
│       ├── characters.json                  Runtime catalog generated from admitted module exports
│       ├── abilities.json                   Later shared ability definitions
│       └── projectiles.json                 Later shared projectile definitions
├── projectiles/
│   └── projectile_view.gd / .tscn           Later shared projectile presentation
└── dev/
    └── character_harness.gd / .tscn         Art-preview and combat modes; real CharacterView
tools/
├── import_character_art.py                  Proposed command wrapper; invokes the Godot importer
└── build_character_catalog.py               Deterministic authoring-to-runtime JSON compilation
```

Do not create every file at once. Each implemented character gets its own required `importer.gd` and `exporter.gd`; there is no manifest-only shortcut through a global importer. Each importer may call shared extraction utilities, while its source interpretation remains custom-built and local. The private JSON files are recommended organization, not formats parsed by other character modules or the global coordinator.

Shared Odin systems remain focused files in the existing `server` package:

| Proposed file / types | Responsibility / introduction |
| --- | --- |
| `character_metrics.odin` / `Character_Metrics` | Size and footprint derivation; first measurement checkpoint |
| `character_components.odin` / typed definitions and runtime records | Split identity, movement, health, hurtbox and ability state as each becomes real |
| `character_intent.odin` / `Character_Intent` | Human and later AI intent accepted by shared rules |
| `character_state.odin` / `Locomotion_State`, `Action_State` | Common transitions and timers; no per-character state classes |
| `abilities.odin` / `Ability_Definition`, `Ability_Effect` | Shared action durations, loadouts and effect dispatch |
| `combat_geometry.odin` / `Hit_Shape`, `Hit_Payload` | Shared hitbox/hurtbox transforms, overlap and swept queries |
| `combat.odin` / `combat_step` | Hit validation, repeat-hit suppression and shared health effects |
| `projectiles.odin` / `Projectile_Definition`, `Projectile` | Spawn, integrate, sweep, resolve and expire projectiles |
| `world_snapshot.odin` / `World_Snapshot` | Value-owned replication/history records before dynamic combat entities |

Existing `movement.odin`, `session.odin`, `content.odin`, `network.odin`, `protocol.odin`, client protocol/snapshot files and `GameArena` receive focused integrations. Keep working prediction, terrain collision, selection, cameras and audience delay in service throughout the migration.

## Authoring data and runtime data

Choose **compiled runtime catalogs** so packages can own their definitions while the deployed Odin server continues reading JSON without Godot or asset import code.

Each module owns its authored configuration, conventionally `packages/<key>/definition.json`, and transforms it through its exporter. The registry lists candidate module entry points. `build_character_catalog.py` consumes validated gameplay definitions and AI exports from harness-admitted packages and writes `client/content/data/characters.json` deterministically, sorted by explicit stable ID. Runtime definitions include the normalized AI policy/backend/profile so authoritative AI settings participate in the gameplay fingerprint. The compiler does not parse each module's private configuration. Never assign IDs from filesystem order. Imported visuals are bound by that ID and module key.

The runtime catalog is generated and reviewable; hand edits would be overwritten. During the first migration, represent the four existing shapes as lightweight legacy package definitions before switching ownership, and verify the generator reproduces their effective radii/IDs. Do not maintain two independently editable versions of character settings.

Keep numeric IDs 1–4 for shapes as regression fixtures. Append new stable IDs for animated characters, promoting them into the normal roster only after all Basic Combat v1 harness checks and any required extensions pass. Do not silently redefine `triangle` to mean Archer: existing launcher scenarios and saved IDs must stay understandable. Candidate previews are separate from the admitted match catalog.

Shared abilities/projectiles have their own canonical definition catalogs. A character package refers to those IDs/keys, never to another character's implementation. Missing references fail validation. Character packages can use the same arrow definition or different projectile parameters while using the same runtime system.

The current fingerprint covers exactly three files: `arenas.json`, `characters.json`, `terrains.json`. Initial isolated movement work can keep that path list while migrating its schema on both readers. Before enabling Basic Combat admission, include the authoritative base/extension contract rules and applicable ability/projectile catalogs in the coordinated fingerprint input. Update both readers, digest fixtures, deployment requirements and compatibility documentation together. Source PNGs, private art configuration and generated visual resources remain presentation dependencies, outside the gameplay digest.

`GameContent` should resolve a registered visual resource instead of assuming `visuals/<key>.tres` and `placeholder_kind <= 3`. `GameArena` still creates the same `CharacterView` interface. The dev launcher must build/validate catalogs in its staged candidate before `validate_choices` reads the scenario keys, then import the selected package resources before client validation. These are proposed integrations, not existing automatic behavior.

## Example package-owned animation mapping

This is **one possible private Archer configuration**, not a globally enforced importer schema, import-ready file or approved art calibration. Archer's own importer/exporter interprets it and emits the shared `CharacterExports` contract. Geometry values and release markers are intentionally omitted until review. Example FPS is an authoring placeholder.

```json
{
  "schema_version": 1,
  "package_key": "archer",
  "source_root": "res://assets/Characters/Archer",
  "reader": "uniform_grid",
  "frame_size_px": [192, 192],
  "clips": {
    "idle_body": {"source": "Archer_Idle.png", "frames": [0, 1, 2, 3, 4, 5], "fps": 10, "loop": true},
    "move_body": {"source": "Archer_Run.png", "frames": [0, 1, 2, 3], "fps": 10, "loop": true},
    "primary_body": {"source": "Archer_Shoot.png", "frames": [0, 1, 2, 3, 4, 5, 6, 7], "fps": 10, "loop": false}
  },
  "bindings": [
    {"role": "idle", "facing": "east", "variant": "default", "clip": "idle_body"},
    {"role": "walk", "facing": "east", "variant": "default", "clip": "move_body"},
    {"role": "attack", "facing": "east", "variant": "primary", "clip": "primary_body"}
  ]
}
```

`idle_body` is a private recipe key; `idle` is the public semantic role. Orc's recipe can point its private idle clip at `Orc_Idle.png` with 100px frames. Monk's can point at `Idle.png`. None of these require changes to `CharacterAnimation`.

For an irregular source, that character's importer emits explicit frame rectangles. Mixed canvas sizes, frame durations and separate direction sheets normalize to the same exported output. Archer's `Arrow.png` is interpreted separately by its importer with its own size/anchor; it must not inherit the body's 192px grid rule. The global coordinator sees the normalized output only.

The complete export contract additionally requires reviewed body measurement, feet anchors, provenance/source hashes, all five base roles, directional coverage/fallbacks, action phase bindings, component definitions and explicit AI capability status. This incomplete example remains workbench-only.

## Shared view and preview API

The proposed shared surface is small:

```text
CharacterView.configure(definition, visual, owner_style)
CharacterView.present(character_state, presented_time)
CharacterAnimation.resolve(AnimationRequest) -> AnimationBinding
CharacterPackageBuilder.build(module_key) -> validated CharacterExports and artifacts
CharacterModuleExporter.export_character(context) -> CharacterExports
CharacterImporter.import_assets(context) -> character-local art draft
```

`CharacterView` receives state; it does not query a global current player or interpret source filenames. A preview supplies synthetic states and a fixed world ruler to this same interface. A running match supplies predicted/presented snapshots. A package needs no live host connection to preview all of its roles.

A shape fallback implements that view contract while drawing a shape. A sprite package uses the body/optional-effect composition in the architecture document. Two instances sharing a visual must have independent animation progression. Team/owner indicators remain outside source art tint so both players remain identifiable even with identical character picks.

## Build, validation and reload

Proposed commands, **not implemented yet**:

```sh
make import_character CHARACTER=archer
make preview_character CHARACTER=archer GAMEPLAY_SIZE=1
make check_character CHARACTER=archer
make build_character_catalog
```

The module builder validates the declared dependencies and complete public exports before publishing output. Publish one coherent generated generation; an invalid frame, missing source, duplicate role binding, fallback cycle, nonpositive size or missing required role leaves the last valid generation available. The harness independently gates normal selection on complete combat verification. Report the module key, file and failing export so a bad Orc importer is diagnosable without knowing Archer's layout.

Shared import helpers must not infer gameplay capability from a `Shoot`/`Heal` filename. Check role coverage against explicit enabled components/abilities instead. Run custom adapters only as local build tools, and never accept adapter code or resource paths from network clients.

For the first implementation, private configuration/importer/exporter/generated-animation edits use validated scenario relaunch. The current launcher only treats known shape `.tres` and texture edits as live visual changes; nested generated resources require explicit support. Gameplay definitions, AI profiles, size, hitboxes and ability timing rebuild the affected evidence/catalogs and restart the coordinated scenario initially. Later live art replacement must preserve instance identity, state/action progress, ground anchor and the audience timeline.

## Small implementation checkpoints

This sequence proves module isolation first, then the complete base contract. Finish and review each checkpoint before implementing the next. A partial package is never promoted merely because its animation import passed.

| Checkpoint | Bounded deliverable | Acceptance |
| --- | --- | --- |
| [4A — Contract and harness](04f-character-harness.md) — implemented | Draft five-role/export contracts, size/anchor helpers, fixed-ruler harness and admission diagnostics | Missing required roles visibly fail; 16px/32px references match at size 1 and grow by 50% at size 1.5 |
| [4B — Two custom modules](04h-archer-and-orc-modules.md) — implemented | Independent Archer/Orc imports, art roles, identity/preview metrics and explicit player_only AI status; full gameplay/state checks remain not run | Each builds with the other absent; processed pixels match original crops and recorded transforms; both render all five shared roles and neither enters selection |
| [4C — Selectable characters and movement](04i-playable-characters.md) — implemented | Per the updated request, bundle validated art, add IDs 5/6 to selection, animate predicted/received movement and show dev action labels | Real art loads without raw files/importers; players/audience show motion, blocked input idles, delayed labels respect audience history; full combat remains unverified |
| 4D — Complete base and first admission | Orc's five roles plus shared health, hurtbox, primary melee, Hurt/Dead and attack phases | Full Basic Combat v1 harness passes, including selection rejection for failing candidates; then admit Orc |
| 4E — Shared projectile extension | Archer's primary attack, projectile effect/view and delayed state/event history | Base plus projectile checks pass before admitting Archer; a second fixture uses the same system with different projectile settings |
| 4F — Further modules | Warrior's shared hurt/death presentations; then Lancer and Monk individually | Complete base plus declared extensions; Monk needs a damage attack or a separately designed support profile |

Attack/heal/guard sheets can be cataloged during asset review, but their mechanics are introduced only in the corresponding checkpoint. The proposed heal/guard contracts are extension points; their presence in this document does not authorize bundling them into the idle/walk implementation.

## Tests that demonstrate the boundary

| Proposed check | Evidence |
| --- | --- |
| `tests/character_import_check.gd` | Different naming/layout fixtures normalize to identical role coverage; missing/duplicate/out-of-bounds mappings fail |
| `tests/character_module_isolation_check.gd` | Each custom importer/exporter builds with siblings absent; undeclared dependencies, mutable export references and nondeterministic output rejected |
| `tests/character_preview_check.gd` | Measured rendered body/feet bounds, fractional sizing, mirroring, per-instance playback and separate effect layer |
| `tests/character_package_check.py` | Deterministic admitted catalog output, stable IDs, normalized AI status, unresolved dependencies and failed exports preserving the previous generation |
| `server/character_state_test.odin` | Shared state queries, interruption priority, repeated input, death and reset; no character-specific state branches |
| `server/combat_test.odin` | Same hitbox descriptor gives the same hits across character types; geometry ignores image resolution; one hit per action |
| `server/projectiles_test.odin` | Different projectile definitions use the same sweep/filters/lifetime; frame-skipping targets and owner despawn covered |
| `tests/character_multiplayer_check.gd` | Selection and same-character instances, facing/action reconstruction, live players and delayed audience including short-lived events |

These files are introduced with the feature they verify. Existing movement/camera/audience/reload checks remain regression coverage. A successful preview proves animation import, not combat authority; host tests prove rules, not rendered anchors. Keep those evidence boundaries visible at each checkpoint.
