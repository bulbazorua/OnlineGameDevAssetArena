# Project structure: one repository, two programs

Status: [Arena trainers and summoning](05a-trainers-and-summoning.md) adds trainer movement and a host-timed summon effect, with separate trainer/gladiator entities. [Player1 trainer harness](05-player-harness.md) adds a separate eight-state player art contract, importer, registry and preview scene. [Checkpoint 4C: selectable characters](04i-playable-characters.md) adds Archer/Orc to selection and the arena with processed runtime art, idle/walk playback and development action labels. [Checkpoint 3J: Tiny Swords Village](03j-tiny-swords-village.md) remains the latest map checkpoint. Shared combat follows later. [Phase 1: Host connection](01-host-connection.md) covers build requirements.

[Checkpoint 4A.1](04g-character-asset-processing.md) adds original fixture PNGs under `asset_sources/`, immutable processing attempts under `build/asset-jobs/`, and saved artifacts under `build/processed/characters/`. The harness consumes processed artifacts; source interpretation runs in a separate processing worker.

The original checkpoint plan is in [the character-selection and top-down-arena plan](03-selection-and-topdown-arena-plan.md). The tree below describes the existing code.

The [combat sensory plan](06j-combat-sensory-system.md) adds dedicated senses
windows as a future presentation responsibility, separate from the decision
debugger. No new runtime files are claimed in the tree below. Use generic
character/creature/agent/sense/perception names in code and contracts; MoPock is
conversational/design shorthand, not an identifier or module prefix.

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
│   │   └── protocol.gd             Version 10 packet codec
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
│   │   ├── fixtures/content/vision_range.arenas.json  Staged close-quarters QA arena for make dev_vision
│   │   └── ai/
│   │       ├── ai_debug_window.gd / .tscn  Separate per-creature native debugger
│   │       ├── trace_reader.gd     Bounded, validated live and journal replay input
│   │       ├── trace_loader.gd / trace_timeline.gd  Background parsing and visible-row log rendering
│   │       ├── decision_graph.gd / trace_palette.gd  Downward graph and shared status styling
│   │       ├── replay_window.gd / .tscn  Recorded-match QA controls and synchronized AI panels
│   │       ├── replay_store.gd / replay_reader.gd  Background bounded index and frame validation
│   │       ├── replay_stage.gd     Arena and entity poses at the selected recorded tick
│   │       ├── vision_view.gd      Creature-knowledge vision panel with a labelled host-diagnostics toggle
│   │       └── spatial_trace.gd    Legacy schema-1 wander geometry
│   ├── ui/
│   │   ├── lobby_screen.gd         Display state and emit user intent
│   │   ├── lobby_screen.tscn       Connection controls, roster, and Start
│   │   ├── character_select_screen.gd
│   │   ├── character_select_screen.tscn  Cards, both picks, Ready, audience
│   │   ├── arena_select_screen.gd / .tscn  Shared map choice and terrain inspection
│   │   ├── debug_overlay.gd / .tscn  Opt-in development FPS/ping panel
│   │   └── arena_preview.gd        Fit a world map to the screen
│   ├── content/
│   │   ├── game_content.gd         Validate catalog, visuals, senses, and fingerprint
│   │   ├── sense_catalog.gd        Validated vision/olfaction profiles, emitters and per-character bindings
│   │   ├── arena_catalog.gd        Terrain/arena definitions, walkability and sight blocking
│   │   ├── arena_presentation.gd   ArenaPresentation: validate theme and grounded props
│   │   ├── character_contract.gd   Draft export/role validation; no admission certification
│   │   ├── contracts/character_basic_combat/1.0.0-draft.1.json
│   │   ├── contracts/player_trainer/1.0.0-draft.1.json
│   │   ├── presentation/arenas/    Client-only Tiny Swords theme and building measurements
│   │   └── data/                   characters.json, terrains.json (schema 3), senses.json (schema 2), arenas.json
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
├── server/                         Odin host executable (package main) and its packages; see docs/codebase/server-architecture.md
│   ├── main.odin                   Options, lifetime, fixed 60 Hz loop and publication cadence
│   ├── host_simulation.odin        One authoritative step with brain threads and diagnostics attached
│   ├── brain_workers.odin          Two dedicated threads and copied private mailboxes
│   ├── network.odin                ENet lifecycle, command dispatch and session updates
│   ├── protocol.odin               Version 11 packet codec over simulation types
│   ├── audience.odin               Shared bounded spectator history and timed release
│   ├── scenario.odin               Debug-only canonical scenario and automatic entry
│   ├── *_test.odin                 Host-level tests: codec bytes, network membership, audience, workers, serial/threaded equivalence, diagnostics seam
│   ├── diagnostics/                Developer diagnostic writer and feeds (package diagnostics); see docs/codebase/server-diagnostics.md
│   │   ├── diagnostics.odin        Diagnostics state, launch gate, open/close, decision recording
│   │   ├── queue.odin              Copied jobs, drop-when-full queue
│   │   ├── record.odin             Record and its JSON view, writer-side fan cache, delivery clocks
│   │   ├── writer.odin             Writer thread loop, drain, publication cadence
│   │   ├── journal.odin            Rotating ai-N.jsonl journals and ai-N.json snapshots
│   │   ├── replay.odin             World capture from the host packet, match.replay.jsonl
│   │   ├── senses.odin / search.odin / scent.odin  senses.json, search.json, scent.json feeds and the scent capture slot
│   │   ├── probe_test.odin         Test-only construction and inspection used by host tests
│   │   └── *_test.odin             Projection, journal ceilings, scent capture, packet copy, queue and option tests
│   ├── content/                    Catalogs and static arenas (package content)
│   │   ├── catalog.odin            Game_Content, load/destroy, fingerprint, character parsing
│   │   ├── characters.odin         Character_Definition
│   │   ├── senses.odin             senses.json validation and character bindings
│   │   ├── arena.odin              Terrain/arena definitions, baked rules and coordinate queries
│   │   └── *_test.odin             Invalid data, digest fixtures, map validation, connectivity and stairs
│   ├── simulation/                 Authoritative runtime (package simulation)
│   │   ├── simulation.odin         Simulation, begin_tick and the serial reference step advance
│   │   ├── session.odin            Session, membership, countdown, arena entry, development entry, spawning
│   │   ├── commands.odin           Message kinds, Client_Command, rejection reasons, session_apply
│   │   ├── character.odin          Live Character, locomotion and facing, SIMULATION_HZ
│   │   ├── movement.odin           Fixed-step terrain movement shared by trainers and creatures
│   │   ├── trainers.odin           Trainer, energy and run clocks
│   │   ├── character_actions.odin  Shared voluntary action resolver: Move, Face (turn in place) and locomotion
│   │   ├── senses.odin             Host receptors (vision, olfaction), shared schedule gate, frozen-phase sampling and host-only audits
│   │   ├── scent_environment.odin  Emitters, deposits and field steps for the round's shared scent field
│   │   ├── battle.odin             Battle_Runtime, per-round/per-slot binding, prepare and resolve phases
│   │   ├── decisions.odin          Brain_Request/Brain_Response values and the single-brain decision
│   │   ├── dev_search_reset.odin   Host-only safe placement and fresh-round reset
│   │   └── *_test.odin             Session, movement, trainers, sensing, battle, scent and search behavior; shared scenario builders
│   ├── observations/types.odin     Data-only brain input contract: sightings, cues, samples, facing helpers
│   ├── perception/                 Privileged sensing physics: sight geometry, the scent field and the nose sampler
│   └── ai/                         Pure per-character decisions: Observe and Search tactics, private visual and scent memory
│       ├── observe.odin            Scan / orient / observe / reacquire from permitted evidence only
│       ├── visual_memory.odin      Bounded once-only ingestion, ageing and expiry
│       └── trace.odin              Optional bounded branch events with evidence references
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
│   ├── 06c-senses-and-ai-debug-windows-plan.md  Broader senses roadmap and earlier vision sketch
│   ├── 06d-ai-debugger-harness.md   Implemented thread/trace contract, debugger and evidence
│   ├── 06e-qa-replay-and-trace-browsing.md  Performance, playback contract, QA and re-simulation plan
│   ├── 06f-focused-and-peripheral-vision-proposal.md  Vision design proposal (implemented in 6B.1)
│   ├── 06g-focused-and-peripheral-vision.md  Implemented vision, memory, Face action, QA arena and verification
│   ├── 06h-vision-coding-agent-report.md  Coding-agent report for the owner and Team Lead
│   ├── 06i-vision-team-lead-review.md  Team Lead review of the first 6B.1 candidate
│   ├── codebase/sight-geometry.md  Closed-cell sight rule, lane sweep and the supported envelope
│   ├── codebase/battle-runtime-lifecycle.md  Per-round versus per-creature private runtime state
│   ├── delegation.md               Team Lead coding assignment for 6B.1
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
│   ├── ai_trace_check.gd           Schema-2 trace validation, evidence references, legacy schema-1 decoding
│   ├── fixtures/ai/                Genuine schema-1 snapshot/replay fixtures for legacy decoding
│   ├── vision_review/              Team Lead vision regression checks (wall edges, accepted range, one-creature replacement)
│   ├── olfaction_review/           Team Lead olfaction regression checks (crossed cells, detectable freshness, zero-coverage rendering)
│   ├── olfaction_coverage/         Coding-agent coverage fixtures and the rendered coverage probe for the Olfaction page
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

`server/main.odin` owns startup, network polling, and the fixed 60 Hz loop; each step is `host_simulation_step`. `network.odin` handles connections and calls the command rules in `simulation/commands.odin`; `protocol.odin` owns packet encoding. Two fighter slots are independent of audience connections. The `content` package validates shared character, terrain, sense and arena catalogs before listening. Players receive live membership/selection state; audience receives historical state through `Audience_Stream`, at the configured delay.

The `simulation` package owns the authoritative runtime: `simulation/session.odin` holds runtime characters, the countdown, spawning and trainer movement, and `Simulation` owns the private `Battle_Runtime` alongside the public session. `brain_workers.odin` runs each creature's AI on its own thread with copied input/state; the host applies returned intents through `simulation/character_actions.odin`. The `diagnostics` package (`server/diagnostics/`) exports optional private traces on a separate writer thread. Odin organizes packages by directory, so several `.odin` files in one package share declarations. [Odin packages](https://odin-lang.org/docs/overview/#packages) The owners, the tick and the thread map are in [server architecture](codebase/server-architecture.md).

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
| `make dev_vision P1=archer P2=orc` | Launch the staged close-quarters vision QA arena with both inspectors |
| `make dev_scent P1=archer P2=orc` | Launch the staged scent-trail QA arena; F8 toggles the host scent heatmap |
| `make check_scent` | Check scent trails, Olfaction pages, host heatmap, minimap, moving-emitter wake and decay, saved filters, reset and recorded olfaction |
| `make check_arena_overview` | Check the shared dev arena overview, radar frames and pages headless, then render the real pages at both window sizes (needs a display) |
| `make check_vision` | Run the perception geometry, AI memory/attention, host vision suites and the independent vision review checks |
| `make check_vision_review` | Run the Team Lead vision regression checks in normal and debug builds |
| `make check_olfaction_review` | Run the Team Lead olfaction regressions and the coverage fixtures in normal and debug builds, then render both coverage probes (needs a display) |
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

Both players can choose characters and a shared map, then press Ready. The host runs **5, 4, 3, 2, 1**, places both trainers and runs a 1.5-second summon sequence for their selected gladiators. Fighters move their trainers with WASD/arrows, climb terraces via stairs, and keep their trainer centered at fixed zoom. Characters independently scan, notice and watch nearby subjects through host vision and the server AI orchestrator, turning in place without walking. Each audience member starts with a whole-map view, can pan and zoom independently, and can optionally follow either player. Either fighter can return the session to Lobby. Combat, senses, adaptive learning and terrain bonuses remain later phases.

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
window. `server/diagnostics/replay.odin` (formerly `dev_replay.odin`) records the host's public state plus matching traces;
the viewer samples existing rendering resources at the selected tick without running
AI or connecting to a match. Deterministic re-simulation remains planned.

[Checkpoint 6B.1](06g-focused-and-peripheral-vision.md) adds `server/observations`,
`server/perception`, `server/senses.odin`, the Observe tactic and private visual memory in
`server/ai`, the Face action, `senses.json`, terrain sight blocking, trace/replay schema 2,
the Vision panels and the staged `vision_range` QA arena.

Player1 walk preparation and prediction are described in [Player1 walk timing](05b-player-walk-timing.md). `client/players/trainer_movement.gd` mirrors `trainer_tick_motion`; `tests/player_step_check.gd` checks processed lift/plant poses and extends the trainer integration check.

## Arena senses overlay

[The arena overlay slice](06k-arena-sense-overlay.md) adds `server/dev_senses.odin` (now `server/diagnostics/senses.odin`) for the writer-owned latest-sample projection, `client/dev/sense_feed.gd` for bounded local reads, `vision_cone_geometry.gd` for the clipped fields, and `sense_overlay.gd` for arena drawing. The existing debug UI groups these separately from physical colliders. `tests/sense_overlay_check.gd` verifies the slice. [Ownership and timing](codebase/arena-sense-overlay.md) are documented separately from the [live senses windows](06l-live-senses-windows.md).

The live companions use `client/dev/senses/senses_window.tscn` and its controller, `vision_readings.gd` for current-only row projection, `vision_sensor_view.gd` for the spatial view, and `display_metrics.gd` for bounded timing samples. `server/diagnostics/senses_test.odin` (formerly `server/dev_senses_test.odin`) covers projection lifecycle and delivery timestamps. `tests/senses_windows_check.py` with `tests/senses_window_driver.gd` verifies six-window operation, uncertainty, stale recovery, closure, reload and display latency. See the [deep dive](codebase/live-senses-inspector.md).

## Trainer running and target reactions

Trainer running and target-found animation are described in
[the running checkpoint](05c-trainer-running-and-target-alert.md).
`server/trainers.odin` owns per-trainer energy and movement clocks;
`client/players/trainer_movement.gd` predicts them and
`client/ui/trainer_energy.gd` displays the local meter.
`server/trainer_run_test.odin`, `tests/trainer_run_model.gd` and
`tests/trainer_run_check.gd` cover the host, prediction, animation and live clients.
`client/characters/surprise_hop.gd` supplies the creature's body lift and fixed
ground shadow; `CharacterView` applies the lift and positions the head marker.
`client/characters/target_alert.gd` keeps the marker's swappable texture.

## Olfactory trails additions

- `server/observations/types.odin`: `Scent_Class`, `Scent_Reading`, `Scent_Sample` (with sixteen `Scent_Coverage` words), `Olfaction_Profile`, `Scent_Emitter`; `Sense_Input` carries both senses with separate new-sample flags.
- `server/perception/scent_field.odin`, `olfaction.odin`, `scent_test.odin`: the shared scent field with authored media rules, the cell-by-cell deposit walk, the nose sampler with per-zone coverage and detectable-cell freshness, and their tests.
- `server/scent_environment.odin`: emitters, deposits and field steps inside `Battle_Runtime`; `server/senses.odin` now holds per-sense receptors with a shared schedule gate.
- `server/content_senses.odin` (senses schema 2), `server/arena.odin` (terrain schema 3 scent media), `client/content/sense_catalog.gd`, `arena_catalog.gd`.
- `server/ai/scent_memory.odin`, `search_scent.odin`, `scent_memory_test.odin`: private scent memory, own-trail discounting and scent-driven search transitions.
- `server/diagnostics/scent.odin` (formerly `server/dev_scent.odin`): quantized field capture and `scent.json`; `diagnostics/senses.odin` schema 4, `diagnostics/search.odin` schema 2, trace schema 5, replay envelope 5; `server/scent_battle_test.odin`.
- `client/dev/senses/olfaction_readings.gd`, `olfaction_sensor_view.gd`: the Olfaction page, drawing measured, partly measured and unknown ground apart; `client/dev/scent_feed.gd`, `scent_field_image.gd`, `scent_overlay.gd`, `window_preferences.gd`: the shared field painter, the F8 host heatmap and its saved filters.
- `client/dev/ui/dev_ui_style.gd`, `arena_overview.gd`, `sensor_radar.gd`: the shared dev UI palette, the whole-arena frame and the local radar frame; `client/dev/senses/sense_page.gd`, `vision_page.gd`, `olfaction_page.gd`, `vision_arena_layer.gd`, `scent_field_layer.gd`, `exploration_memory_layer.gd`: one page layout, the three page controllers and their arena layers ([deep dive](codebase/dev-arena-overview.md)); `tests/dev_arena_overview_check.gd`, `dev_arena_overview_render_check.gd`, `dev_arena_fixtures.gd`: headless contract checks and the rendered page probe (`make check_arena_overview`).
- `client/dev/fixtures/content/scent_trail.arenas.json`, `tests/scent_check.py`, `scent_client_driver.gd`, `scent_replay_check.gd`: the scent QA arena and integration harness.
- `tests/olfaction_review/` (Team Lead-owned), `tests/olfaction_coverage/`, `tools/measure_peak_memory.py`: independent regressions, rendered coverage probes and the six-window peak-memory measurement.

See [the feature record](06n-olfactory-trails.md) and [ownership deep dive](codebase/olfaction.md).

## Composite search additions

- `server/ai/search*.odin`: private search profiles, evidence handling, decaying visit history, local steering and behavior tests.
- `server/search_battle_test.odin`: real-map exploration, privacy, dedicated-worker equivalence and lifecycle checks.
- `server/diagnostics/search.odin` (formerly `server/dev_search.odin`): latest-only private search projection for development.
- `server/dev_search_reset.odin`: host-only safe placement and fresh-round reset; `dev_search_reset_test.odin` covers separation, lifecycle, rejected resets and development gates.
- `client/dev/search/`: saved preferences, validated feed, arena drawing, readable scores and recorded Search tab.
- `client/dev/search/search_reset_control.gd`: reset button, host confirmation and failure feedback; F7 routes here from the development overlay.
- `client/dev/senses/exploration_memory.gd`, `exploration_memory_panel.gd`, `exploration_memory_layer.gd`: owner-filtered visit projection, live memory page on the shared arena frame and its clickable layer. Uses the existing search feed independently of F6; no world-map query or decision-history loading.
- `tests/exploration_memory_check.gd`: private display data, decay, selection and lifecycle checks; the search integration verifies both live memory windows against private journals and across reset.
- `client/characters/target_alert.gd`, `client/presentation/target_acquired.tres`: public acquisition presentation and replaceable pixel asset.
- `tests/search_check.py`, `search_client_driver.gd`, `search_ai_driver.gd`, `search_replay_check.gd`: native/headless integration, actual restart persistence and recorded markers.

See [the feature record](06m-naturalistic-opponent-search.md) and [ownership deep dive](codebase/opponent-search.md).
