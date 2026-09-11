# Olfaction: ownership, flow and clocks

Code: [`server/perception/scent_field.odin`](../../server/perception/scent_field.odin),
[`server/perception/olfaction.odin`](../../server/perception/olfaction.odin),
[`server/simulation/scent_environment.odin`](../../server/simulation/scent_environment.odin),
[`server/simulation/senses.odin`](../../server/simulation/senses.odin), [`server/ai/scent_memory.odin`](../../server/ai/scent_memory.odin),
[`server/ai/search_scent.odin`](../../server/ai/search_scent.odin), [`server/dev_scent.odin`](../../server/dev_scent.odin),
[`client/dev/senses/olfaction_sensor_view.gd`](../../client/dev/senses/olfaction_sensor_view.gd),
[`client/dev/scent_overlay.gd`](../../client/dev/scent_overlay.gd). Behavior record:
[6B.2 olfactory trails](../06n-olfactory-trails.md). Package map: [server architecture](server-architecture.md).

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
`scent_environment_tick` runs first in `battle_prepare_decisions`:

1. `scent_emitter_follow` compares each body's confirmed position with the
   position the field last recorded. A different entity, or a first sight of the
   body, re-arms without painting. Otherwise, while the round is live and the
   emitter is enabled, `scent_field_deposit_segment` shares one tick of emission
   over the cells the segment crossed. Longer than two tiles is a teleport and
   paints nothing.

### The deposit walk

`scent_field_deposit_segment` walks the segment from the previous confirmed
position to the new one, cell by cell, and gives each cell the share of the
path that lies inside it. Sampling points along the segment was not enough: a
short diagonal step can enter a neighbouring cell for less than half a tile and
leave again, which the old half-tile point samples skipped (Team Lead R1).

- `scent_axis_walk` prepares one axis: the segment fraction at which the walk
  reaches the next vertical (or horizontal) grid line, the fraction between
  consecutive lines, and the cell step direction. A zero delta never crosses.
- The main loop takes the nearer of the two next crossings, deposits
  `amount × (crossing − covered)` on the current cell, then steps in x, in y, or
  in both when the crossings coincide. When the next crossing lies at or beyond
  the segment end, the remaining share goes to the current cell and the walk ends.
- Conventions: a point exactly on a grid line belongs to the cell with the higher
  index (`floor`), so the start cell is `scent_field_cell_of(from)`; a crossing
  exactly through a corner steps diagonally and touches neither side cell; a
  zero-length segment (standing still, blocked step) deposits everything on the
  body's cell.
- Bounds: the shares sum to the tick's emission; ground that is solid or beyond
  the map keeps its share out of the field (`scent_field_deposit` refuses it), so
  total emission never exceeds `SCENT_EMISSION_PER_TICK × intensity`. A step of at
  most two tiles crosses at most five cells; `SCENT_SEGMENT_MAX_CELLS` only guards
  the loop against rounding surprises.

Because consecutive segments share their end points, ground is covered exactly
once and the deposit per tile depends only on speed: crossing a 32-unit tile at
64 units per second still leaves 0.75, and a standing body still saturates its
cell. The perception tests compare the walk with a dense thousand-point oracle
across the 16-, 32-, 64- and 128-unit tile sizes.
2. Every `SCENT_STEP_TICKS` ticks `scent_field_advance` runs one spread-and-decay
   step over the box that currently holds scent, computing each cell's open
   neighbours once for both classes. Solid cells and the map edge exchange
   nothing; water decays faster. A cell's age is the age of its dominant
   contributor, so a halo is as old as the trail it came from, and a deposit
   always resets it to zero.

Only the environment writes the field. Workers never see it: `simulation.Brain_Request`
carries an agent and a decision context by value, and `ai` imports only the
data-only `observations` package.

## The nose side

`olfaction_receptor_sample` in `simulation/senses.odin` builds an `Olfaction_Query` with
the observer's pose, its profile and a pointer to the field that only the host
holds. `perception.olfaction_sample` walks the whole reach box, classifies every
cell centre inside reach (`scent_cell_reach`: blind, zone, falloff), keeps
per-zone maxima and per-zone measurement counts, reduces each class to bands, a
coherence gated bearing and a freshness band, and numbers readings in the upper
half of the observation-ID space. The `Olfaction_Audit` returned beside the
sample (cells sampled, blind and excluded, raw peaks, newest ages of any level
and of detectable cells, coherence) stays in the receptor and reaches diagnostics
as `host_scent_audit`, outside the brain input.

### Coverage: what the nose actually measured

Every `Scent_Sample` carries sixteen `Scent_Coverage` words, one per zone, next
to the readings (Team Lead R3):

| Word | Meaning | How it arises |
| --- | --- | --- |
| `Unsampled` | Nothing in this zone was measured; the ground is unknown, not empty | No cell centre inside the zone was measurable: blind body disc, ground beyond the map or solid ground, or a reach too small for the tile size |
| `Partial` | Some cells were measured, others could not be | At least one measured cell and at least one excluded cell (solid or beyond the map) inside the zone |
| `Sampled` | Every cell centre inside the zone was measured | Measured cells and no excluded ones |

The gather loop deliberately walks the unclipped reach box, so cells beyond the
map count as excluded instead of silently vanishing. Coverage depends only on
the nose position, its reach, the tile size and the arena's media; scent never
changes it, and a zone can only hold a reading band when it is not `Unsampled`
(the readers enforce this). The host audit adds `cells_excluded`; the creature
only receives the three words at its own sixteen-zone resolution. That is the
nose's own sampling footprint, not an arena map: the worker still gets no field,
no media and no coordinates of anything but itself. The host test compares the
delivered words with an independent classification of the arena's cells, and the
review probe on 128-unit tiles with a 32-unit reach yields sixteen `Unsampled`
words and zero measured cells.

### Freshness from detectable cells only

A cell contributes to the zone maximum whenever it holds any scent, but it may
only set the freshness of a reading when it is detectable on its own: its level
scaled by the range falloff reaches `SCENT_WEAK_LEVEL` (Team Lead R2). The
reading's freshness band is the age of the newest such cell across all its
reported zones. A fresh trace too faint to be smelled therefore changes nothing,
not even the age, while a fresh trace that is itself at least Weak honestly makes
the reading recent and appears as a Weak zone. Mixed ages among detectable cells
resolve to the newest; mixed strengths do not matter for the age: an old Medium
trail plus a fresh detectable Weak trace reads **Medium, Very_Recent**, meaning
"some detectable part of this scent is this fresh", never "its source is here".
Receptors without `estimates_freshness` keep saying `Unknown`. The audit keeps
both the newest age of any trace and the newest detectable age so the debugger
can show the difference. Sampling the same old trail again yields a new sample
whose reading is still `Old`; the brain's `Scent_Memory` copies the band and only
its `observed_tick` moves.

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

The Olfaction page (`olfaction_readings.gd`, `olfaction_sensor_view.gd`) first
draws the sample's coverage and only then the readings: a `Sampled` zone gets the
faint "measured, no scent" fill, a `Partial` zone concentric stripes, an
`Unsampled` zone nothing at all, so it stays as dark as the background. The
reach ring is an outline only, the body's blind disc is drawn at its true size
(a 32-unit reach on 128-unit tiles is entirely inside it), and the legend and the
readings column say how many zones were measured fully, partly or not at all.
Because the sensor is zone based, the page cannot and does not draw a tiled
trail. Its status and display metrics use the scent delivery clock, separate
from vision's. `plot_geometry()` exposes the drawing geometry so the rendered
probes read pixels where the page really paints.

`senses.json` is schema 4, decision traces schema 5 and the replay envelope 5,
because the nose sample and the host audit grew. `trace_reader.gd` requires the
sixteen coverage words and the excluded-cell counts for schema 5 and rejects them
in schema 4 records; a schema-4 recording is still readable and its decision
debugger and replay lines say "coverage not recorded".

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

## Independent regressions

`tests/olfaction_review/` is Team Lead-owned and unchanged: the short diagonal
step, the undetectable fresh trace and the zero-coverage fixture, plus the
rendered `coverage_view_check.gd`. `tests/olfaction_coverage/` adds the coding
agent's fixtures (zero, partial and full coverage, a solid column) written from
the production sampler, and `coverage_render_check.gd` renders the real control
at 700 × 500 and at the 400 × 350 minimum page size, reading pixels inside every
zone band: unknown ground must be the background colour, measured empty ground
the faint fill, partly measured ground striped, and the legend must fit.
`make check_olfaction_review` runs all of it in normal and debug builds; both
Godot probes render, so the target and therefore `make check` need a display.
