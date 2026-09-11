# Olfaction: ownership, flow and clocks

Code: [`server/perception/scent_field.odin`](../../server/perception/scent_field.odin),
[`server/perception/olfaction.odin`](../../server/perception/olfaction.odin),
[`server/scent_environment.odin`](../../server/scent_environment.odin),
[`server/senses.odin`](../../server/senses.odin), [`server/ai/scent_memory.odin`](../../server/ai/scent_memory.odin),
[`server/ai/search_scent.odin`](../../server/ai/search_scent.odin), [`server/dev_scent.odin`](../../server/dev_scent.odin),
[`client/dev/senses/olfaction_sensor_view.gd`](../../client/dev/senses/olfaction_sensor_view.gd),
[`client/dev/scent_overlay.gd`](../../client/dev/scent_overlay.gd). Behavior record:
[6B.2 olfactory trails](../06n-olfactory-trails.md).

## One lifecycle for every sense

```text
configuration            senses.json profile -> Character_Definition.olfaction / .emitter, Game_Content.trainer_emitter
scheduled measurement    Receptor.olfaction (Olfaction_Receptor: profile, Receptor_Schedule, last, audit)
private observation      obs.Scent_Sample inside obs.Sense_Input, with olfaction_is_new
brain input              ai.Decision_Context.senses + own_emitter -> Scent_Memory -> Search_Runtime.scent
diagnostic projection    dev_senses.odin (senses.json), dev_search.odin (search.json), dev_scent.odin (scent.json)
recorded evidence        AI_Debug_Record.input / before / after / scent_audit -> trace schema 4 -> replay envelope 4
```

Vision follows the same shape with `Vision_Receptor`, `Vision_Sample` and
`Visual_Memory`. `Receptor_Schedule` and the private `receptor_gate` in
`senses.odin` are shared: every sense answers Disabled, Waiting, Retained or Due
the same way, and a Retained sense hands back its last sample unchanged. The
measurement rules stay separate: `perception.vision_sample` walks the opacity
grid, `perception.olfaction_sample` walks the scent field. Neither imports the
other's rules.

## The world side: field and emitters

`Scent_Environment` lives inside `Battle_Runtime`, next to agents and
receptors, so a round change zeroes everything together and a copied runtime
carries its own field. The field is fixed storage (`Scent_Field`, about 213 KB)
because the runtime is compared and copied by value in tests and the production
tick must not allocate.

`scent_environment_bind` initialises the field from the arena's baked
`scent_media` and arms one `Scent_Emitter_State` per body: two creatures, then
two trainers. `battle_bind_creature` re-arms only its creature's emitter.
`scent_environment_tick` runs first in `battle_tick`:

1. `scent_emitter_follow` compares each body's confirmed position with the
   position the field last recorded. A different entity, or a first sight of the
   body, re-arms without painting. Otherwise, while the round is live and the
   emitter is enabled, `scent_field_deposit_segment` shares one tick of emission
   over the cells the segment crossed. Longer than two tiles is a teleport and
   paints nothing.
2. Every `SCENT_STEP_TICKS` ticks `scent_field_advance` runs one spread-and-decay
   step over the box that currently holds scent, computing each cell's open
   neighbours once for both classes. Solid cells and the map edge exchange
   nothing; water decays faster. A cell's age is the age of its dominant
   contributor, so a halo is as old as the trail it came from, and a deposit
   always resets it to zero.

Only the environment writes the field. Workers never see it: `Brain_Request`
carries an agent and a decision context by value, and `ai` imports only the
data-only `observations` package.

## The nose side

`olfaction_receptor_sample` in `senses.odin` builds an `Olfaction_Query` with
the observer's pose, its profile and a pointer to the field that only the host
holds. `perception.olfaction_sample` gathers cells (skipping the blind disc and
solid cells), keeps per-zone maxima, reduces each class to bands, a coherence
gated bearing and a freshness band, and numbers readings in the upper half of
the observation-ID space. The `Olfaction_Audit` returned beside the sample
(cells sampled, cells blind, raw peaks, newest ages, coherence) stays in the
receptor and reaches diagnostics as `host_scent_audit`, outside the brain input.

Both receptors of one creature sample from the same frozen phase, but each has
its own `Receptor_Schedule`. `Sense_Input` carries `vision_is_new` and
`olfaction_is_new` separately; `ai_debug_note_delivery` keeps one delivery clock
per sense per owner, so a new smell never refreshes the eye's clock.

## The brain side

`scent_update_memory` runs in both controllers after the visual memory update:
it notes the sample in the trace, ingests a genuinely new sample once into
`Scent_Memory` (one entry per class, three-second expiry from the sample tick)
and expires old entries against the decision tick. `scent_memory_is_current`
means "from the newest sample and at most two intervals old"; anything else is
retained memory.

`search_interpret_scent` turns memory entries into candidates. For the class
the body itself emits, zones whose probe point (origin plus a quarter or three
quarters of the range along the sector) lies in a region the searcher visited
within `self_trail_ticks` are discounted, and strength and bearing are rebuilt
from the survivors. The best candidate becomes `Search_Runtime.scent`, with the
discounted zone count kept for the inspectors. `search_read_evidence` keeps its
priority order: focused opponent, remembered focused position, visual cue, then
`search_follow_scent`, then the local-search budget, then extensive search. A
bearing set by the nose is flagged `cue_from_scent` so the visual-cue retention
branch never relabels it as a remembered cue, and `search_choose_heading` uses
`scent_weight` instead of `cue_weight` for smelled bearings.

## Diagnostics

`dev_senses.odin` (schema 3) adds the nose sample, its delivery time and the
owner's emitter to each live record. `dev_search.odin` (schema 2) publishes the
runtime with its scent evidence. `dev_scent.odin` is the only reader of the
field outside the simulation: `ai_debug_capture_scent` copies a quantized field
into a mutex-guarded slot on the simulation thread whenever a field step or
round changed (a memcpy-sized critical section, no JSON), and the writer thread
publishes `scent.json` every 100 ms with base64 level and age layers per class.
The client `scent_feed.gd` validates identity and layer sizes, and
`scent_overlay.gd` paints one pixel per cell into a texture whenever the
publication or the class filters change. The heatmap therefore shows exactly
the published field; it never queries emitter positions or invents deposits.

The Olfaction page (`olfaction_readings.gd`, `olfaction_sensor_view.gd`) draws
the sixteen zones of each delivered reading. Because the sensor is zone based,
the page cannot and does not draw a tiled trail. Its status and display metrics
use the scent delivery clock, separate from vision's.

The writer thread processes every queued job in one pass and, when it publishes
the two 80-record history snapshots every 250 ms, it catches up on the queue
between the two owners' snapshots (`ai_debug_drain`). A fresh eye or nose
sample therefore waits behind at most one snapshot serialization, not both,
which keeps the delivery-to-display clock of the 5 Hz Olfaction page inside
the 150 ms target without touching sensor rates.

## Clocks and limits worth knowing

- Field steps, half-lives, retention, freshness bands and the self-trail window
  are all simulation ticks. There is no wall-clock anywhere in the model.
- Work per field step is bounded by the map (16,384 cells); work per nose sample
  is bounded by the cells inside the range, at most the map. The worst accepted
  case is measured in `scent_test.odin`.
- The trace record ceiling stayed at 48 KiB; the measured worst case is 40,931
  bytes with every array full. Journal rotation therefore comes sooner than it
  did with schema 2 records; the harnesses read across rotated segments.
- The host field is not recorded. Replay keeps the recorded nose samples,
  memory and search evidence per frame and labels the field unavailable.
