# Checkpoint 4B: independent Archer and Orc modules

Status: **implemented**. Archer and Orc both pass all five art-role checks. Archer includes the user-supplied hurt/death sheets, normalized by its own importer. The subsequent [4C checkpoint](04i-playable-characters.md) makes both selectable in the movement sandbox; full combat checks remain future work.

Scope: import the existing Archer and Orc original PNGs through their own modules, calibrate their neutral body/feet, and inspect their processed output in the shared harness. Match selection, host movement integration and combat remain later checkpoints.

## Run it

```sh
make character_harness CHARACTER=orc
make character_harness CHARACTER=archer
make process_character CHARACTER=orc
make process_character CHARACTER=archer
make check_character_modules
```

Each harness command processes that character before opening its preview. Both characters now open a successful generation. The launcher prefers the last successful generation; when none exists and an attempt produced a complete staged artifact, it automatically selects **Latest processed candidate** and displays validation failures. `CANDIDATE=1` forces candidate preview even if an older successful generation exists. The same mode can be selected in the workbench. Module switching loads existing output using the selected preview mode; process a module before trying to view it. `MODULE=res://characters/packages/orc` remains available as an explicit path alternative.

Use **Processing report** to open the latest attempt's result and linked trace/logs. **Processed files** opens the actual artifact being shown. Original PNGs remain under `client/assets/Characters/{Archer,Orc}/`; staged output and reports are under `build/asset-jobs/<key>/<attempt>/`; successful art generations are under `build/processed/characters/<key>/generations/<digest>/`. These are distinct files, and each processed frame records its original file, hash and crop rectangle.

## Implementation decisions

- Modules live in `client/characters/packages/archer/` and `orc/`. Each owns `source_manifest.json`, `art.json`, `definition.json`, `importer.gd`, `exporter.gd` and `SOURCE.md`.
- `packages/registry.json` lists workbench candidates and their entry paths. It carries no frame rules and does not admit candidates into `characters.json`.
- Archer owns its original 192px strips and maps Idle/Run/Shoot to `idle`/`walk`/`attack`. Its custom importer also normalizes the larger, unevenly spaced user-supplied hurt/death sheets. Arrow is inventoried but reserved for the projectile checkpoint.
- Orc owns its 100px split strips and maps Idle/Walk/Hurt/Attack01/Death to all five roles. The combined atlas and Attack02 remain inventoried alternatives.
- Each exporter supplies identity, normalized preview size/footprint and explicit `player_only` AI status. Full gameplay components remain unverified; no invented attack/health implementation is added in this checkpoint.
- Both reuse their source view for the eight logical facings, mirroring the western directions explicitly. This is a declared art fallback, not eight-direction source artwork or a combat aiming implementation.

| Public role | Archer private clip / source | Orc private clip / source |
| --- | --- | --- |
| `idle` | `bow_rest` / Archer_Idle, 6 frames | `orc_rest` / Orc_Idle, 6 frames |
| `walk` | `bow_run` / Archer_Run, 4 frames | `orc_walk` / Orc_Walk, 8 frames |
| `hurt` | `bow_hurt` / Archer_hurt, 6 frames | `orc_hurt` / Orc_Hurt, 4 frames |
| `attack`, variant `primary` | `bow_shoot` / Archer_Shoot, 8 frames | `orc_axe` / Orc_Attack01, 6 frames |
| `death` | `bow_fall` / Archer_death, 7 frames | `orc_fall` / Orc_Death, 4 frames |

The shared viewer requests `walk`; only Archer's exporter knows that this means `bow_run`. Orc uses its own configuration shape and exporter mapping. Neither imports the other module. Shared source access performs verified reads/crops and records their provenance.

The original 11 PNGs were matched by SHA-256 to their local source packs. Archer's two additional hurt/death PNGs are inventoried separately as user-supplied sheets. The [Archer source notes](../client/characters/packages/archer/SOURCE.md), [Orc source notes](../client/characters/packages/orc/SOURCE.md) and inventories record their sources and calibration.

## Calibration

The neutral body supplies the size reference; PNG canvas, weapons, shadows and attack effects do not. Measurements verified in the rendered harness:

| Module | Native frame | Neutral body rectangle | Reference span | Foot anchor |
| --- | --- | --- | --- | --- |
| Archer | 192×192 | `(72, 64, 48, 64)` | 64px | `(96, 128)` |
| Orc | 100×100 | `(44, 42, 13, 14)` | 14px | `(50, 56)` |

At gameplay size 1, each authored body reference spans 32 world units; at 1.5, 48. Weapons, helmet ornaments, shadows and action effects may extend beyond the neutral rectangle. Preserve the authored frame alignment across clips instead of centering each crop independently. Preview FPS is an art setting, not authoritative attack timing.

Archer's new sheets are 2172×724, containing six hurt and seven death poses. Private `authored_sequences` entries specify each crop and source ground anchor. Hurt uses scale 0.3 and death 0.35 throughout their respective sequences. Crops are resized with nearest-neighbor sampling and placed on a transparent 192×192 canvas so the ground anchor agrees with `(96,128)` within half a pixel. The falling pose remains shorter than the standing body. Each frame records its original crop and versioned `resize_canvas` transform; the original PNGs remain unchanged.

## Incomplete candidate inspection

The last-successful-generation publication rule still applies. A future missing-role failure can retain a complete staged artifact for inspection. **Latest processed candidate** loads that attempt's saved artifact and verifies its digest. The launcher selects it automatically only when no successful-generation pointer exists. **Last successful generation** loads only published output. Failed extraction/compilation without a complete artifact remains unviewable with a clear report. Candidate preview never replaces `current.json` or changes selection eligibility.

Both characters pass the art checks and remain `selection_eligible: false`. The contract remains `character.basic_combat@1.0.0-draft.1`, export API `0.1.0`. Health, state lifecycle, attacks, AI backends and admission checks remain unimplemented.

## Acceptance

- Original PNG hashes match their inventories and remain unchanged.
- Each module builds with the other module and its source assets absent.
- Processed frame order, crop dimensions and source hashes match each module's authoring decisions.
- Both normalize public roles and explicit player-only status; missing roles never fall back silently.
- Actual shared CharacterView rendering verifies neutral body size, stable ground anchors, mirrored views and independent playback.
- The harness distinguishes failed candidate previews from successful processed generations.
- Existing shape/multiplayer and raw-to-processed failure checks continue to pass.

## Verification

`make check_character_modules` builds each character twice in a disposable repository containing only that module, its declared originals and shared processing code. It verifies stable digests, mappings, unchanged originals and source-to-processed pixel equality after replaying recorded transforms. Incorrect frame counts, invalid Archer ground anchors and deliberately removed hurt/death bindings fail without replacing successful output. Incomplete staged output remains readable. Finally, the test removes raw files and module code and reloads the saved successful artifact.

`tests/character_module_views_check.gd` checks every imported animation frame at gameplay sizes 1 and 1.5, facing east and west, through the shared `CharacterView`. It verifies body size, transformed ground anchors, independent instances, final-frame hold and missing-role behavior. Its graphical run additionally measures rendered alpha bounds and captures all five roles in the actual harness at 900×800 and 800×760:

```sh
godot --path client --script "$PWD/tests/character_module_views_check.gd"
```

The headless module checks and graphical checks passed on 2026-09-10 with Godot 4.6. Captures are under `build/verification/characters/modules/`; logs are `build/verification/character-modules-check.log` and `character-modules-render.log`. Automated controls and rendered measurements do not constitute physical mouse/keyboard testing or combat verification.

The full `make check` also passed: 21 Odin tests, reference contracts, asset-processing failure recovery, real-character isolation, terrain, multiplayer selection/movement, cameras, five-second audience delay, and development reload/relaunch checks. The full log is `build/verification/check-4b.log`.

The subsequent Archer hurt/death import passed `make check_character_modules check_asset_pipeline check_character_contract` and the graphical module check on 2026-09-10. Both characters pass all five art roles; all six original Archer PNG hashes remain unchanged. New evidence is in `build/verification/archer-states-final-check.log` and `archer-new-states-render.log`, with updated hurt/death captures under `build/verification/characters/modules/`. Rendered bounds use alpha at least 32/255 so faint source specks dropped by minification do not distort the silhouette measurement; byte-level verification still checks the complete processed RGBA data.

The subsequent [4C checkpoint](04i-playable-characters.md) now integrates real characters into selection and movement. Shared combat remains the next major implementation layer.
