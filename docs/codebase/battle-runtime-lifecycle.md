# Battle runtime lifecycle: per-round versus per-creature state

Code: [`server/battle.odin`](../../server/battle.odin) (`battle_sync`,
`battle_bind_creature`), [`server/senses.odin`](../../server/senses.odin)
(`receptor_bind`), [`server/ai/orchestrator.odin`](../../server/ai/orchestrator.odin)
(`agent_reset`). Behavior record:
[6B.1 focused and peripheral vision](../06g-focused-and-peripheral-vision.md).

## What lives where

`Battle_Runtime` is the private sibling of the public `Session`. It is never copied into
audience history or wire packets. It holds two kinds of state:

| Scope | Fields | Cleared when |
| --- | --- | --- |
| Round-wide | `round_id`, `config` (Observe tuning), `limits` (shared Move limits), `bound`, `scent.field` (the shared scent ground) and the two trainer emitter records | The session leaves the arena or the round ID changes |
| Per creature (slot) | `agents[i]` (visual and scent memory, attention, search, last decision), `receptors[i]` (eye and nose: profile, schedule, retained sample, host audit each), `scent.emitters[i]` (this body's emitter record), `actions[i]` (turn timing), `anchors[i]` (spawn anchor) | That slot's runtime entity ID changes, or the round is cleared |

## How `battle_sync` decides

`simulation_tick` calls `battle_sync` once per tick before any sensing or decision.

1. Not in the arena: the whole runtime is zeroed. Nothing private survives a return to
   the lobby.
2. Unbound, or a different round ID: the runtime is rebuilt from scratch and every slot
   is bound fresh. A new round starts both creatures from nothing.
3. Otherwise, each slot is compared to the session's character in that slot. Only a slot
   whose entity ID differs is rebound. The other slot is not touched at all, so its
   memories, attention, retained eye sample, sampling deadline and turn timing stay
   byte-for-byte identical.

`battle_bind_creature` is the single place that produces a fresh slot: an empty agent
for the new entity and round, the spawn position as movement anchor, receptors bound to
the character definition's vision and olfaction profiles (schedules and samples cleared),
a re-armed emitter record that paints no trail, and zeroed turn timing. Old deposits on
the ground stay for the replacement to smell; only a round change clears the field
([olfaction](olfaction.md)).

## Why per-slot binding matters

The first candidate rebuilt the whole runtime whenever any slot's entity changed, so
replacing P1 also erased P2's private experience. That violates the rule that another
creature's memory must not be silently altered by a hidden event: P2 never sensed the
replacement, so its knowledge must not change until a genuine sample shows it. With
per-slot binding, P2's old sighting of the previous entity stays in memory at its
original time and position until it expires or is replaced by fresh evidence. The next
eye sample then reports the new entity as a new subject handle.

The host test `replacing_one_creature_keeps_the_other_creatures_private_runtime` covers
both slots, the round-wide fields, the kept creature's continued sampling schedule and
its aging memory of the old subject. The Team Lead's independent
`tests/vision_review` harness covers the P1 case against production APIs.

There is no player-facing replacement feature yet; the entity ID change is the seam that
a later summon/swap feature will use.
