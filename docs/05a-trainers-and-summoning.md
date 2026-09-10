# Trainers in the arena and automatic summoning

**Current follow-up:** [checkpoint 6A](06b-autonomous-idle-walk.md) adds autonomous idle/walk after summoning. [Player1 walk timing](05b-player-walk-timing.md) adds lift/plant preparation, matching trainer prediction and protocol v9. The descriptions below record this earlier checkpoint.

This checkpoint adds a controllable trainer for each fighter and automatically
summons their selected gladiator. Both trainers use the processed Player1 style.
WASD/arrows now move the trainer. Selected gladiators remain idle at their summon
positions while their autonomous combat behavior is developed in a later phase.

```sh
make dev_arena P1=archer P2=orc ARENA=tiny_swords_village AUDIENCE=1
# Include the normal countdown when testing:
make dev_arena P1=archer P2=orc ARENA=meadow_crossing COUNTDOWN=5 AUDIENCE=1
```

The launcher still accepts all shape and character picks. `P1`/`P2` choose the
**gladiators**, not the trainer style. Normal Ready starts the five-second countdown;
the development launcher can skip that countdown. Both paths run the same summon
sequence. Audience delay remains five seconds by default; use `AUDIENCE_DELAY=0`
for an immediate development audience view.

## Arena entry

1. At countdown completion, the host allocates two trainers and two selected
   gladiator entities with distinct runtime IDs. Trainers use the map's spawn
   centers. Gladiator positions are reserved on nearby clear land.
2. The host advances `summon_elapsed_ticks` from 0 to 90 at 60 Hz. Trainer input is
   acknowledged but movement remains locked during these 1.5 seconds.
3. The client plays the trainer's existing `advise` gesture, showing a colored orb
   arcing toward the reserved gladiator position. This is a presentation use of
   `advise`; it does not emit gameplay advice or affect a bond/mood system.
4. At tick 36 (0.6 seconds), a ring and particles appear and the gladiator starts
   materializing. Its opacity and scale reach their normal values over 24 ticks.
5. At tick 90, the effect ends and trainer movement becomes available. The camera
   follows the local trainer at the existing fixed zoom.

```mermaid
sequenceDiagram
    participant H as Odin host
    participant P as Player clients
    participant A as Audience
    H->>P: Arena entry: trainers, reserved gladiators, summon tick 0
    Note over P: Trainer gesture and orb; gladiators hidden
    H->>P: Summon tick 36
    Note over P: Gladiators materialize
    H->>P: Summon tick 90
    Note over P: Trainer movement enabled
    H->>A: Same entity states and summon ticks after configured delay
    Note over A: Independent camera; summon follows historical state
```

The effect uses received simulation progress rather than starting a local timer on
join. Display progress interpolates between snapshots without predicting unseen
summon ticks. A stopped feed freezes the sequence. A viewer joining after completion
sees the already summoned gladiators, with no replay. Round reset or disconnect
clears trainer views, gladiator views, effects, prediction history and camera input.
There are no delayed spawn callbacks that can recreate entities after cancellation.

## State and authority

`Session.trainers` and `Session.characters` are separate two-entity collections.
`characters` continues to identify selected gladiators. The shared spatial record
holds runtime ID, definition ID, owner, position and input acknowledgement. Only
trainers receive fighter input and use prediction/reconciliation. Gladiators never
consume those input sequences.

Protocol **version 7** transmits both collections plus the summon clock in every
arena snapshot. Trainer definition ID 1 maps to Player1 for this first slice.
Trainer speed is 180 world units/second and its radius is 9.6 world units, matching
Player1's gameplay size 1 × footprint 0.3 × the 32-unit ruler. These host/client
constants belong to the versioned protocol. Adding selectable trainer styles or
changing gameplay measurements requires an explicit shared definition change.

Spawn placement first tries two cells toward the arena center, then scans nearby
cells on the same elevation. It checks terrain clearance and separation from both
trainers and the other reserved gladiator. All shipped maps are tested with every
current gladiator. Very small custom maps without room use the already validated
original spawn as a land-safe fallback; entity-to-entity collision remains deferred.

Spectator history stores full Session values, including trainer positions and the
summon clock. Live player movement and summoning never bypass that history for an
audience connection. Audience zoom/pan remain local and immediate; following P1/P2
now follows the corresponding trainer.

## Implementation

| File / class | Responsibility |
| --- | --- |
| `server/trainers.odin` | Trainer constants, entity allocation and summon placement |
| `server/session.odin`, `server/movement.odin` | Separate entity collections, movement ownership, summon lock and fixed clock |
| `server/protocol.odin`, `client/network/protocol.gd` | Version-7 records and validation |
| `client/session/session_snapshot.gd` | Separate trainer/gladiator states; immutable snapshot replacement |
| `client/content/player_content.gd` / `PlayerContent` | Load processed player runtime art and validate host footprint agreement |
| `client/content/presentation/players.json` | Player runtime bundle declarations |
| `client/players/player_view.gd` / `PlayerView` | Trainer label, gesture playback, idle/walk presentation |
| `client/world/summon_effect.gd` / `SummonEffect` | Procedural orb, ring, beam and particles driven by received ticks |
| `client/world/game_arena.gd` | Entity views, trainer prediction/camera and materialization |
| `tools/prepare_characters.py --family=players` | Reuse the processing/bundling pipeline for player art |
| `tools/dev_session.py` | Prepare both art families and wait until summoning completes |

`make prepare_players` publishes processed Player1 art into
`client/generated/players/`. Runtime clients use this data-only bundle, with no
raw sheets or importer execution. The original and processed asset pipeline from
the [player harness](05-player-harness.md) remains intact. Player package/raw edits
use the launcher's validated rebuild/relaunch path.

## Verification

`make check_trainers` uses a real Odin host, two independent client viewports and
an audience, checking summon locking, selected art, paused-feed behavior, delayed
progress, trainer movement, fixed gladiator positions, late joins, replay and
cancellation. The Odin tests exercise every map/pick, land-safe spawns, IDs, input
ownership and history copying. Existing movement, terrain, camera, audience, bundle
and development-workflow checks now exercise trainers where movement is involved.

```sh
make check
# Graphical sequence captures:
godot --path client --script "$PWD/tests/trainers_check.gd" -- --server="$PWD/build/server"
```

Graphical captures and logs are under `build/verification/trainers/`. This phase
provides arena trainers and summon presentation. Combat AI, following, advice
commands, receptivity and bond effects are subsequent gameplay work.
