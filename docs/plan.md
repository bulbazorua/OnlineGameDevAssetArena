# Asset Arena roadmap

The working game includes **checkpoint 3D: countdown, arena entry, and networked movement**, with three typed-terrain maps and shared player/audience views.

| Phase | Status | Result |
| --- | --- | --- |
| [0 — Architecture example](00-odin-server-godot-client.md) | Documented | Odin authority and Godot presentation explained. |
| [1 — Host connection](01-host-connection.md) | Implemented | Hello/Welcome, reconnects, and timeouts. |
| [2 — Shapes and audience](02-shapes-and-audience.md) | Implemented | Two player roles, colored shapes, and audience joining. |
| [3A — Separate responsibilities](03a-connection-session-lobby.md) | Implemented | Extracted connection/session handling and lobby UI; version 2 compatibility verified. |
| [3B — Character selection](03b-character-selection.md) | Implemented | Start with two players, choose Circle/Square/Triangle/Diamond, and confirm Ready; viewers see both picks. |
| [3C — Arena selection and terrain](03c-arena-selection.md) | Implemented | Three shared maps, typed terrain, TileMapLayer previews, tile inspection, and map-aware Ready. |
| [3D — Countdown and movement](03d-countdown-and-movement.md) | Implemented | Host-controlled 5-second countdown, selected-character spawning, cameras, predicted movement, audience snapshots, and reset/replay. |
| AI, combat, terrain effects | Later planning | Build on live character instances and the server-owned map. |

Implement and verify one checkpoint at a time. The Phase 3 document lists the proposed filenames, classes, Odin types/procedures, message layouts, and acceptance checks. The [current protocol](protocol.md) is version 5. Both Ready now starts the countdown and then enters the playable arena.
