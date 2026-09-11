# Checkpoint 6B.2: olfactory trails, private sensing and live heatmaps

Implemented **2026-09-11** from the [active assignment](delegation.md) and the
[combat sensory contract](06j-combat-sensory-system.md). Status: **coding-agent
candidate, not yet Team Lead-reviewed or owner-accepted.** The
[coding-agent report](06o-olfaction-coding-agent-report.md) lists changed files,
commands, measurements and evidence; the [deep dive](codebase/olfaction.md)
explains ownership and flow.

```sh
make dev_scent P1=archer P2=orc            # wide scent QA arena, six windows, F8 host heatmap
make dev_vision P1=archer P2=orc           # the existing close-quarters arena also has scent
make dev_scent P1=archer P2=orc DEV_QA_SENSES=--qa-senses=client/dev/fixtures/content/blind_tracker.senses.json
make check_scent                           # headless scent integration
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
  shared over the cells its confirmed movement crossed since the previous tick.
  Standing still saturates one cell; walking across a 32-unit tile at creature
  speed leaves 0.75; a running trainer leaves about 0.2 per tile. A blocked step
  deposits where the body actually is, never on the attempted destination.
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
| `freshness` | Very recent < 3 s, Recent < 15 s, Old, from the newest deposit among the sampled cells; **Unknown** when the receptor does not estimate age or nothing is present |
| `bearing`, `bearing_valid` | Weighted pull of the zones; valid only when at least 35% of the pull agrees. Scent all around the nose is presence with no usable direction |
| `zones` | The sixteen bands, the sensor's own resolution |
| `observation_id` | Identifies the observation. Scent IDs live in the upper half of the 32-bit space so they never collide with vision IDs |

A `Scent_Sample` carries the observer, round, sample tick, delivery tick, the
nose position, the profile and a status: **Disabled**, **Waiting for summon**
or **Sampled**, with **Unsupported** reserved. No emitter identity, owner,
faction, hostility, coordinate, action, velocity, count or route is delivered.
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
sampled position, sixteen zones per class drawn as wedges at the sensor's own
resolution (amber human, green orc, opacity by band), the range ring, the dark
blind disc, a faint ring for sampled-but-empty ground, a bearing arrow when
valid, and a table with class, strength, freshness and bearing. Dark means not
sampled; nothing is interpolated into a tiled trail. The page has its own
LIVE / STALE / DISCONNECTED / WAITING / DISABLED status and its own delivery
clock, so a fresh eye sample never makes an old smell look current. A paused
decision debugger does not pause it. The page holds no logs, traces or replay
controls.

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

Trace schema **4** records the consumed nose sample, the private scent memory
before and after, the scent evidence the searcher acted on, the emitter the
body knows it has, and a separately labelled host olfaction audit. Replay
envelope **4** carries it. The AI window and the replay window show the nose
sample line beside the eye sample; schema-3 and older records say olfaction was
not recorded. The full host field is not recorded: replay marks it unavailable
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
| Trace record | Worst case 40,931 bytes under the unchanged 48 KiB ceiling |
| `senses.json` | Schema 3, still 32 KiB |
| `search.json` | Schema 2, still 32 KiB |
| `scent.json` | Schema 1, 96 KiB cap, 10 Hz, quantized levels and ages per class |

## Verification

```sh
make check_perception check_ai check_session       # 14 / 17 / 60 tests
odin test server -debug -extra-linker-flags:"-L$PWD/build/deps"
make check_vision_review                           # unchanged Team Lead guarantees
make check_senses_windows                          # Olfaction page, delivery clocks, fixtures, staleness
make check_scent                                   # real trail, orc-only reading, smell-driven search, heatmap, F8/F6 persistence, F7, replay
python3 tests/scent_check.py --graphical
python3 tests/senses_windows_check.py --graphical
make check
```

Host tests cover trail persistence and fading, teleport-free reset, terrain
media, Orc versus human reach, scentless bodies, hidden-emitter invariance
behind a wall, one-creature replacement, dedicated-worker equivalence, the
worst-case record ceiling and the bounded field capture. AI tests cover
once-only ingestion, retention, investigation, presence, fading, abandonment,
cooldown, cue precedence, no acquisition and self-trail discounting. The
integration harness drives a real trainer trail with synthetic keys and checks
the orc's live reading, its recorded search decision, the drawn heatmap against
the published field, saved filters across a restart, the reset round and the
recording. Results and measurements are in the coding-agent report. Physical
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
