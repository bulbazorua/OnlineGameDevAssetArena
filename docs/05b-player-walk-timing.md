# Player1: lift and plant before translation

The supplied `player_walk.png` contains eight poses. Reading the feet from left
to right gives the following gait interpretation:

| Source pose (1-based) | Visible foot pose |
| --- | --- |
| 1 / 5 | Extended front foot contacting the ground |
| 2 / 6 | Weight settling onto the front foot, trailing foot drawing forward |
| 3 / 7 | Feet passing underneath the body |
| 4 / 8 | Leading foot raised and swinging forward |

The previous player path started on pose 1, held that image for 125 ms at 8 FPS,
and immediately translated the trainer. At the former 180-unit speed, the body
travelled 22.5 world units before the next pose. The earlier character-only
preparation fix did not affect this trainer path.

## Processed animation

Player1's private `art.json` rotates the existing eight crop descriptors to source
order **3, 4, 5, 6, 7, 8, 1, 2**. All original poses and their calibrated ground
anchors are retained. The raw PNG is untouched. Normal processing publishes a new
generation with the exact source crop, source checksum and transform provenance.
No filename parsing or Player1-specific frame ordering enters the shared renderer.

| Action age | Art pose | Trainer position |
| --- | --- | --- |
| 0 ms | Source pose 3: passing | Planted |
| 33 ms | Source pose 4: foot lifted | Planted |
| 67 ms | Source pose 5: foot contacts ground | Planted |
| 133 ms | Source pose 5, continuing into the cycle | First movement step |

The imported clip remains at 8 FPS. At runtime `PlayerView` accelerates just the
first two poses to 33 ms each, then continues at the normal clip rate. This is a
one-time adjustment per walk action: later loops, idle and the harness's source
preview retain their normal timing. The action clock itself is unchanged, so
late joins and reconciliation sample the correct point in that same sequence.

`TRAINER_WALK_START_TICKS = 8` reserves
enough time for lift, contact and a visible planted pose at 30/60/120 FPS. The
initial version used a 333 ms startup; this tuning reduces it to 133 ms. This is
an action's preparation time; input begins animating immediately. A tap released
before preparation finishes returns to idle without translation. Holding a
direction continues the cycle without repeating preparation on each packet.

## Simulation and networking

- `server/trainers.odin::trainer_tick_motion` validates the next terrain step,
  sets facing and starts the host walk clock. It writes position only after
  preparation. Release, blocked movement, opposing keys and heartbeat expiry
  cancel walking; a later walk starts a fresh clock.
- `client/players/trainer_movement.gd::step` mirrors that fixed-step rule for local
  prediction and input replay. Reconciliation restores the whole motion state,
  including the original state-start tick, before replaying pending inputs.
- `CharacterMotionPresenter` accepts preparation timing as a constructor value.
  Remote trainers and spectators use the trainer clock, while autonomous
  characters retain their separate 12-tick preparation. It does not spread
  translation across idle or planted portions of a snapshot interval.
- `PlayerView` receives the canonical `walk` role and animation age and remaps
  only the first two poses for faster startup; summoning
  overlays `advise` while locked. The old per-frame summon-finish reset was removed
  so it cannot erase a trainer's predicted walk state.

Protocol v9 adds six bytes per trainer to both world and arena-entry messages.
SessionState is 138 bytes, WorldState 121, and the packet cap 160. Audience history
copies these action clocks with the existing default five-second delay. Late
viewers sample the current eligible pose instead of restarting the walk clip.

The host speed was changed to **120 world units/second** during this work. Client
prediction now matches it (2 units per simulation tick), preserving that change.
The startup fix does not infer ongoing root motion from the artwork. Exact foot
locking throughout a walk would require a calibrated stride-distance contract;
the current loop still uses a fixed animation rate and travel speed.

## Verification

`make check_trainers` now runs `tests/player_step_check.gd`, which extends the
existing real-host trainer/summon integration check. It verifies that both the
lift and planted poses render before displacement at 30/60/120 FPS with eight
render-phase offsets, for local prediction and remote interpolation. It also
checks the host timing fixture and reconciliation from midway through preparation.

For the graphical version and a controlled frame sequence:

```sh
godot --path client --script "$PWD/tests/player_step_check.gd" -- --server="$PWD/build/server"
```

The [captured sequence](../build/verification/player-step/player-first-step.png)
uses the real processed Player1 art and production prediction states. The same
check then exercises real trainers, cameras, summoning, audience and round reset.
`make check_player_harness` verifies raw-to-processed provenance and failure recovery.

Initial first-step verification: the graphical player check, 3 pure AI tests, 27 host tests, and every
`make check` target passed across staged runs. Old fixed-duration movement tests
were updated for preparation and the 120-unit speed, then rerun with the remaining
targets. Development reload passed with unchanged process IDs for visual edits
and validated relaunches for code/data edits. The
[check index and logs](../build/verification/player-step/checks.txt) retain the
initial failures and successful reruns.

Faster-start tuning: 3 pure AI tests, 27 host tests, the graphical player-step
check at 30/60/120 FPS, movement integration and the default five-second audience
check passed. The check also verifies that acceleration applies only at action
start, later loops retain 8 FPS, and idle playback is unaffected. Updated captures
and `player-quick-start-*.log` are in `build/verification/player-step/`.
