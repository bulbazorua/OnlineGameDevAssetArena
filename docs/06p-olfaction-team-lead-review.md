# 6B.2 Team Lead review

Reviewed **2026-09-11**, against the uncommitted candidate described in
[the coding-agent report](06o-olfaction-coding-agent-report.md).

**Decision: corrections required. R1–R3 remain open.** Existing suites and a
fresh graphical scent integration pass, but independent probes reproduce two
sensor/field errors and one rendered coverage error. This is not acceptance of
6B.2. The [active delegation](delegation.md) assigns the corrections; the
[original assignment](06q-olfaction-original-delegation.md) preserves the scope.

## Findings

### R1 — P2: short diagonal movement skips ground actually crossed

Location: [scent_field.odin](../server/perception/scent_field.odin#L110).

On a 32-unit grid, move from `(63.8, 63.5)` to `(64.55, 64.25)`.
This is only about 1.06 units, within a normal creature's single movement step.
The segment enters the interior of cell `(2, 1)` before reaching `(2, 2)`.
After the starting cell is seeded, the production deposition call paints the
destination but leaves the intermediate cell at exactly zero. Reversing the
movement reproduces the omission; the opposite corner cell correctly stays empty.

Point samples spaced half a tile apart do not guarantee every crossed cell is
covered. Trails can therefore have gaps even during ordinary walking, contrary
to the continuous crossed-tile contract. Later diffusion does not repair the
missing movement deposit at the time it should exist.

Acceptance: confirmed movement covers the traversed ground under one documented
edge/corner convention in either direction, without painting untouched cells.
Keep emission bounded and preserve blocked-step, teleport, solid-cell and
simulation-time behavior. Verify short diagonal steps as well as fast running.

### R2 — P2: undetectable fresh scent makes a detectable old trail look new

Location: [olfaction.odin](../server/perception/olfaction.odin#L108).

With a nose at `(112, 112)`, range 160 and 32-unit tiles, an old human deposit
of `0.4` at cell `(5, 3)`, aged 200 field steps, reads **Old**. A fresh `0.005`
deposit at `(3, 5)` alone yields no detection. Add that faint deposit to the old
trail: the detected zones, strength and bearing remain identical, but freshness
becomes **Very_Recent**.

The age reduction considers every positive concentration, including cells whose
contribution is below detection. A faint fresh trace in another zone can thus
make old, stronger evidence look fresh. This changes information delivered to
the brain and can change evidence selection; it is not an emitter-ID leak.

Acceptance: estimated freshness describes the detectable evidence supporting
the reading. An otherwise undetectable trace must not independently rejuvenate
it. Preserve meaningful old/recent distinctions and honest Unknown results for
receptors that cannot estimate freshness. Mixed trails need documented behavior.

### R3 — P2: the senses panel labels unsampled space as sampled absence

Locations: [olfaction_sensor_view.gd](../client/dev/senses/olfaction_sensor_view.gd#L32)
and its [sampled-area rendering](../client/dev/senses/olfaction_sensor_view.gd#L54).

Accepted content permits 128-unit tiles and a 32-unit nose range. The production
sensor's blind radius is 96 units, so a nose at `(448, 448)` on the review map
samples **zero cells**. Its sample is current and contains zero readings.
The actual Godot control nevertheless draws a faint outer annulus and labels it
**sampled, no scent**. The renderer caps the blind disc at half the displayed range.

The attached rendered probe records a dark center (`0c1420`) and a different
outer fill (`18293a`) despite zero sampled cells. The same unconditional ring
also treats directions beyond map edges as measured absence. In the independent
native P2 capture, the nose is about 77 units from the north edge with 256-unit
reach, yet the whole northern extent is presented as sampled.

Acceptance: distinguish actual sampled coverage, undetected scent within that
coverage, and unknown space at the observation's coarse resolution. Handle
blind regions, map limits, solid/excluded areas, partial zones and accepted
range/tile combinations. A zero-reading sample does not prove the whole range
was measured. Preserve this meaning through live exports and recorded evidence
without supplying the brain a world map or source locations. Merely reducing
the range circle or relabeling all empty regions is insufficient.

## Independent verification

Pinned evidence: `build/verification/olfaction-review-20260911/`.
The `initial-failures/` subdirectory preserves the original failing logs,
production-generated fixture, rendered panel and pixel results. Source copies
and SHA-256 fingerprints identify the reviewed version.

| Check run by Team Lead | Result |
| --- | --- |
| `odin test server/perception`, normal and `-debug` | Exit 0; 14 tests each |
| `odin test server/ai`, normal and `-debug` | Exit 0; 17 tests each |
| `odin test server`, normal and `-debug`, repository ENet link flags | Exit 0; 60 tests each |
| `make check_vision_review` | Exit 0; 3 + 3 tests; source byte-identical to the pre-olfaction snapshot |
| `odin test tests/olfaction_review`, normal and `-debug` | Exit 1 in both; R1 and R2 fail, zero-coverage fixture test passes |
| Graphical `coverage_view_check.gd` | Exit 1; R3 reproduced in the actual rendered control |
| `python3 tests/scent_check.py --graphical` | Exit 0; native six-window run, live trail/search, saved filters, reset and recorded olfaction replay |

The graphical integration sandbox is
`build/verification/scent-20260911-115030-667811/`, also pinned. Copies of the
two native Olfaction captures, host heatmap and six-window manifest are in
`live-captures/`. The Team Lead inspected the Orc page, host heatmap and the
separate zero-coverage rendered probe. The existing integration compares field
cell counts and delivered values; its success alone does not prove correct
coverage rendering, as R3 demonstrates.

Reproduce the new probes from the repository root:

```sh
mkdir -p build/verification/olfaction-review-20260911
odin test tests/olfaction_review -out:build/olfaction_review_tests
odin test tests/olfaction_review -debug -out:build/olfaction_review_tests_debug
godot --path client --script ../tests/olfaction_review/coverage_view_check.gd
```

Run each command even while earlier probes fail. The Odin fixture test writes
the sample consumed by the graphical probe. The latter requires a display;
headless execution cannot validate its rendering. Preserve `initial-failures/`
when capturing a corrected run.

The supplied finished-tree `full-check-final.log` ends with `exit=0`; the Team
Lead inspected it but did **not** rerun the full suite after finding these
failures. The next candidate needs a final full check including these regression
guarantees. All review input was synthetic; physical input and exported release
acceptance were not exercised.

## Architecture and deviations

The reviewed ownership direction fits the roadmap: environmental deposits live
on the host; independently scheduled receptors produce anonymous value samples;
workers receive their own copied inputs and memory. Smell evidence enters the
existing search controller and cannot confirm a visual target. Vision and nose
clocks remain distinct. These boundaries should survive the corrections.

| Deviation | Review disposition |
| --- | --- |
| Read rotated journal segments in existing harnesses | Appropriate. Preserve this fix, but restore the exact serialized byte-ceiling assertion: `ai_debugger_check.py:153` now checks re-encoded JSON against `record_limit_bytes + 1024`. Rotation does not require extra tolerance. No actual oversized production record was observed. |
| Inert placeholder shapes; scentless Diamond with a receptor | Acceptable explicit fixture capabilities. The original scope allowed authored shape settings, and the old vision harness is unchanged. Future work should remove its incidental dependence on a search trajectory without weakening the lifecycle assertion. |
| Blind-tracker catalog through `--qa-senses` | Appropriate isolated smell-only QA. Keep ordinary vision precedence tested with the normal capabilities too. |
| Publish fresh records between history snapshots | Reasonable bounded responsiveness change. The reported latency figures remain the coding agent's measurements; this review reran the scent scenario, not the separate latency profiler. |
| Sector-based local view; full host field unavailable in replay | Fits the information contract, provided coverage and unavailable states are honest. R3 still needs correction. |

The required peak-memory measurement is missing from both baseline and candidate
columns. A fixed 213 KB field does not measure peak process memory with six
windows, recording, histories and publication buffers. Supply a reproducible
measurement and state what it includes. Likewise, the field-size assertion is
not a dedicated proof of zero allocations per tick; label the evidence accurately.

The reported 46–51-second recording limit and worst-envelope field/sample costs
are documented growth limits, not additional correctness findings. Keep them
visible when measuring the corrected candidate; do not silently raise caps.

## Review changes and handback

The Team Lead added `tests/olfaction_review/`, this review, the archived original
assignment and the correction packet, and updated roadmap status. No runtime
implementation or existing regression harness was changed. Nothing was staged
or committed. The coding agent owns the corrective implementation and returns
an updated report for independent re-review.
