# Trainer running and target-found hop

Implemented 2026-09-11. Normal gameplay and development arenas use the same
trainer movement and energy rules.

## Controls and tuning

Hold **Space + WASD / arrows** to run with the trainer's existing `run` animation.
Release Space to walk. The player's HUD shows energy and its current state.

| Rule | Initial value |
| --- | --- |
| Walking / running speed | 120 / 240 world units per second |
| Full continuous run | Five seconds of actual running movement |
| Recovery delay after running | One second |
| Recovery while walking or resting | 10% per second |
| Resume after exhaustion | Recover to 20%, release Space, then hold it again |

Holding Space after exhaustion keeps walking; it cannot repeatedly spend each
newly recovered sliver of energy. Space alone, cancelled directions and fully
blocked movement do not spend energy. Walking and running share the existing
collision and summon rules. Switching between them keeps movement continuous.
Losing window focus clears Space with the direction keys. New rounds, including
development **Reset search [F7]**, restore full energy.

Both the run clip and energy reach remote players and delayed audience through
host snapshots. Each trainer has separate energy. Creatures do not receive
trainer energy through their senses; the current two-state visual contract
reports a running trainer as moving (`Walk`).

## Target-found reaction

The creature's body hops up 12 world units and lands after 0.36 seconds.
A dark, slightly shrinking shadow stays at its ground position while the body
rises. The exclamation follows the creature's head and stays visible for one
second from the original acquisition tick. The hop is a visual offset; the
creature's movement, collision footprint and sensed position stay on the ground.

The existing CC0 pixel asset remains selected by
`client/presentation/target_acquired.tres`. Replacing that resource changes the
art without changing the AI or protocol. `surprise_hop.gd` exposes jump height
and duration; `target_alert.gd` exposes marker scale and head spacing. The reaction is sampled from battle time,
including when replay is paused or seeks backward.

## Compatibility and QA

Protocol **11** adds trainer energy and a movement clock alongside the action
clock. Restart the launcher so host and clients use the same version. Existing
protocol-9 and protocol-10 recordings remain readable through the replay adapter.
See [the wire layout](protocol.md) and [implementation flow](codebase/trainer-running.md).

```sh
make dev_arena P1=archer P2=orc ARENA=tiny_swords_village
make check_trainers
godot --path client --script "$PWD/tests/trainer_run_check.gd" -- --server="$PWD/build/server"
```

For manual QA, run along clear ground until the meter empties. Verify the trainer
returns to walking, recovers, and requires releasing Space before another run.
Check both player views and an audience view. Use `make dev_vision` to see nearby
target-found reactions, then pause and seek a recording to inspect the hop.

The host checks cover five seconds of movement, exhaustion/release, recovery,
diagonal speed, blocked movement, input timeout, packet bursts, independent
energy, tick wrap and reset. The client check exercises prediction/reconciliation,
the real run clip, a live host with two players and delayed audience, focus loss,
HUD lifecycle, a recorded host tick matched against received energy/movement,
replay pose stability, both Archer and Orc bodies rising/landing, and the
shadow staying at their feet. The search integration also checks both bodies
jumping and landing in both live player windows and in recorded playback. Graphical input
is synthetic; physical keyboard/mouse acceptance is manual.

The initial 2026-09-11 `make check` passed, including 55 tests in both host
builds, but its animation check incorrectly tested only the marker. The owner's
review caught that mistake. The corrected checks require the creature's body
to rise, leave its shadow on the ground and land; marker movement alone fails.

The correction passed the headless and graphical trainer checks and the
graphical search integration across three launches, including recorded
pause/seek checks. Inspected Archer/Orc pose captures, live acquisition records
and logs are pinned in `build/verification/creature-surprise-hop-20260911/`.
These were targeted checks; the full suite was not rerun for this correction.
