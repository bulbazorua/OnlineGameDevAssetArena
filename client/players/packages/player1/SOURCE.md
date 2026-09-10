# Player1 source and calibration

Player1 is the trainer/player art package. Original user-supplied PNGs remain in
`client/assets/Characters/Player1/`. `source_manifest.json` inventories their
SHA-256 hashes. Processing never overwrites them.

The 2172×724 RGBA sheets are ordered left to right. The replacement walk sheet
contains eight poses; each other sheet contains six. The sheets
have uneven spacing and faint alpha specks outside the visible poses. `art.json`
records individually reviewed crop rectangles and ground positions. In particular,
the fourth advice pose extends past a regular 362px cell; using an even grid would
cut its finger into the next frame.

The private importer extracts those rectangles, resizes them with nearest sampling
at 0.25 source scale (rounded to whole pixels), then places them on transparent
192×192 canvases. Every frame records its source hash, crop, resize dimensions,
offset, source ground and target ground. Crops include the visible pose and its
attached effects; faint distant alpha residue outside the authored crops is omitted.
There is no automatic background removal, generated art or inferred in-between frame.

The neutral body's reference is 79px, its body rectangle is `[73,65,46,79]`, and
the common ground anchor is `[96,144]`. Gameplay size 1 renders that reference at
32 world units; size 1.5 renders at 48. One scale applies to the entire animation
set. Crouching, extended arms and the airborne cheer pose retain their differences;
the importer does not resize each pose to the same bounding box. Cheer frame 3
keeps its raised feet above the strip's ground line.

`exporter.gd` owns the source-to-contract mapping. `player_advice.png` becomes
`advise`; every other sheet's suffix becomes the corresponding canonical state.
Private `trainer_*` clip names do not escape into gameplay state identifiers.

These are front/three-quarter poses, not eight-direction sprite sets. Each logical
facing is mapped explicitly to the supplied clip; west, southwest and northwest
mirror it. No back-view animation is claimed. A future Player2 can provide true
facing-specific clips through its own importer/exporter, under the same contract.

The walk sheet was replaced on 2026-09-10. All eight new poses use individually
authored crops and ground anchors at source y=549, retaining the common 0.25
import scale and looping at 8 FPS. The source inventory records the replaced hash.
