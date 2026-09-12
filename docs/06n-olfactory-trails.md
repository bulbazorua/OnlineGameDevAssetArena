# Checkpoint 6B.2: olfactory trails, private sensing and live heatmaps

Implemented **2026-09-11** from the [original assignment](06q-olfaction-original-delegation.md)
and the [combat sensory contract](06j-combat-sensory-system.md); corrected on
**2026-09-12** for the [Team Lead review](06p-olfaction-team-lead-review.md)
findings R1–R3. The [delegation](delegation.md) is now closed. Status:
**Team Lead technical re-review passed on 2026-09-12; owner physical-input
acceptance remains pending.** The
[coding-agent report](06o-olfaction-coding-agent-report.md) lists changed files,
commands, measurements and evidence; the [deep dive](codebase/olfaction.md)
explains ownership and flow.

```sh
make dev_scent P1=archer P2=orc            # wide scent QA arena, six windows, F8 host heatmap
make dev_vision P1=archer P2=orc           # the existing close-quarters arena also has scent
make dev_scent P1=archer P2=orc DEV_QA_SENSES=--qa-senses=client/dev/fixtures/content/blind_tracker.senses.json
make check_scent                           # headless scent integration (runs check_olfaction_review first)
make check_olfaction_review                # Team Lead regressions + coverage probes; renders, needs a display
python3 tests/scent_check.py --graphical   # native windows and captures
```

The third command stages a **blind tracker** catalog: the shipped senses with the
Orc's eyes disabled, so its only working sense is its nose. The launcher stages it
into the private candidate like the QA arena; the authored catalog is untouched.
The integration harness uses it because a sighted Orc that has already found the
Archer rightly ignores smell, which made the live scenario timing-dependent.

## What a creature does now

Every summoned body leaves scent on the ground it stands on or crosses. The ground
keeps that scent after the body moves on, spreads it a little, and thins it with
simulation time. Each creature's nose samples the ground around it on its own
schedule and receives only anonymous class readings: **human** or **orc** scent,
a coarse strength, an uncertain age and a compass bearing when the sampled zones
agree. A creature can smell a trail long after the trainer or opponent that left
it has gone, investigate the general direction, lose the fading trail, search
locally and eventually resume exploring. It can follow the wrong human scent.
Once its own vision confirms an opponent, the existing pursuit, target-found
marker and surprise hop take over exactly as before; smell alone never
acquires a target.

| Source / receptor | Shipped setting |
| --- | --- |
| Archer (`human_senses`) | Emits human scent; nose reaches 5 gameplay units (160 world units), samples every 12 ticks, estimates freshness |
| Orc (`orc_senses`) | Emits orc scent; nose reaches 8 gameplay units (256 world units), samples every 12 ticks, estimates freshness |
| Trainers (`trainer_emitter`) | Emit human scent at full intensity; no trainer receptor |
| Circle, Square, Triangle (`fixture_senses`) | Geometric placeholders: no nose and no emission. A disabled receptor is reported as **Disabled**, never as an empty sample, and their search behaviour is unchanged from before this slice |
| Diamond (`scentless_sensor`) | Emits nothing; human-reach nose that reports freshness **unknown**. The scentless-body QA configuration |
| Lancer / Warrior | Not admitted by this slice; they would use `human_senses` |

Memory settings stay equal for every creature. A longer nose gives the Orc more
reach, not a better map or a longer memory.

## The scent field

`terrains.json` is now **schema 3**: every terrain names its scent medium
explicitly, independent of walking and sight.

| Medium | Terrains | Rule |
| --- | --- | --- |
| `open` | grass, ground, sand, stairs, tall grass | Holds and spreads scent; half of it is gone after 20 s |
| `water` | water | Carries scent but loses half every 2 s; a two-cell pool stops a trail, a single cell passes a faint trace |
| `solid` | stone, cliff, forest, building | Never holds scent; spread goes around it, never through it |

Outside the map is solid: the edge neither leaks nor adds scent. Elevation does
not enter the rules. The field has one concentration per arena cell and scent
class, capped at 1.0, plus the age of the newest deposit on that cell.

- Every live tick, each enabled emitter deposits `1.5 × intensity` per second,
  walked cell by cell along the segment from its previous confirmed position to
  the new one: each crossed cell receives the share of the path inside it, so
  even a one-unit diagonal step that clips a neighbouring cell paints it.
  Conventions: a point on a grid line belongs to the higher cell, a crossing
  exactly through a corner steps diagonally without touching the side cells, and
  a zero-length step deposits everything under the body. Standing still saturates
  one cell; walking across a 32-unit tile at creature speed leaves 0.75; a running
  trainer leaves about 0.2 per tile. A blocked step deposits where the body
  actually is, never on the attempted destination. Solid ground and ground beyond
  the map keep their share out of the field, so emission stays bounded.
- Emission starts when summoning completes. A jump longer than two tiles in one
  tick paints nothing, so reset placement and replacement never draw a trail.
- Every six ticks (10 Hz) the field steps: each open or water cell gives 0.3% to
  each open neighbour and decays by its medium's half-life. A cell under 0.001
  becomes empty again. Trail cells also bleed sideways, so a walked trail keeps
  roughly a fifth of its concentration after 15 s and stops being smellable after
  about 40 s; the faint halo beside it appears within a few seconds.
- Simulation time alone drives emission and steps. Rendering, connections,
  polling and paused replay cannot touch the field.

## The nose

A receptor samples the field on its own schedule from the frozen world phase
that also feeds vision. Cells closer than three quarters of a tile are the body's
own and are skipped; solid cells hold nothing; every other cell inside the range
falls into one of sixteen zones: eight compass sectors (north first, clockwise)
times a near band (inside half the range) and a far band. A zone keeps the
strongest concentration it saw, scaled from 100% at the nose to 40% at the range
edge. The delivered reading per class present is:

| Field | Meaning |
| --- | --- |
| `strength` | Weak ≥ 0.03, Medium ≥ 0.15, Strong ≥ 0.45 of the scaled peak |
| `freshness` | Very recent < 3 s, Recent < 15 s, Old, from the newest deposit among the cells that are **detectable on their own** (scaled level at least the weak band). A fresh trace too faint to smell changes nothing, not even the age; mixed ages resolve to the newest detectable cell, so an old Medium trail plus a fresh detectable Weak trace reads Medium and Very recent. **Unknown** when the receptor does not estimate age |
| `bearing`, `bearing_valid` | Weighted pull of the zones; valid only when at least 35% of the pull agrees. Scent all around the nose is presence with no usable direction |
| `zones` | The sixteen bands, the sensor's own resolution |
| `coverage` (per sample) | Sixteen words, one per zone: **Sampled** (every cell centre in reach was measured), **Partial** (some ground in the zone was solid or beyond the map and stayed unknown), **Unsampled** (nothing measured: blind body disc, edge, walls or a reach too small for the tile). A zone can only hold scent when it was measured |
| `observation_id` | Identifies the observation. Scent IDs live in the upper half of the 32-bit space so they never collide with vision IDs |

A `Scent_Sample` carries the observer, round, sample tick, delivery tick, the
nose position, the profile, the coverage words and a status: **Disabled**,
**Waiting for summon** or **Sampled**, with **Unsupported** reserved. A sample
that did not happen has every zone **Unsampled**. Coverage is the nose's own
sampling footprint at its sixteen-zone resolution; the creature still receives
no field, no media and no coordinates of anything but itself. No emitter
identity, owner, faction, hostility, coordinate, action, velocity, count or
route is delivered.
Two humans blend into one human reading. Retained samples keep their original
time; a fresh empty sample clears current detection.

## Private interpretation and search

The brain ingests each new nose sample once into a per-class `Scent_Memory`
entry that keeps its sample time, expires after three seconds, and is never
refreshed by re-reading the same sample. The searcher then explains away its own
trail: it knows what its own body gives off, so a same-class zone that points at
ground it visited within the last 20 s is discounted, and the remaining zones
decide strength and bearing again. A scentless body discounts nothing. The
strongest, then freshest, surviving class wins. Limits: a creature standing
where another same-class body just stood cannot tell them apart; once its own
visit memory ages past 20 s it may briefly investigate its own old trail, which
the existing 8-second budget and 15-second cooldown then abandon. Permanent
self-chasing does not occur; temporary false leads do, by design.

| Evidence | Behavior |
| --- | --- |
| Directional scent | **Investigate** (`Scent_Trail`): the coarse bearing biases heading scores with weight 3 × confidence (Weak 0.2, Medium 0.3, Strong 0.4, old traces × 0.7). Re-steering happens at a leg end or a change of at least two sectors, never for one-sector wobble |
| Scent without a bearing | **Intensive search** (`Scent_Presence`) around the nose position, with the existing growing radius |
| Trail weakens or vanishes | Retained memory ages out, then `Scent_Faded` hands over to the local-search budget, then extensive exploration resumes |
| Current or briefly remembered visual cue | Outranks any smell while it lasts; the remembered smell takes over afterwards, keeping its own provenance (`Scent` / `Scent_Memory`) |
| Focused opponent sighting | Existing acquisition and pursuit; smell never sets the public target flag, the marker or the hop, and never moves a last-seen visual fix |
| Repeated weak evidence | One shared episode budget for cues and smells: eight seconds without an opponent ends it, then weak evidence is ignored for fifteen seconds |

Trace nodes record every candidate reading, the discounted zone count, the
selected observation and the transition, so the decision debugger can show
which smell drove a change and what was rejected.

## Inspectors and the host heatmap

Both **Senses** windows now have a live **Olfaction** page: the nose at its
sampled position, the reach as an outline ring, and every zone drawn by what the
nose measured there: a faint fill for measured ground without scent, concentric
stripes for partly measured ground, and nothing at all (dark, like unknown
ground) for unmeasured zones; the body's blind disc is drawn at its true size.
Scent wedges (amber human, green orc, opacity by band) are painted only over
measured ground, a bearing arrow appears when valid, the legend and the readings
column count measured, partly measured and unknown zones, and a table lists
class, strength, freshness and bearing. An empty sample therefore never implies
that the whole reach was measured: a 32-unit reach on 128-unit tiles shows a
dark disc and "No ground was measured". Nothing is interpolated into a tiled
trail. The page has its own LIVE / STALE / DISCONNECTED / WAITING / DISABLED
status and its own delivery clock, so a fresh eye sample never makes an old
smell look current. A paused decision debugger does not pause it. The page
holds no logs, traces or replay controls.

The page's canvas has two views behind one control: **Local sensor** is the
nose picture above, and **Arena overview** (the default) is the shared whole-
arena frame with the host's published scent field drawn on it, titled **HOST
SCENT FIELD · developer-only world data, not what this creature knows**. It
shows the wake behind a moving emitter exactly as published (class colours on a
fixed level scale, never per-frame normalised), the nose's sampled reach ring
labelled with its sample number, and a readout for the hovered cell; clicking a
cell pins its per-class level (0–255 of saturation) and age (whole seconds since
the newest deposit, capped at 255) under the reading details. The field has its
own reader, throttle and LIVE / STALE / DISCONNECTED / WAITING badge, separate
from the nose sample's clock, and a field for another round, map or size is
never drawn. Its class filters are page-local and save nothing. The same
`scent_field_image.gd` painter builds the F8 heatmap and this minimap, so both
show the same cells. See [the shared frames](codebase/dev-arena-overview.md).

The arena's **F4** panel gains a **Senses · Olfaction** group: **Host scent
field [F8]**, Human scent, Orc scent, Smell range P1 and Smell range P2. The
heatmap draws the actual published field as one pixel per cell under the
actors at restrained opacity, labelled **HOST SCENT FIELD · privileged world
data** with the field tick and a STALE marker. Range circles come from the same
live feed the senses windows use. These settings are saved per player window in
`user://dev/scent-p1.cfg` / `scent-p2.cfg` beside the existing F6 setting and
restore on the next launch; automated checks use their own directory.
Diagnostic toggles never change gameplay.

## Recording and replay

Trace schema **5** records the consumed nose sample with its coverage, the
private scent memory before and after, the scent evidence the searcher acted on,
the emitter the body knows it has, and a separately labelled host olfaction
audit (cells sampled, blind and excluded, peaks, newest ages of any and of
detectable traces, coherence). Replay envelope **5** carries it; `senses.json`
is schema **4**. The AI window and the replay window show the nose sample line
with its measured / partly / unknown zone counts beside the eye sample; schema-4
records say coverage was not recorded, schema-3 and older records say olfaction
was not recorded. The full host field is not recorded: replay marks it unavailable
and never reads the live field for an old frame. Public packets are unchanged
(protocol 11); audiences receive no scent data.

## Reset, replacement and bounds

A new round, map change or **F7** reset clears the field and both private
olfactory states; emitters re-arm at their placements without painting. Replacing
one creature resets only its receptor, emitter record and mind; the other keeps
its schedule and memory, and old deposits stay on the ground to fade naturally.
Switching an emitter off stops new deposits, not old decay.

| Bound | Value |
| --- | --- |
| Field storage | Fixed: 128 × 128 cells × 2 classes, 213 KB inside the battle runtime, no tick allocations |
| Field step | Inside the box holding scent; worst accepted case (saturated 128 × 128) ≈ 2.4 ms every 100 ms |
| Nose sample | Cells within range, at most the map; worst case (1,024-unit reach) ≈ 1.5 ms every 200 ms per creature |
| Readings / memory | At most one per class (two) per sample and per creature |
| Trace record | Worst case 41,232 bytes under the unchanged 48 KiB ceiling (coverage words and audit counts added 301 bytes) |
| `senses.json` | Schema 4, still 32 KiB |
| Nose sample | Walks the whole reach box, including ground beyond the map, so coverage is known: at most (2 × reach / tile + 1)² cells, 16,641 for the widest accepted profile; worst case ≈ 2.0 ms every 200 ms per creature |
| `search.json` | Schema 2, still 32 KiB |
| `scent.json` | Schema 1, 96 KiB cap, 10 Hz, quantized levels and ages per class |

## Verification

```sh
make check_perception check_ai check_session       # 17 / 18 / 61 tests
odin test server -debug -extra-linker-flags:"-L$PWD/build/deps"
make check_vision_review                           # unchanged Team Lead guarantees
make check_olfaction_review                        # Team Lead R1–R3 regressions and the coverage fixtures, normal and debug, plus two rendered probes
make check_senses_windows                          # Olfaction page, delivery clocks, fixtures, staleness
make check_scent                                   # real trail, orc-only reading, smell-driven search, heatmap, F8/F6 persistence, F7, replay
python3 tests/scent_check.py --graphical
python3 tests/senses_windows_check.py --graphical
make check
```

Perception tests compare the deposit walk with a dense point oracle across the
16-, 32-, 64- and 128-unit tile sizes (both directions of the review's diagonal,
corners, grid lines, standing still, solid ground and the map edge), check that
freshness follows detectable cells only for both classes at the threshold, and
check coverage for zero, partial, edge, wall and full cases. Host tests cover
trail persistence and fading, teleport-free reset, terrain media, Orc versus
human reach, scentless bodies, hidden-emitter invariance behind a wall,
one-creature replacement, dedicated-worker equivalence, the worst-case record
ceiling, the bounded field capture, and that the delivered coverage equals an
independent classification of the arena's cells and reaches the journal,
snapshot and live senses file while the audit stays outside the brain input. AI tests cover
once-only ingestion, retention, investigation, presence, fading, abandonment,
cooldown, cue precedence, no acquisition and self-trail discounting. The integration harness drives a real trainer trail with synthetic keys and checks
the orc's live reading, its recorded search decision, the drawn heatmap against
the published field, saved filters across a restart, the reset round, the
recording, and that the orc's wide nose on the small arena reports measured and
unmeasured zones with scent only on measured ground. The senses-window harness
publishes zero-coverage, partial-coverage and invalid (scent in an unmeasured
zone) fixtures to the real page and checks what it shows and refuses. Results and measurements are in the coding-agent report. Physical
keyboard and mouse acceptance remains manual.

## Manual QA steps

1. `make dev_scent P1=archer P2=orc`. Press **F8** in the P1 window and open
   **F4**: the host heatmap shows saturated cells under the standing bodies.
2. Hold **Space + D** to run P1's trainer east toward the Orc, then walk back.
   The heatmap shows the trail, stronger where you walked slowly, and a faint
   halo growing beside it.
3. In the P2 senses window select **Olfaction**: a human reading appears with a
   bearing toward the trail while the trainer is already far away. The P2 AI
   window's **Search** tab shows `Scent` evidence and a `Scent_Trail` transition.
4. Wait about 40 s without moving: the reading weakens and disappears; the
   heatmap fades; the Orc abandons and explores again.
5. Press **F7**: the field and both Olfaction pages clear; nothing paints a
   line to the new placements. Restart the launcher: F8 and the class filters
   return as saved; F6 settings are untouched.
