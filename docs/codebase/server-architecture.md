# Server architecture: packages, owners and the tick

Code: [`server/`](../../server) (host executable), [`server/content/`](../../server/content),
[`server/simulation/`](../../server/simulation), [`server/ai/`](../../server/ai),
[`server/perception/`](../../server/perception), [`server/observations/`](../../server/observations).
Handback: [server refactor coding-agent report](../server-refactor-coding-agent-report.md).
R1 correction: [R1 coding-agent report](../server-refactor-r1-coding-agent-report.md).

This is the map for finding a feature, its state owner and its execution path after the
2026-09-12 structural refactor. Behavior, wire bytes, content digests, tuning and the
diagnostic file formats did not change; only where code lives and how it is called. The R1
correction narrowed the simulation package's callable API to the operations listed under
[public operations](#the-simulations-public-operations-and-private-mutation-paths); every
other simulation procedure is package-private.

## Packages and what each one owns

| Package | Owns | Must not know about |
| --- | --- | --- |
| `server` (`package main`) | Startup and options, the ENet host, packet encoding, the delayed audience history, the two brain threads, the diagnostic writer thread and its files, development scenarios. | Nothing above it; it is the top. |
| `server/simulation` | The authoritative runtime: `Simulation` = public `Session` + private `Battle_Runtime`. Membership, commands, countdown, arena entry, trainers, terrain movement, receptors and sampling, the scent environment, the battle phases, action resolution, the development search reset. | Sockets, files, threads, console output, the diagnostic writer. It imports only `content`, `ai`, `perception`, `observations` and `core:math/sync/time`. |
| `server/content` | Catalog loading and validation, definitions, baked arena rules, geometry queries, the cross-language fingerprint, allocation lifetime. | Sessions, brains, the host. It imports `perception` and `observations` for profile validity and grid types. |
| `server/ai` | One creature's private memory and decisions on a supplied `Agent`. | Any world lookup. It imports only `observations`. |
| `server/perception` | Privileged sensing physics: sight geometry, the scent field, the nose sampler. | Brains and sessions. It imports only `observations`. |
| `server/observations` | The data-only evidence contract every brain may read. | Everything. |

Dependency direction is one way: `main → simulation → content → perception → observations`,
with `ai → observations` beside it. Nothing lower imports anything higher, so a
simulation change cannot reach a socket and a brain cannot reach the map.

## Where the state lives

| State | Owner and type | Lifetime | Who may change it |
| --- | --- | --- | --- |
| Catalogs, arenas, baked opacity and scent media | `content.Game_Content` | `content.load` at startup until `content.destroy` at exit; the tick never allocates | Only `load`. Production reads through `find_character/arena/terrain` and the `arena_*` queries; the returned pointers are borrowed until `destroy`. Tests edit fixtures through the same pointers and re-bake with `arena_refresh_rules`. |
| Public match state | `simulation.Session` (inside `Simulation`) | The process; rounds change its round ID | `session_join/leave/reset`, `session_apply` (commands, including the development search reset), `session_tick`, `session_enter_arena`, `session_start_match` (development entry). Trainers move only inside `session_tick`; creatures move only inside `battle_resolve_decisions`. |
| Private creature runtime | `simulation.Battle_Runtime` (inside `Simulation`) | Bound by `battle_sync` per round; one slot rebinds when its entity changes ([lifecycle](battle-runtime-lifecycle.md)) | `battle_sync`, `battle_prepare_decisions` (receptor clocks, scent deposits, field steps), `battle_resolve_decisions` (adopted agents, action timing). |
| Brain inputs and outputs | `simulation.Brain_Request` / `Brain_Response` values | One tick | Built by `battle_prepare_decisions`; answered by `brain_decide`; consumed by `battle_resolve_decisions`. Copies only: no pointer into the session, the field, the map or the other brain. |
| Audience history | `Audience_Stream` in `server/audience.odin` | The process | `audience_advance` copies whole `Session` values on wall time. |
| Host diagnostics | `AI_Debug` in `server/dev_ai_debug.odin` | `ai_debug_open` until `ai_debug_close`; heap-owned, never moved | The simulation thread enqueues copies; the writer thread alone serializes and writes files. |

Two different protections apply here. Procedure visibility is checked by the compiler: a
`@(private)` procedure cannot be named from another package. Field visibility does not exist
in Odin, so every field of `Session` and `Battle_Runtime` is writable by any importer, and the
owner rules in the table above are conventions enforced by naming, by the import direction, by
review, and by the tests that compare copied runtimes byte for byte.

## The simulation's public operations and private mutation paths

These are the only simulation procedures another package can call. Everything else in
`server/simulation/` is `@(private)` (package scope) or `@(private = "file")`.

| Group | Public procedures | Production callers outside the package |
| --- | --- | --- |
| Session lifecycle | `session_join`, `session_leave`, `session_apply`, `session_start_match` | `network.odin` (join, leave, apply), `dev_scenario.odin` (start_match) |
| Session lifecycle, test-reached | `session_reset`, `session_tick`, `session_enter_arena` | None. Production reaches them through `session_leave`/`session_apply`, `begin_tick` and `session_start_match`; the host package's tests and the vision review fixture call them on a bare `Session` |
| Session queries | `session_player_mask`, `session_countdown_seconds` | `protocol.odin`, `dev_scenario.odin`, `network_test.odin` |
| Fixed step | `begin_tick`, `battle_prepare_decisions`, `battle_resolve_decisions`, `advance` | `host_simulation.odin`; `advance` is also the serial reference in the host tests |
| Fixed step, test-reached | `battle_sync` | None. `begin_tick` runs it; the host tests and the vision review fixture call it to rebind one replaced creature without ticking |
| Brains | `brain_decide`, `decide_serially` | `brain_workers.odin`, `host_simulation.odin` |
| Types and constants | `Simulation`, `Tick_Start`, `Session`, `Player_Slot`, `Session_Phase`, `Character`, `Trainer`, `Receptor` and its parts, `Scent_Environment`, `Battle_Runtime`, `Decision_Outcome`, `Brain_Request`, `Brain_Response`, `Client_Command`, `Message_Kind`, `Command_Reject_Reason`, `Dev_Search_Spawn`, `MAX_PLAYERS`, `SIMULATION_HZ`, the trainer and character constants | `protocol.odin`, `audience.odin`, `main.odin`, `brain_workers.odin`, `dev_*.odin` |

The shared scenario builders in `simulation/scenario_test.odin` (`battle_test_scenario`,
`battle_test_content_with_qa`, `scent_test_scenario`) are public so the host package's tests
can build the same worlds. They are test fixtures, not part of the production contract, even
though Odin compiles `_test.odin` files into normal builds.

Each public operation owns the private steps below. The host cannot run a step on its own,
so trainer energy changes only with trainer motion, receptors reset only when a creature is
bound, and an action is resolved only together with the agent's confirmed result.

| Public operation | Package-private steps it runs, in order |
| --- | --- |
| `session_tick` | `trainer_tick_motion` → `character_move` → `movement_apply_delta`; then `trainer_tick_energy` (file-private to `trainers.odin`) |
| `session_apply` | `serial_is_newer` for input ordering; `dev_search_reset` → `dev_search_reset_placements` → `dev_search_distance_squared` and the reachable/spawn/farthest helpers |
| `session_enter_arena` | `session_next_entity`, `summon_position` |
| `battle_sync` | `scent_environment_bind`; per slot `battle_bind_creature` → `receptor_bind`, `scent_environment_bind_creature` |
| `battle_prepare_decisions` | `scent_environment_tick` (emitter follow, field step); `senses_prepare` (receptor gates and samples); `character_turn_ready`, `character_facing_to_observation` |
| `battle_resolve_decisions` | per slot `battle_resolve_creature` → `character_resolve_intent` → `movement_apply_delta`, then `ai.agent_record_result` and the target alert |

Tests inside `server/simulation/` may call these private steps directly; tests in other
packages use only the public operations and the shared scenario builders.

## One fixed step

`run_host` in `server/main.odin` runs the loop: poll the network, start a pending
development scenario, then catch up fixed steps and publish. Each step is
`host_simulation_step` in `server/host_simulation.odin`:

```text
simulation.begin_tick          was summoning already over? (can_act) -> session_tick -> battle_sync
simulation.battle_prepare_decisions
    scent_environment_tick     confirmed bodies deposit on the ground; the field steps on its clock
    senses_prepare             every due eye and nose samples one frozen world phase
    one Brain_Request per creature: own agent, own samples, self condition
brain_workers_decide | simulation.decide_serially
    both requests submitted before either answer is collected; each runs simulation.brain_decide
simulation.battle_resolve_decisions
    adopt both decided minds, then per slot: character_resolve_intent -> ai.agent_record_result -> target alert
ai_debug_record_decisions      host only: append the confirmed outcome to each trace and enqueue a record
ai_debug_capture_world / ai_debug_capture_scent
```

The indented simulation names (`scent_environment_tick`, `senses_prepare`,
`character_resolve_intent`) are package-private; the host reaches them only through the
phase above them.

`simulation.advance` runs the same phases on the calling thread with no diagnostics. It
is the serial reference: the host package's tests step one copy with `advance` and another
with `host_simulation_step` and require identical sessions and runtimes.

Publication stays in the host loop: the session packet goes out when a step or a command
marked it dirty (also during network polling), the world packet every third tick
(`SNAPSHOT_INTERVAL` in `main.odin`), and the audience packet from the delayed history.

## Threads

| Thread | Runs | Touches |
| --- | --- | --- |
| Main | Network, session, battle phases, resolution, diagnostic enqueue | Everything owned by `Simulation`; only copies leave it |
| Brain worker 1 and 2 (`server/brain_workers.odin`) | `simulation.brain_decide` on the mailbox copy | Its own `Brain_Request`/`Brain_Response` mailbox behind two semaphores |
| Diagnostic writer (`server/dev_ai_debug.odin`) | JSON, journals, snapshots, replay frames, scent heatmap | The bounded job queue under its mutex, writer-owned history and the copied scent capture |

Workers are created before the first tick and joined at exit; a started worker is never
moved or copied. The writer owns its opacity grid copies and file handles.

## Commands and the wire

`simulation/commands.odin` holds `Message_Kind`, `Client_Command`, `Command_Reject_Reason`
and `session_apply`. `server/protocol.odin` turns bytes into those commands and sessions
into bytes; it imports the simulation, never the reverse. The content fingerprint framing
in `content/catalog.odin` writes its own little-endian lengths so the digest bytes stay
identical without a codec dependency. Protocol details: [protocol record](../protocol.md).

## Where a feature goes

- A new command: `simulation/commands.odin` (rule) and `server/protocol.odin` (bytes).
- A new public field of a body: `simulation/character.odin`, then the codec and the Godot decoder.
- A new sense: a receptor in `simulation/senses.odin`, physics in `perception`, the
  evidence type in `observations`, memory and use in `ai`, a projection in `server/dev_*.odin`.
- A new catalog or arena rule: `content`.
- A new diagnostic file: `server/dev_*.odin` on the writer thread; capture copies on the main thread.
- A new development-only session operation: `simulation` owns the mutation and validation;
  the host prints or publishes the result (`dev_log_search_reset` is the pattern). Keep the
  procedure `@(private)` unless the host itself must call it.

## Build, test and debug entry points

| Command | What it exercises |
| --- | --- |
| `make build_server` | Debug host build; `odin build server -o:speed` is the release gate used by `tests/ai_debugger_check.py` |
| `make check_session` | `odin test server/content`, `server/simulation` and `server` (host package), after `check_ai` |
| `make check_ai_debugger` | The same three packages in `-debug` builds, then the real-worker and inspector harness |
| `make check_vision_review`, `check_olfaction_review` | The Team Lead harnesses; the vision harness imports `content` and `simulation` directly |
| `make dev_arena`, `dev_vision`, `dev_scent` | The staged launcher; every `.odin` save under `server/` (nested packages included) rebuilds the host |

Test placement follows ownership: catalog and arena rules in `server/content/*_test.odin`;
session, movement, trainers, sensing, battle, scent and search behavior in
`server/simulation/*_test.odin` (their shared scenario builders live in
`scenario_test.odin`, and same-package tests may exercise private helpers); anything that needs threads, the audience history, the codec or the
diagnostic writer in `server/*_test.odin`.

## File map before and after the refactor

Older checkpoint records name the pre-refactor files. Read them with this table.

| Before (root package) | Now |
| --- | --- |
| `content.odin`, `content_senses.odin`, `characters.odin`, `arena.odin` | `content/catalog.odin`, `content/senses.odin`, `content/characters.odin`, `content/arena.odin` |
| `session.odin` (+ `session_tick`, `session_enter_arena` from `movement.odin`; `session_next_entity`, `summon_position` from `trainers.odin`) | `simulation/session.odin` |
| `session_apply`, `Client_Command`, `Message_Kind`, `Command_Reject_Reason`, `serial_is_newer` | `simulation/commands.odin` |
| `Character`, locomotion and facing enums, `SIMULATION_HZ` | `simulation/character.odin` |
| `character_move`, `movement_apply_delta` | `simulation/movement.odin` |
| `trainers.odin`, `character_actions.odin`, `senses.odin`, `scent_environment.odin`, `dev_search_reset.odin` | Same names under `simulation/` |
| `battle.odin` (`battle_tick`) | `simulation/battle.odin` (`battle_prepare_decisions`, `battle_resolve_decisions`) and `simulation/decisions.odin` (`Brain_Request`, `Brain_Response`, `brain_decide`) |
| `simulation.odin` (`simulation_tick`) | `simulation/simulation.odin` (`begin_tick`, `advance`) and `server/host_simulation.odin` (`host_simulation_step`) |
| `SNAPSHOT_INTERVAL` in `movement.odin` | `server/main.odin` |
| `content_load`, `content_destroy`, `content_character`, `content_arena`, `content_terrain`, `content_parse_extra` | `content.load`, `content.destroy`, `content.find_character`, `content.find_arena`, `content.find_terrain`, `content.parse_extra` |
