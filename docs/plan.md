# Asset Arena roadmap

The working game now includes **checkpoint 4C: selectable Archer and Orc**, using independently processed art, calibrated bodies, idle/walk animation and development action labels. All five asset folders were audited; Lancer, Warrior and Monk still lack required animations. Gameplay combat states, damage, projectiles and AI remain subsequent checkpoints. The default five-second audience delay remains.

| Phase | Status | Result |
| --- | --- | --- |
| [0 — Architecture example](00-odin-server-godot-client.md) | Documented | Odin authority and Godot presentation explained. |
| [1 — Host connection](01-host-connection.md) | Implemented | Hello/Welcome, reconnects, and timeouts. |
| [2 — Shapes and audience](02-shapes-and-audience.md) | Implemented | Two player roles, colored shapes, and audience joining. |
| [3A — Separate responsibilities](03a-connection-session-lobby.md) | Implemented | Extracted connection/session handling and lobby UI; version 2 compatibility verified. |
| [3B — Character selection](03b-character-selection.md) | Implemented | Start with two players, choose Circle/Square/Triangle/Diamond, and confirm Ready; viewers see both picks. |
| [3C — Arena selection and terrain](03c-arena-selection.md) | Implemented | Three shared maps, typed terrain, TileMapLayer previews, tile inspection, and map-aware Ready. |
| [3D — Countdown and movement](03d-countdown-and-movement.md) | Implemented | Host-controlled 5-second countdown, selected-character spawning, cameras, predicted movement, audience snapshots, and reset/replay. |
| [3E — Development overlay](03e-dev-overlay.md) | Implemented | Opt-in FPS and host ping in every player/audience window. |
| [3F — Arena launcher and reload](03f-dev-workflow.md) | Implemented | Variable scenario launcher; live visual reload and validated automatic relaunch for code/data edits. |
| [3G — Larger land arenas](03g-land-arenas.md) | Implemented | Six times the map area, grassland layouts, CC0 terrain art, stairs/elevation rules, and follow/overview cameras. |
| [3H — Player and audience cameras](03h-player-and-audience-cameras.md) | Implemented | Centered fighter cameras at fixed zoom; independent audience pan/zoom and optional follow. |
| [3I — Audience delay](03i-audience-delay.md) | Implemented | Configurable host-enforced spectator history, delayed joins/resets, and live player state. |
| [3J — Tiny Swords Village](03j-tiny-swords-village.md) | Implemented | Fourth map, local asset importer, 12 buildings, shared collision footprints, and native-resolution-independent tile/prop scaling. |
| [4 — Characters and state machines](04-character-architecture-proposal.md) | Proposed | Separate definitions, runtime state and art; phased filenames, host authority, delayed-audience animation and acceptance checks. |
| [4 — Component and animation contracts](04c-component-characters-and-animation-contract.md) | Refined proposal | Each character is an isolated module with a required custom importer/exporter for shared states/art, gameplay components and AI. |
| [4 — Package layout and migration](04d-character-packages-and-migration.md) | Current implementation proposal | Exact module files, five-character inventory, Archer/Orc isolation proofs and phased combat admission. |
| [4 — Versioned character harness](04e-character-harness-and-base-contract.md) | Proposed admission contract | Basic Combat v1 requires idle, walk, hurt, attack and death; only fully verified modules enter normal selection. |
| [4A — Contract and art harness](04f-character-harness.md) | Implemented | Draft five-role contract, required custom importer/exporter interfaces, independent synthetic modules, missing-role diagnostics and verified 16px/32px body sizing. No combat or selection admission. |
| [4A.1 — Raw and processed assets](04g-character-asset-processing.md) | Implemented | Preserved original PNGs, independent processing, saved generations, per-frame provenance and failed-attempt reports; harness loads processed output. |
| [4B — Archer and Orc modules](04h-archer-and-orc-modules.md) | Implemented | Custom isolated imports, five canonical roles and calibrated bodies/feet. Archer's additional hurt/death sheets have recorded crop/resize/placement transforms. Runtime integration follows in 4C. |
| [4C — Selectable characters and movement](04i-playable-characters.md) | Implemented | Archer/Orc join the roster as IDs 5/6, load processed runtime bundles, animate idle/walk, and show dev-only action text through the audience's delayed view. Full combat certification remains future work. |
| [4 — Gameplay size](04b-gameplay-size-proposal.md) | Body scaling proven in 4A | Equal body reference size and a fixed world ruler; authoritative character geometry integration follows later. |
| [4 — Asset pipeline](04a-asset-pipeline-proposal.md) | Import foundation implemented; later integration proposed | Isolated imports and processed previews are in place; isolated movement, shared melee/projectiles and admission follow. |
| AI, combat, terrain effects | Later planning | Build on live character instances and the server-owned map. |

Implement and verify one checkpoint at a time. The Phase 3 document lists the proposed filenames, classes, Odin types/procedures, message layouts, and acceptance checks. The [current protocol](protocol.md) is version 6. Both Ready now starts the countdown and then enters the playable arena.
