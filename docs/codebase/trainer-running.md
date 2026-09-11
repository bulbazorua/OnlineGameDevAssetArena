# Trainer running: input, energy and presentation

`GameArena` tracks Space beside its existing direction keys and adds bit 16 to
the input mask. The welcomed connection identity chooses the trainer; the input
packet contains no speed, energy or position. Ordinary play uses this path too.

`Trainer` now embeds its shared spatial/action record and owns energy, recovery
delay, exhaustion and a movement-start tick. These are trainer fields rather
than additions to the creature's AI memory. `session_enter_arena` initializes a
fresh trainer with full energy. Session history copies the entire value, so
audience delay cannot mix old movement with live energy.

On each fixed tick, `trainer_tick_motion` checks the run request and available
energy, resolves the terrain step at walking or running speed, then chooses
idle/walk/run. It starts the movement clock only when leaving idle. It starts
the action clock when the displayed locomotion changes. This lets a walk/run
switch change the clip without repeating first-step preparation. Translation
still waits for the existing eight-tick preparation when starting from rest.

`trainer_tick_energy` charges only a translated running step. A charge resets
the recovery delay. Other ticks count that delay down, then restore energy.
Exhaustion remains locked until the trainer has recovered the threshold and
the input has released Space. No packet handler advances these clocks. Timeout
and summoning zero the whole input mask before movement is evaluated.

`TrainerMovement.step` mirrors the fixed-step rule for immediate local response.
Reconciliation copies energy, recovery delay, exhaustion and both motion clocks
from the host before replaying pending masks. Stale-world handling freezes
prediction. The HUD reads that predicted trainer and disappears on reset/lobby;
it never uses the other trainer's energy. Remote presentation uses the received
action clock to choose the `run` role and the movement clock to exclude planted
preparation from interpolation. The existing art contract supplies the clip.

Protocol 11 appends the bounded resource fields to the world/session messages.
The new eight-byte records keep one movement clock per trainer in addition to
its existing action clock. Old recordings are upgraded only by `decode_recorded`;
normal networking still requires the current version. AI vision projects a
running trainer as `Walk`, the existing coarse moving state, and forwards no
energy or input request to a creature.

The target-found hop is separate presentation. `CharacterMotionPresenter`
advances it with the displayed battle clock; `ReplayStage` supplies the selected
record's acquisition age directly. `surprise_hop.gd` samples a single parabolic
hop and draws the shadow at the character's ground origin. `CharacterView`
applies the lift to `body_sprite.position`, then places the action label and
exclamation above the raised head. The character root, footprint and sense
origin do not move vertically. Placeholder bodies use the same drawing offset.

`target_alert.gd` only draws the swappable marker. It has no separate hop or
shadow. Expiry, cleared acquisition and reconfiguration reset the body offset.
Animation-frame changes preserve the offset, so locomotion continues during
the reaction. There is no tween, delayed callback or simulation displacement.
Sampling the same age always produces the same pose, including replay seeks.
