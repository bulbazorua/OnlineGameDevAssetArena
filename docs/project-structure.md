# Project structure: one repository, two programs

Status: [Arena trainers and summoning](05a-trainers-and-summoning.md) adds trainer movement and a host-timed summon effect, with separate trainer/gladiator entities. [Player1 trainer harness](05-player-harness.md) adds a separate eight-state player art contract, importer, registry and preview scene. [Checkpoint 4C: selectable characters](04i-playable-characters.md) adds Archer/Orc to selection and the arena with processed runtime art, idle/walk playback and development action labels. [Checkpoint 3J: Tiny Swords Village](03j-tiny-swords-village.md) remains the latest map checkpoint. Shared combat follows later. [Phase 1: Host connection](01-host-connection.md) covers build requirements.

[Checkpoint 4A.1](04g-character-asset-processing.md) adds original fixture PNGs under `asset_sources/`, immutable processing attempts under `build/asset-jobs/`, and saved artifacts under `build/processed/characters/`. The harness consumes processed artifacts; source interpretation runs in a separate processing worker.

The original checkpoint plan is in [the character-selection and top-down-arena plan](03-selection-and-topdown-arena-plan.md). The tree below describes the existing code.

For the complete character architecture, use the [refined architecture](04c-component-characters-and-animation-contract.md), [future package layout](04d-character-packages-and-migration.md) and [versioned harness/admission contract](04e-character-harness-and-base-contract.md). The tree below includes only implemented code; shared interfaces, synthetic fixtures and Archer/Orc modules cover the art foundation, while full gameplay/AI exports and admission remain planned.

Keep both programs in **OnlineGameDevAssetArena**, in sibling folders:

- **`client/`** is the Godot project that players run.
- **`server/`** is the Odin program that hosts the game.

They share one Git history, but build and run independently. The server is a separate executable and process. During local development it can run on the same computer as the clients; for Internet play it can run on its own host machine.

## Start with this small layout

```text
OnlineGameDevAssetArena/
├── asset_sources/characters/       Original reference PNGs, outside the Godot project
├── client/                         Godot project
│   ├── project.godot               Project settings and startup scene
│   ├── main.tscn                   Persistent connection, selection screens, playable arena
│   ├── main.gd                     AppController: content, screen routing, signals, CLI
│   ├── network/
│   │   ├── game_connection.gd      ENet lifecycle and decoded state
│   │   └── protocol.gd             Version 9 packet codec
│   ├── session/
│   │   └── session_snapshot.gd     Decoded session, countdown, tick, and live characters
│   ├── dev/
│   │   ├── collision_geometry.gd   Debug geometry from shared blocked cells, height rules and map bounds
│   │   ├── collision_overlay.gd    Filtered world outlines and displayed trainer/character footprints
│   │   ├── reload_controller.gd    Local visual reload and launcher acknowledgments
│   │   ├── character_harness.gd / .tscn  Isolated art workbench and diagnostics
│   │   ├── player_harness.gd / .tscn  Trainer workbench with all eight required states
│   │   ├── character_harness_stage.gd   Fixed grid and body/feet overlays
│   │   ├── process_character_assets.gd  Isolated artifact-processing worker
│   │   ├── fixtures/characters/{reference16,reference32}/  Independent importer/exporter fixtures
│   │   ├── validate_project.gd     Validate a staged client before publication
│   │   └── ai/
│   │       ├── ai_debug_window.gd / .tscn  Separate per-creature native debugger
│   │       ├── trace_reader.gd     Bounded, validated live and journal replay input
│   │       ├── trace_loader.gd / trace_timeline.gd  Background parsing and visible-row log rendering
│   │       ├── decision_graph.gd / trace_palette.gd  Downward graph and shared status styling
│   │       ├── replay_window.gd / .tscn  Recorded-match QA controls and synchronized AI panels
│   │       ├── replay_store.gd / replay_reader.gd  Background bounded index and frame validation
│   │       ├── replay_stage.gd     Arena and entity poses at the selected recorded tick
│   │       └── spatial_trace.gd    Recorded self/candidate/intent/result geometry
│   ├── ui/
│   │   ├── lobby_screen.gd         Display state and emit user intent
│   │   ├── lobby_screen.tscn       Connection controls, roster, and Start
│   │   ├── character_select_screen.gd
│   │   ├── character_select_screen.tscn  Cards, both picks, Ready, audience
│   │   ├── arena_select_screen.gd / .tscn  Shared map choice and terrain inspection
│   │   ├── debug_overlay.gd / .tscn  Opt-in development FPS/ping panel
│   │   └── arena_preview.gd        Fit a world map to the screen
│   ├── content/
│   │   ├── game_content.gd         Validate catalog, visuals, and fingerprint
│   │   ├── arena_catalog.gd        Terrain/arena definitions and cell queries
│   │   ├── arena_presentation.gd   ArenaPresentation: validate theme and grounded props
│   │   ├── character_contract.gd   Draft export/role validation; no admission certification
│   │   ├── contracts/character_basic_combat/1.0.0-draft.1.json
│   │   ├── contracts/player_trainer/1.0.0-draft.1.json
│   │   ├── presentation/arenas/    Client-only Tiny Swords theme and building measurements
│   │   └── data/                   characters.json, terrains.json, arenas.json
│   ├── presentation/
│   │   └── asset_scale.gd          AssetScale: source reference to gameplay/world size
│   ├── world/
│   │   ├── arena_world.gd / .tscn  TileMapLayer world and spawn markers
│   │   ├── game_arena.gd / .tscn  Countdown, camera, input, prediction, interpolation
│   │   ├── arena_camera.gd       Fixed fighter camera and independent audience pan/zoom
│   │   ├── character_movement.gd  Shared movement rules for local prediction
│   │   ├── tiny_swords_tileset.gd  64px terrain theme and cliff/shore adjacency
│   │   └── terrain_tileset.gd      Terrain-to-atlas mapping and custom tile data
│   ├── assets/                     Ninja Adventure/Kenney plus locally imported Tiny Swords
│   ├── players/packages/
│   │   ├── registry.json           Separate trainer workbench choices
│   │   └── player1/                Private importer/exporter, calibration and source inventory
│   ├── characters/
│   │   ├── character_animator.gd   Per-instance motion action, facing and clip clock
│   │   ├── character_visual.gd     Presentation resource type
│   │   ├── character_animation_set.gd  Normalized clips, bindings and art measurements
│   │   ├── character_artifact.gd    Persist/reload processed art with frame provenance
│   │   ├── import/character_exports.gd  Public module envelope
│   │   ├── import/character_importer.gd  Required custom importer interface
│   │   ├── import/character_asset_sources.gd  Declared inputs, frame extraction and trace
│   │   ├── import/character_module_exporter.gd  Required custom exporter interface
│   │   ├── import/character_package_builder.gd  Invoke a module and inspect its output
│   │   ├── packages/registry.json   Workbench candidates; separate from the match roster
│   │   ├── packages/{archer,orc}/   Each owns importer.gd, exporter.gd, art.json,
│   │   │                           definition.json, source_manifest.json and SOURCE.md
│   │   ├── visuals/*.tres          Four placeholder resources
│   │   ├── character_view.gd       Shape and normalized sprite-art presentation
│   │   └── character_view.tscn
│   └── arena.gd                    Draw colored player shapes
├── server/                         Odin server package
│   ├── main.odin                   Options, lifetime, and fixed 60 Hz loop
│   ├── dev_scenario.odin           Debug-only canonical scenario and automatic entry
│   ├── dev_scenario_test.odin      All characters/maps, countdowns, and one-shot entry
│   ├── audience.odin               Shared bounded spectator history and timed release
│   ├── audience_test.odin          Delay timing, copies, ring bounds, Welcome bytes
│   ├── network.odin                ENet lifecycle and session updates
│   ├── ai/                         Pure per-character decisions, wander tactic and PRNG
│   │   └── trace.odin              Optional bounded branch events with thread/timing data
│   ├── brain_workers.odin          Two dedicated threads and copied private mailboxes
│   ├── dev_ai_debug.odin           Bounded queue, rotating journals, atomic snapshots
│   ├── brain_workers_test.odin     Serial equivalence, isolation, rotation and debug gates
│   ├── simulation.odin             Public session plus private battle owner
│   ├── battle.odin                 Context preparation, AI intents and execution adapter
│   ├── character_actions.odin      Shared voluntary action resolver and locomotion
│   ├── protocol.odin               Version 9 packet codec
│   ├── session.odin                Membership, phase, picks, Ready, reset
│   ├── characters.odin             Character_Definition
│   ├── movement.odin               Live Character, countdown/spawn, fixed movement
│   ├── movement_test.odin          Timing, input authority, collision, wire fixtures
│   ├── content.odin                Catalog validation, lookup, fingerprint
│   ├── content_test.odin           Invalid data and shared digest fixtures
│   ├── arena.odin                  Terrain/arena definitions and coordinate queries
│   ├── arena_test.odin             Map validation, selection rules and wire fixtures
│   ├── elevation_test.odin         Connected land, height validation and stair rules
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
│   ├── 03e-dev-overlay.md
│   ├── 03f-dev-workflow.md         Working launcher, reload policy, and commands
│   ├── 03f-dev-workflow-plan.md    Original design and future reload checkpoints
│   ├── 03g-land-arenas.md          Larger maps, elevation, art, and camera controls
│   ├── 03h-player-and-audience-cameras.md  Role-specific camera behavior and checks
│   ├── 03i-audience-delay.md       Configuration, delayed timeline and verification
│   ├── 03j-tiny-swords-village.md  Local import, buildings, sizing and verification
│   ├── 04-character-architecture-proposal.md  Future character/FSM checkpoints and files
│   ├── 04a-asset-pipeline-proposal.md  Reviewed manifests, animation import and preview
│   ├── 04b-gameplay-size-proposal.md  Pixel-independent body size and gameplay footprint
│   ├── 04c-component-characters-and-animation-contract.md  Independent import and shared gameplay roles
│   ├── 04d-character-packages-and-migration.md  Proposed package files and staged roster migration
│   ├── 04e-character-harness-and-base-contract.md  Five-role base, versioning and selection admission
│   ├── 04f-character-harness.md    Implemented 4A workbench, draft contract, commands and checks
│   ├── 04g-character-asset-processing.md  Raw/processed storage, job history and failures
│   ├── 04h-archer-and-orc-modules.md  Independent real-art modules, calibration and checks
│   ├── 04i-playable-characters.md  Runtime bundles, selectable art, motion labels and asset audit
│   ├── 05-player-harness.md        Trainer contract, Player1 processing and harness
│   ├── 06c-senses-and-ai-debug-windows-plan.md  Pending vision and later sense roadmap
│   ├── 06d-ai-debugger-harness.md   Implemented thread/trace contract, debugger and evidence
│   ├── 06e-qa-replay-and-trace-browsing.md  Performance, playback contract, QA and re-simulation plan
│   ├── log-cleanup.md              Daily retention, active-run protection and installed cron
│   ├── project-structure.md        This document
│   ├── protocol.md                 Version 9 messages and content contract
│   └── plan.md                     Roadmap and implementation status
├── tools/
│   ├── process_character_assets.py  Source/code snapshots, processing reports and publication
│   ├── prepare_characters.py       Prepare cached runtime art under client/generated/characters/
│   ├── dev_session.py              Isolated host/clients, validation, file watch, cleanup
│   ├── open_replay.py              Open the latest or selected recording with compatible resources
│   ├── purge_logs.py               Preview/delete expired generated logs; suitable for cron
│   ├── build_arena_maps.py         Explicit authoring recipes for the land arenas
│   ├── import_tiny_swords.py       Validate and install the local licensed art subset
│   └── build_enet.py               Build the pinned Linux dependency locally
├── tests/
│   ├── dev_workflow_check.py       Real processes, saves, reloads, failures, cleanup
│   ├── dev_client_driver.gd        Development-check input and render capture
│   ├── ai_debugger_check.py        Real workers, inspector lifecycle, replay and native windows
│   ├── ai_debugger_driver.gd       Test-only controls and actual inspector render capture
│   ├── ai_trace_check.gd           Trace identity, bounds, ancestry and journal validation
│   ├── replay_check.gd             Real recorded movement, synchronized seek/pause, graph and file checks
│   ├── log_cleanup_check.py        Expiry, deletion, active/pinned/source and symlink preservation
│   ├── land_movement_check.gd      Real host/client stair traversal and camera switches
│   ├── land_arena_render.gd        Whole-map and selection-layout render checks
│   ├── tiny_swords_check.gd        Networked building collision, theme switching and scale
│   ├── audience_delay_check.gd     Packet-level timing, delayed joins/resets and bypass checks
│   ├── camera_check.gd           Independent viewports, input, centering and captures
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

`GameArena` owns the countdown/HUD, character views, input, local prediction, and remote interpolation. Its `ArenaCamera` child owns the fighter camera lock and audience pan/zoom/follow controls. Camera settings remain local to each client. `ArenaWorld` renders tiles independently of movement, including terrain/elevation metadata and a grass underlay. Player 1 and Player 2 run two copies of the same client, with identities assigned by the server.

## The Odin side

`server/main.odin` owns startup, network polling, and the fixed 60 Hz loop. `network.odin` handles connections and calls the rules in `session.odin`; `protocol.odin` owns packet encoding. Two fighter slots are independent of audience connections. `content.odin` validates shared character, terrain, and arena catalogs before listening. Players receive live membership/selection state; audience receives historical state through `Audience_Stream`, at the configured delay.

`movement.odin` owns runtime characters, the countdown, spawning, and authoritative collision/movement. `Simulation` owns private `Battle_Runtime` alongside the public session. `brain_workers.odin` runs each creature's AI on its own thread with copied input/state; the host applies returned intents through `character_actions.odin`. `dev_ai_debug.odin` exports optional private traces on a separate writer thread. Odin organizes packages by directory, so several `.odin` files in one package share declarations. [Odin packages](https://odin-lang.org/docs/overview/#packages)

The server connects to clients through network messages. Its simulation code owns the accepted game state, as described in the [message-flow example](00-odin-server-godot-client.md).

## What the two programs share

Their shared agreement lives in **`docs/protocol.md`**: message names, fields, encoding, and protocol version. The current phase implements reliable lifecycle messages on channel 0 and sequenced unreliable Input/WorldState on channel 1.

Godot code and Odin code each implement that agreement in their own language. For example, Odin writes a Welcome message containing a player ID; GDScript reads it and displays that ID. Keeping both sides in one repository makes it easy to update the implementations and their contract together.

Both programs read the same character, terrain, and arena catalogs under `client/content/data/`; character ID 3 means Triangle on both sides. The client maps that ID to a `CharacterVisual` resource. Gameplay definitions are shared; presentation resources stay with the client. The Hello fingerprint detects different catalog bytes before joining.

## Building and running

The root `Makefile` provides the entry point for both programs:

| Command | Purpose |
| --- | --- |
| `make prepare_players` | Process and bundle Player1 for arena clients |
| `make check_trainers` | Verify trainer authority, summon timing, delayed audience and cancellation |
| `make player_harness PLAYER=player1` | Process and preview all eight required trainer states |
| `make process_player PLAYER=player1` | Publish validated player art under build/processed/players |
| `make check_player_harness` | Check isolated player imports, required roles and preview controls |
| `make character_harness` | Open the isolated character art workbench |
| `make character_harness CHARACTER=orc` | Process and preview Orc's five art roles |
| `make character_harness CHARACTER=archer` | Process and preview Archer's five art roles, including normalized hurt/death sheets |
| `make check_character_modules` | Check isolated real-art processing, source pixels and harness behavior |
| `make prepare_characters` | Prepare validated runtime art bundles for the Godot client |
| `make check_playable_characters` | Verify runtime bundles and networked animated characters/action labels |
| `make process_character MODULE=res://dev/fixtures/characters/reference16` | Process one module and print its report/output paths |
| `make check_asset_pipeline` | Check original preservation, deterministic output, provenance and failed processing |
| `make check_character_contract` | Check required roles, invalid exports, sizing and independent fixture modules |
| `make import_tiny_swords` | Install the reviewed terrain/building art from the local source pack |
| `make dev_arena ARENA=tiny_swords_village AUDIENCE=1` | Launch the new village with two shapes and a delayed audience |
| `make check_tiny_swords` | Verify installed assets, normalized sizing and networked building collision |
| `make dev_arena P1=triangle P2=diamond ARENA=sandbar AUDIENCE=1` | Launch directly into a watched development scenario |
| `make check_dev` | Check launcher, live visuals, automatic code/data relaunch, and cleanup |
| `make ai_debugger P1=archer P2=orc` | Launch the arena and two separate AI tree/timeline/replay inspectors |
| `make check_ai_debugger` | Check real dedicated workers, bounded logs, inspector replay/lifecycle and release export gate |
| `make replay [REPLAY=/path/to/match.replay.jsonl]` | Open recorded match QA with pause/play, seeking, speed and both AI traces |
| `make purge_logs` | Preview logs and recordings eligible for daily cleanup; no deletion by default |
| `make check_audience_delay` | Check the five-second spectator timeline before client presentation |
| `make check_camera` | Check independent spectator controls and fixed centered player views |
| `make check_land` | Check networked stair traversal and camera controls |
| `make run_server` | Build and start the Odin server |
| `make run_client` | Start the Godot client |
| `make run_audience` | Start the Godot client as a viewer |
| `make run_client DEV=1` / `make run_audience DEV=1` | Show the development FPS/ping overlay |
| `make check_movement` | Check countdown, live movement, cameras, and replay |
| `make check_connection` | Run the local connection integration check |
| `make check_session` | Check Odin session/content rules and version 9 bytes |
| `make check_content` | Verify content readers, visuals, and digest/wire fixtures |
| `make check_selection` | Exercise selection, Ready, audience, and reset |
| `make check_arena_content` | Check map cells, terrain metadata, and coordinates |
| `make check_arena_selection` | Check map choice and Ready invalidation |
| `make check` | Run all current checks |

Run these targets from the repository root. The first server build also downloads and compiles its pinned ENet dependency under `build/deps/`.

In separate terminals, run one server and two clients. Both can start selection once connected; additional clients join as viewers and see the same picks and Ready states.

Later, deploy the server executable and required server data to the host. Distribute the exported Godot game and its resources to players. Sharing a source repository does not require distributing or deploying both programs together.

Keep generated output in `build/` and ignore it in Git. Also ignore the Godot cache at `client/.godot/`, while versioning the client source, scenes, and source assets whose terms permit redistribution. Tiny Swords PNG copies are installed locally and ignored; its manifest and provenance record are versioned. [Godot version-control guidance](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html)

## Current checkpoint boundary

Both players can choose characters and a shared map, then press Ready. The host runs **5, 4, 3, 2, 1**, places both trainers and runs a 1.5-second summon sequence for their selected gladiators. Fighters move their trainers with WASD/arrows, climb terraces via stairs, and keep their trainer centered at fixed zoom. Characters independently idle and walk within their summon area through the server AI orchestrator. Each audience member starts with a whole-map view, can pan and zoom independently, and can optionally follow either player. Either fighter can return the session to Lobby. Combat, senses, adaptive learning and terrain bonuses remain later phases.

## Autonomous character AI

[Checkpoint 6A](06b-autonomous-idle-walk.md) implements the pure `server/ai` package,
private `Battle_Runtime`, `Simulation` owner and Godot `CharacterMotionPresenter`.
Public session snapshots stay separate from future senses and cognitive memory.
The [architecture roadmap](06-character-ai-orchestration-proposal.md) retains the
later sensing, strategy and learning phases. Current transport uses protocol v9.

[Checkpoint 6A.1](06d-ai-debugger-harness.md) adds dedicated native workers and the
standalone Godot debugger at `client/dev/ai/ai_debug_window.tscn`. It loads no game
connection/arena, consumes private local trace files, and displays actual branches
and confirmed feedback. Its pause/step controls replay recorded decisions. Vision
and longer deliberation will extend this harness; neither is simulated by the UI.

[Checkpoint 6A.2](06e-qa-replay-and-trace-browsing.md) adds a virtual timeline,
background parsing, shared downward decision graphs and a separate match replay
window. `server/dev_replay.odin` records the host's public state plus matching traces;
the viewer samples existing rendering resources at the selected tick without running
AI or connecting to a match. Deterministic re-simulation remains planned.

Player1 walk preparation and prediction are described in [Player1 walk timing](05b-player-walk-timing.md). `client/players/trainer_movement.gd` mirrors `trainer_tick_motion`; `tests/player_step_check.gd` checks processed lift/plant poses and extends the trainer integration check.
