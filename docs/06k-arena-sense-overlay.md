# Arena vision cones and independent sense filters

Implemented **2026-09-11** at the owner's request. This delivers the arena-overlay
part of **6B.1.1**. The subsequent [live senses windows](06l-live-senses-windows.md)
complete the presentation slice; the original evidence below remains dated to this overlay change.

## Try it

```sh
make dev_vision P1=archer P2=orc
make dev_arena P1=archer P2=orc ARENA=tiny_swords_village
```

Vision appears by default once each creature has a delivered eye sample. Cyan
shows focused vision; amber shows peripheral vision. Both use thin wireframe
outlines at **20% opacity**, with no filled area or dark border. Each field uses the sampled
position and facing, with a label identifying its owner and sample age.

- **F4 / Filters:** the **Senses · Perception** group appears first. It contains
  Vision cones, Focused vision, Peripheral vision and independent Character P1/P2
  controls. The **Physical colliders** group is separate below it.
- **F5 / Vision cones:** hide/show vision while retaining the sense filters.
- **F3 / Colliders:** hide/show physical collision drawings. All colliders and
  None affect physical filters only.
- Settings belong to the current client window. Closing Filters keeps the cones
  visible. The list scrolls within a bounded panel at the minimum window size.

The overlay creates no physics bodies. Changing a filter does not change a
creature's senses, actions, movement or sampling schedule. A separate
**Senses · Olfaction** group holds the **F8** host scent heatmap and its class
and smell-range filters, saved per window ([olfactory trails](06n-olfactory-trails.md)).
Hearing, touch and pain are listed as not implemented.

## Evidence and limits

The host log writer publishes a small `senses.json` beside its existing local AI
traces. This contains each creature's latest delivered vision sample and the
same clipped display fan used by the decision debugger. It contains no decision
tree, memory, host audit or rejected-candidate list. Ordinary network packets
are unchanged. The player overlay never queries the map to reconstruct vision.

Cone outlines stop at the host's sampled cover boundaries. Water does
not block sight; opaque terrain does. The 65-ray fan remains a diagnostic
approximation, while actual subject visibility uses the existing exact tests.
The arena displays coverage only; current detection lists now live in the
[dedicated senses windows](06l-live-senses-windows.md).

Snapshots are bounded to 32 KiB and replace the previous file. The writer targets
50 ms publication intervals plus fresh-sample publication after the live-window
extension; the arena polls every 100 ms. Existing writer work
can delay publication, so this is not a guaranteed 10 Hz display or a claim that
the whole 6B.1.1 latency target is met. Readings retain their sampled pose instead
of following newer client animation. Labels show sample age; stalled sensory or
world feeds dim the cones and display **STALE**.

Identity checks bind a reading to its run, content fingerprint, map, round,
owner, entity and definition. Readings delivered after the client's world tick
are withheld. Returning to the lobby clears drawn readings. Audience windows
explicitly show senses as unavailable; they never borrow the players' live feed.

This requires local telemetry, enabled by default with `AI_DEBUG=1`. Disabling
both `AI_DEBUG` and `SENSE_DEBUG`, or using ordinary
`DEV=1` clients without the local telemetry binding show an unavailable message.
Normal clients and release exports have no sense overlay. The private files stay
inside the existing ignored/pruned development directories.

## Verification

```sh
make check_sense_overlay
make check_collision_overlay
godot --path client --script "$PWD/tests/sense_overlay_check.gd" -- --server="$PWD/build/sense_debug_server" --dev
python3 tests/ai_debugger_check.py --graphical
make check
```

The sense-overlay check uses a real host, two clients and a delayed audience. It
checks default visibility, independent mouse/key filters, all eight facings,
non-aligned focus boundaries, fully blocked coverage, sampled pose/range,
stale-feed recovery, audience exclusion, malformed/cross-run evidence, minimum
window layout and lobby cleanup. Existing physical collider checks still run.
The launcher/debugger integration checks that both real arena windows receive
cones and that the lightweight feed exactly matches recorded eye samples/fans.

Final verification on **2026-09-11**: full `make check` **exit 0**, graphical
overlay check **exit 0**, and native launcher/debugger integration **exit 0**.
The unchanged Team Lead vision regressions also pass through the full suite.

Pinned logs and copies of inspected captures are in
`build/verification/arena-senses-implementation/`: `full-check.log`,
`overlay-graphical-final.log`, `debugger-graphical.log`, `arena-vision-cones.png`
and `senses-filters.png`. The native graphical run is
`build/verification/ai-debugger-20260911-050740-220297/`; the standalone overlay
check's captures are in `build/verification/sense-overlay-219811/`.
The latter measured 219 µs for its final local read of a 5,924-byte snapshot.
Input in these checks is synthetic; physical keyboard/mouse acceptance remains
with the owner. These are implementation checks, not an independent review of
the new overlay by another coding agent.

The later wireframe appearance change passed the Godot script check and graphical
overlay check, both exit 0. Its inspected capture is `arena-vision-wireframe.png`
in the pinned log directory; the full suite above predates this visual-only change.

The [implementation deep dive](codebase/arena-sense-overlay.md) describes ownership
and the path from the existing writer to the arena. The [live-window record](06l-live-senses-windows.md)
covers the completed companion-window extension.
