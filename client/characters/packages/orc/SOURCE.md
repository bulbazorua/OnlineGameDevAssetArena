# Orc source and calibration

Originals: `client/assets/Characters/Orc/`. All seven PNGs match byte-for-byte, by SHA-256, the local `Tiny RPG Character Asset Pack 01 v2.0 -Free Soldier&Orc/Characters(100x100 split)/Orc/Orc with shadows/` folder under `~/CONTENT_CREATION/BulbaZorua/GameAssets/` (checked 2026-09-10). Exact hashes and matching filenames are recorded in `source_manifest.json`. This records local provenance; it does not certify redistribution terms or combat admission.

The module reads these originals without modifying or relocating them. Its own `art.json` and importer define 100×100 cells and left-to-right order. Selected strips are Idle (6), Walk (8), Hurt (4), Attack01 (6) and Death (4). `Orc.png` and `Orc_Attack02.png` are inventoried alternatives and produce no clips in this checkpoint. The primary attack uses Attack01 consistently.

Neutral body calibration uses `(44,42,13,14)` and ground anchor `(50,56)` in every full source frame. The 14px reference covers the standing body and excludes the axe, ground shadow and swing effects. This gives the same 32-world-unit reference height as Archer at gameplay size 1. Pose bobbing, axe swings and the falling death pose retain their original frame alignment. These measurements are separate from future hitboxes/hurtboxes.

The source provides a side-facing view. All eight logical facings explicitly reuse it, mirroring west, northwest and southwest. These visual fallbacks do not control future authoritative attack direction. Preview FPS is authored for inspection; combat timing remains unimplemented.

The exporter normalizes all five public roles and explicit `player_only` AI status. Passing art checks does not admit Orc into normal selection: health, actions, combat and networking checks are still not run. This folder imports no other character's configuration or code.
