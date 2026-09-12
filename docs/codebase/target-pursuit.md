# Target pursuit

## What was conflicting

The search controller used the same eight-direction scorer for wandering and
chasing. Random exploration, the previous search heading, old blocked headings
and visit penalties could outweigh a sighted opponent. The chosen direction was
then rounded to a compass heading before local navigation saw it. The target
position only limited stopping distance; it did not correct that direction.

A lingering avoidance bout from wandering could also win immediately after
acquisition. Separately, a short loss of focus counted as a new acquisition, and
a different focused creature could replace a still-remembered target.

## Responsibility and flow

1. [search_evidence.odin](../../server/ai/search_evidence.odin) selects a focused
   creature and keeps that subject while its sighting remains in memory. Other
   sightings do not replace it during that interval. Looking back at the same
   remembered subject continues the acquisition episode instead of restarting it.
2. [search_pursuit.odin](../../server/ai/search_pursuit.odin) points from the body's
   current position to the latest permitted target position. Pursuit does not use
   exploration noise, visits, or old search-direction penalties. Its compass
   scores remain available for the existing search display, but movement receives
   the continuous direction rather than a rounded compass vector.
3. [search.odin](../../server/ai/search.odin) submits that direction and the existing
   finite approach distance to the same local movement controller as foraging.
4. [navigation.odin](../../server/ai/navigation.odin) releases the old wandering
   bout when a finite approach begins. It still checks the creature's private
   terrain memory, chooses a body-safe passage, retains a passing side, respects
   bounded turns, and slows for uncertainty and arrival. Repeated pursuit updates
   do not restart that passing maneuver.
5. The authoritative simulation resolver executes movement and returns actual
   displacement. Local avoidance can detour or stop, but cannot replace the
   higher-level target with an unrelated wandering direction.

The existing goal-coupled obstacle avoidance remains the naturalistic movement
model described in [local-navigation.md](local-navigation.md). This change removes
competing movement goals; it does not add a second steering system or a hidden
map-based shortest route.

## Knowledge and limits

- Only focused creature sightings acquire or refresh a target. A peripheral cue
  or a smell cannot reveal identity or update the opponent's coordinates.
- Losing focus continues toward the last observed position. It does not predict
  unobserved movement, renew the evidence time, or copy another creature's memory.
- The existing focused-memory limit still applies. Reaching the last position
  invokes local search; expired evidence eventually returns to extensive search.
  The controller does not promise to follow an unseen opponent forever.
- The existing observation-distance stop remains unchanged. This is pursuit, not
  a new attack or combat mechanic.
- Foraging still uses its seeded exploration algorithm when no target is being
  pursued. Pursuit itself no longer draws wandering randomness. No new runtime
  fields, allocations, sensor work, network fields, or diagnostic schema changes
  are introduced.

## Regression coverage

[AI scenarios](../../server/ai/pursuit_test.odin) cover noisy and previously blocked
search headings, continuously updated goal directions, distractions, finite
private memory, reacquisition, safe passing commitment and trace parity.
[Simulation scenarios](../../server/simulation/pursuit_test.odin) use the real eyes
and movement resolver to follow a moving target and pass a body-sized visible
post before stopping at the existing observation distance.

Run `make check_session check_search check_ai_debugger` for the focused integration
gates. The full suite remains `make check`. Verification logs and the pre-change
source snapshot are under `build/verification/target-pursuit-*/`.
