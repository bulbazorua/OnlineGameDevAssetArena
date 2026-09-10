# Proposal: gameplay size independent of pixels

This sizing contract is used by the refined [component/animation architecture](04c-component-characters-and-animation-contract.md), [character package migration](04d-character-packages-and-migration.md) and [versioned harness](04e-character-harness-and-base-contract.md). Each character's custom importer/exporter normalizes body measurements and feet; shared gameplay components derive collision geometry independently.

Use **one gameplay unit = 32 world units**. A standard terrain cell occupies one gameplay unit. Pixels describe the source image, not the character's world size.

For characters, `gameplay_size` sets the world span of an authored neutral-body reference. Use the longest side of its body reference rectangle; exclude canvas padding, shadows, weapons and VFX. Keep that reference fixed across animations. For tiles the reference is the native tile edge; for buildings it is an explicitly reviewed architectural span such as facade width.

```text
target_span_world = gameplay_size × 32
render_scale = target_span_world / reference_span_px
```

| Source reference | Gameplay size | Render scale | Resulting reference span |
| --- | ---: | ---: | ---: |
| 16×16 body | 1 | 2 | 32 world units |
| 32×32 body | 1 | 1 | 32 world units |
| 16×16 body | 1.5 | 3 | 48 world units |
| 32×32 body | 1.5 | 1.5 | 48 world units |
| 64×64 Tiny Swords terrain tile | 1 | 0.5 | 32 world units |
| 320px castle facade reference | 5 | 0.5 | 160 world units / five cells |

This gives the requested behavior: a 16×16 and a 32×32 character at size 1 occupy the same reference span, while size 1.5 is 50% larger. A nonsquare character keeps its aspect ratio; equal size means equal reference span, not stretching every character into a square.

The helper `client/presentation/asset_scale.gd` is introduced for tiles/buildings in the terrain milestone. Character fields, shared collision derivation, the size preview and animation integration remain **proposed checkpoint 4A/4B work**.

## Padding example

An idle frame is 192×192, but the reviewed body span is 80px. At `gameplay_size = 1`, use `32 / 80 = 0.4` as the scale. The frame canvas becomes 76.8 world units, while the body is 32 world units. If an attack frame is 320×320 with the same body span and extra sword reach, the body remains 32 units; its weapon can extend farther without rescaling the character.

Do not automatically fit each animation frame to the footprint or selection card. That would make breathing, weapon swings, and transparent padding change apparent size. Calibrate a body reference once and reuse it.

## World anchor and scene scale

```text
CharacterView.position = authoritative/predicted ground position
    BodyVisual.scale = render_scale
    BodyVisual.offset = -foot_anchor_px
    OwnerRing = gameplay footprint in world units
    DebugBodyBounds = authored reference transformed into world units
```

The parent gameplay node stays at scale 1. Scale the art child only; derive collision separately from shared definitions. This prevents scaling the same movement/footprint twice. Mirror art around the ground anchor with an explicit offset adjustment so left/right flips do not slide feet. Sort characters and buildings by ground position, not texture center or roof height.

Fixed player-camera zoom remains a camera concern. A selection card may fit a character into its UI rectangle, but the size preview must show a fixed world ruler so differences remain visible.

## Gameplay footprint

Proposed shared character fields:

```json
{
  "id": 5,
  "key": "warrior",
  "display_name": "Warrior",
  "gameplay_size": 1.0,
  "footprint_radius_units": 0.375
}
```

This is a **future schema example**, not an assigned character ID or a change to today's catalog. Derive `radius_world = footprint_radius_units × gameplay_size × 32` in both Odin and Godot. The example produces radius 12 at size 1 and radius 18 at size 1.5. Animation frame dimensions never enter collision or attack calculations.

The footprint profile remains independent of the visual reference: a tall humanoid and a wide quadruped need different ground footprints even when their reference spans are equal. Start with the existing circular solver. Later profiles can add a capsule/rectangle/polygon only when both host and prediction support it. Combat hitboxes and attack reach are separate ability data; changing visual size must not silently derive them from opaque pixels.

Preserve current shape behavior during migration. Current shapes use radius 12 directly and do not yet consume `gameplay_size`. A schema migration should retain that effective radius while adding an explicit reference measurement. Reject conflicting old/new size fields, nonfinite/zero/negative values, and sizes without valid spawn clearance.

Large characters may no longer fit a narrow stair or the current spawn. Check the derived radius against the selected map before Ready/spawn, and show a useful reason instead of clipping or teleporting. Movement speed remains independent of size unless a later character definition explicitly changes it.

## Tiles and buildings

The existing map `tile_size` is already measured in world units. Both a 16px atlas layer scaled by 2 and a 64px layer scaled by 0.5 place their tile centers on the same 32-unit grid. Preserve source PNGs and sample their native regions; no destructive image resize is needed.

Building art uses the same conversion formula and an authored ground anchor. Its collision footprint is expressed in map cells and baked into the shared terrain rows. Visual roof overhang is allowed. A building size edit must also update/validate its authored footprint; the tiny terrain slice deliberately checks those two representations together.

Do not expose an unrelated per-tile scale that changes how far a cell looks like it extends without changing its world dimensions. Changing the physical grid size is a shared map/content change; changing native tile resolution is presentation only.

## Verification to implement with character sizing

Compare independent 16px and 32px reference fixtures at size 1 and 1.5 using measured rendered bounds, not just the scale formula. Include padded canvases and attack frames with larger weapon bounds, horizontal flips, stable feet, fractional scaling, and two instances sharing one visual. Check host/client radius equivalence and a large character blocked by a narrow gap. Nearest filtering preserves source pixel edges; fractional scale/downscaling cannot make different source pixel densities stylistically identical.
