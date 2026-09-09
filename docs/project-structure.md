# Project structure: one repository, two programs

Status: [Checkpoint 3D: countdown and movement](03d-countdown-and-movement.md) is implemented, including shared countdown, selected characters, cameras, and networked movement. [Phase 1: Host connection](01-host-connection.md) covers build requirements.

The original checkpoint plan is in [the character-selection and top-down-arena plan](03-selection-and-topdown-arena-plan.md). The tree below describes the existing code.

Keep both programs in **OnlineGameDevAssetArena**, in sibling folders:

- **`client/`** is the Godot project that players run.
- **`server/`** is the Odin program that hosts the game.

They share one Git history, but build and run independently. The server is a separate executable and process. During local development it can run on the same computer as the clients; for Internet play it can run on its own host machine.

## Start with this small layout

```text
OnlineGameDevAssetArena/
├── client/                         Godot project
│   ├── project.godot               Project settings and startup scene
│   ├── main.tscn                   Persistent connection, selection screens, playable arena
│   ├── main.gd                     AppController: content, screen routing, signals, CLI
│   ├── network/
│   │   ├── game_connection.gd      ENet lifecycle and decoded state
│   │   └── protocol.gd             Version 5 packet codec
│   ├── session/
│   │   └── session_snapshot.gd     Decoded session, countdown, tick, and live characters
│   ├── ui/
│   │   ├── lobby_screen.gd         Display state and emit user intent
│   │   ├── lobby_screen.tscn       Connection controls, roster, and Start
│   │   ├── character_select_screen.gd
│   │   ├── character_select_screen.tscn  Cards, both picks, Ready, audience
│   │   ├── arena_select_screen.gd / .tscn  Shared map choice and terrain inspection
│   │   └── arena_preview.gd        Fit a world map to the screen
│   ├── content/
│   │   ├── game_content.gd         Validate catalog, visuals, and fingerprint
│   │   ├── arena_catalog.gd        Terrain/arena definitions and cell queries
│   │   └── data/                   characters.json, terrains.json, arenas.json
│   ├── world/
│   │   ├── arena_world.gd / .tscn  TileMapLayer world and spawn markers
│   │   ├── game_arena.gd / .tscn  Countdown, camera, input, prediction, interpolation
│   │   ├── character_movement.gd  Shared movement rules for local prediction
│   │   └── terrain_tileset.gd      Terrain-to-atlas mapping and custom tile data
│   ├── assets/                     Kenney atlases, original licenses, provenance
│   ├── characters/
│   │   ├── character_visual.gd     Presentation resource type
│   │   ├── visuals/*.tres          Four placeholder resources
│   │   ├── character_view.gd       Draw an owner-colored placeholder
│   │   └── character_view.tscn
│   └── arena.gd                    Draw colored player shapes
├── server/                         Odin server package
│   ├── main.odin                   Options, lifetime, and fixed 60 Hz loop
│   ├── network.odin                ENet lifecycle and session updates
│   ├── protocol.odin               Version 5 packet codec
│   ├── session.odin                Membership, phase, picks, Ready, reset
│   ├── characters.odin             Character_Definition
│   ├── movement.odin               Live Character, countdown/spawn, fixed movement
│   ├── movement_test.odin          Timing, input authority, collision, wire fixtures
│   ├── content.odin                Catalog validation, lookup, fingerprint
│   ├── content_test.odin           Invalid data and shared digest fixtures
│   ├── arena.odin                  Terrain/arena definitions and coordinate queries
│   ├── arena_test.odin             Map validation, selection rules and wire fixtures
│   └── session_test.odin           Session rules and wire-contract checks
├── docs/
│   ├── 00-odin-server-godot-client.md
│   ├── 01-host-connection.md       Run and verify the first phase
│   ├── 02-shapes-and-audience.md   Run and verify shapes and viewers
│   ├── 03-selection-and-topdown-arena-plan.md
│   ├── 03a-connection-session-lobby.md
│   ├── 03b-character-selection.md
│   ├── 03c-arena-selection.md
│   ├── 03d-countdown-and-movement.md
│   ├── project-structure.md        This document
│   ├── protocol.md                 Version 5 messages and content contract
│   └── plan.md                     Roadmap and implementation status
├── tools/
│   └── build_enet.py               Build the pinned Linux dependency locally
├── tests/
│   ├── host_check.gd               Shared isolated-host test lifecycle
│   ├── connection_check.gd         Membership, reconnect, malformed packets, timeouts
│   ├── content_check.gd            Godot catalog/visual and wire/digest checks
│   ├── selection_check.gd          Character selection and audience flow
│   ├── arena_content_check.gd      Cell metadata, coordinates and content fixtures
│   ├── arena_selection_check.gd    Shared map choice, spectators and Ready resets
│   ├── movement_check.gd           Countdown, cameras, prediction, live movement/reset
│   └── fixtures/                   Independent cross-language content fixtures
├── AGENTS.md                       Repository guidance
├── Makefile                        Commands run from the repository root
├── .gitignore                      Exclude generated output
└── build/                          Generated executables and exports
```

This tree shows the current source layout. Godot's source metadata files also live under `client/`; generated caches and build output are ignored.

## The Godot side

Open **`client/project.godot`** in Godot. The `client/` directory is the Godot project root. Downloaded tile sprites live under `client/assets/` so they belong to the project's import and export workflow. Godot imports assets from within its project folder. [Godot project organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)

`main.tscn` owns a persistent `GameConnection`, `LobbyScreen`, `CharacterSelectScreen`, `ArenaSelectScreen`, and `GameArena`. `main.gd` loads `GameContent`, connects signals, applies CLI options, and routes screens according to host state. `GameProtocol` decodes full `SessionSnapshot` values. `CharacterView` draws the catalog-backed selection previews; `arena.gd` still draws the lobby roster. The network node continues operating independently of the visible screen.

`GameArena` owns its Camera2D, countdown/HUD, character views, input, local prediction, and remote interpolation. `ArenaWorld` renders tiles independently of movement. Player 1 and Player 2 run two copies of the same client, with identities assigned by the server.

## The Odin side

`server/main.odin` owns startup, network polling, and the fixed 60 Hz loop. `network.odin` handles connections and calls the rules in `session.odin`; `protocol.odin` owns packet encoding. Two fighter slots are independent of audience connections. `content.odin` validates shared character, terrain, and arena catalogs before listening. All joined clients receive the full membership and selection state.

`movement.odin` now owns runtime characters, the countdown, spawning, and authoritative collision/movement. Future character AI and combat also belong on the host. Add focused files as those responsibilities appear. Odin organizes packages by directory, so several `.odin` files in one package can later share declarations. [Odin packages](https://odin-lang.org/docs/overview/#packages)

The server connects to clients through network messages. Its simulation code owns the accepted game state, as described in the [message-flow example](00-odin-server-godot-client.md).

## What the two programs share

Their shared agreement lives in **`docs/protocol.md`**: message names, fields, encoding, and protocol version. The current phase implements reliable lifecycle messages on channel 0 and sequenced unreliable Input/WorldState on channel 1.

Godot code and Odin code each implement that agreement in their own language. For example, Odin writes a Welcome message containing a player ID; GDScript reads it and displays that ID. Keeping both sides in one repository makes it easy to update the implementations and their contract together.

Both programs read the same character, terrain, and arena catalogs under `client/content/data/`; character ID 3 means Triangle on both sides. The client maps that ID to a `CharacterVisual` resource. Gameplay definitions are shared; presentation resources stay with the client. The Hello fingerprint detects different catalog bytes before joining.

## Building and running

The root `Makefile` provides the entry point for both programs:

| Command | Purpose |
| --- | --- |
| `make run_server` | Build and start the Odin server |
| `make run_client` | Start the Godot client |
| `make run_audience` | Start the Godot client as a viewer |
| `make check_movement` | Check countdown, live movement, cameras, and replay |
| `make check_connection` | Run the local connection integration check |
| `make check_session` | Check Odin session/content rules and version 5 bytes |
| `make check_content` | Verify content readers, visuals, and digest/wire fixtures |
| `make check_selection` | Exercise selection, Ready, audience, and reset |
| `make check_arena_content` | Check map cells, terrain metadata, and coordinates |
| `make check_arena_selection` | Check map choice and Ready invalidation |
| `make check` | Run all current checks |

Run these targets from the repository root. The first server build also downloads and compiles its pinned ENet dependency under `build/deps/`.

In separate terminals, run one server and two clients. Both can start selection once connected; additional clients join as viewers and see the same picks and Ready states.

Later, deploy the server executable and required server data to the host. Distribute the exported Godot game and its resources to players. Sharing a source repository does not require distributing or deploying both programs together.

Keep generated output in `build/` and ignore it in Git. Also ignore the Godot cache at `client/.godot/`, while versioning the client source, scenes, and source assets. [Godot version-control guidance](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html)

## Current checkpoint boundary

Both players can choose characters and a shared map, then press Ready. The host runs **5, 4, 3, 2, 1** and spawns both selected characters. Every client has a camera that fits the arena; fighters move with WASD/arrows and audience sees their positions. Either fighter can return the session to Lobby. Combat, AI, and terrain bonuses remain later phases.
