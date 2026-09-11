# 6B.2 Team Lead review

Initial review: **2026-09-11**. Correction re-review: **2026-09-12**, against the
finished working tree described in [the coding-agent report](06o-olfaction-coding-agent-report.md).
The owner's `333bd1b` commit already includes the host corrections; the remaining
candidate changes are uncommitted. Both were included in this review.

**Current decision: 6B.2 passes Team Lead technical re-review. R1–R3 are closed.**
The original independent probes, expanded coverage checks, full `make check` and
fresh graphical scent, senses and debugger integrations pass. No blocking finding
remains in the correction scope. Physical keyboard/mouse and exported-release
acceptance were not exercised.

[Delegation.md](delegation.md) now closes this assignment. It does not assign the
next sense. The [original scope](06q-olfaction-original-delegation.md) and the
historical findings below remain available for reference.

## Correction disposition

| Item | Re-review result |
| --- | --- |
| R1: crossed ground | Closed. Cell traversal assigns emission by the portion of the path inside each cell. Both original diagonal directions pass; the neighboring untouched cell stays empty. The documented edge/corner cases and 600 additional path comparisons across four tile sizes pass. |
| R2: detectable freshness | Closed. Only independently detectable cells contribute to the reported freshness. Both classes pass near-threshold and mixed-age cases; a new sample of an old trail remains old in private memory/evidence. The undetectable control no longer rejuvenates the reading. |
| R3: measured coverage | Closed. Sixteen coarse coverage values distinguish Unsampled, Partial and Sampled. The real control renders zero coverage as unknown, partial zones with stripes and measured absence with a faint fill. Native pages and both tested control sizes were inspected. |
| Harness integrity | Original files in `tests/vision_review/` and `tests/olfaction_review/` match the preserved first-review copies. Their assertions were not weakened. |
| Serialized byte ceiling | Restored. The journal check measures the actual serialized bytes across rotated segments against the declared ceiling, without the extra 1,024-byte allowance. |
| Memory evidence | Supplied. The measurement script, both raw reports and preserved pre-olfaction tree were inspected; the sums reconcile. Qualifications are recorded below. |

The host still owns the physical field and measurement logic. Workers receive
private copied samples and memory; coverage adds no source identity, field,
terrain map or host audit. Vision and olfaction retain independent clocks and
the existing search/action authority. Smell does not acquire a visual target.

## Independent re-review evidence

Pinned evidence root:
`build/verification/olfaction-team-lead-rereview-20260912/`.
It includes logs, captures, source fingerprints, the previous review/assignment,
and a check using an actual recording from the first candidate. The initial
failure evidence remains under `olfaction-review-20260911/initial-failures/`.

| Command/check run by Team Lead | Result |
| --- | --- |
| `make check_olfaction_review` | Exit 0: original 3 + 3 tests, added 4 + 4 coverage tests and both graphical probes |
| `make check` | Exit 0: 42 PASS checks; includes normal perception/AI/host suites (17 / 18 / 61), debug host suite, original vision review and headless integrations |
| `odin test server/perception -debug` | Exit 0: 17 tests |
| `odin test server/ai -debug` | Exit 0: 18 tests |
| `python3 tests/scent_check.py --graphical` | Exit 0: real trail and private search, both native Olfaction pages, saved settings, reset and recorded replay |
| `python3 tests/senses_windows_check.py --graphical` | Exit 0: six native windows, coverage fixtures, latency, independent pause/close, stale states, reload and lifecycle |
| `python3 tests/ai_debugger_check.py --graphical` | Exit 0: current schema, strict journal ceiling, decision inspection and recorded playback |
| Actual historical replay | Exit 0: current reader decodes 1,725 frames from the first candidate's schema-4 recording; seeking retains original scent data and the display helper reports coverage not recorded |
| Source checks | Reviewed source fingerprints remain unchanged through verification; `git diff --check` passes; inspected correction sources have no consecutive comment groups over three lines |

The historical check uses the recording's own fingerprint to test decoding and
seeking. It does not claim asset migration across different content catalogs.
Public protocol remains 11, authored senses content remains schema 2, live senses
diagnostics are schema 4, and decision traces/replay envelopes are schema 5.

Full graphical sandboxes are pinned separately; copied captures and `SOURCE.txt`
files under the evidence root identify their originals:

- `scent-20260912-005310-98665/`: both live Olfaction pages and host field.
- `senses-windows-20260912-005444-102608/`: native pages, minimum-size fixtures
  and `performance.json`.
- `ai-debugger-20260912-005621-110376/`: graphical decisions and replay.

The native Orc capture shows **6 fully measured, 6 partial and 4 unknown zones**,
including dark northern space beyond the map. The Archer independently shows
**13 fully measured and 3 partial zones**. These are separate delivered samples,
not projections of the other creature's knowledge.

| Live page | Displays | Delivery p50 | p95 | Maximum |
| --- | --- | --- | --- | --- |
| Vision P1 | 80 | 45.4 ms | 111.6 ms | 112.5 ms |
| Vision P2 | 82 | 45.3 ms | 94.5 ms | 112.7 ms |
| Olfaction P1 | 61 | 45.4 ms | 79.4 ms | 196.0 ms |
| Olfaction P2 | 60 | 45.3 ms | 78.8 ms | 111.7 ms |

All p95 values meet the 150 ms target at normal sensor rates. Clock errors and
host queue drops were zero. One P1 nose display took 196 ms; the target is a p95
limit, not a guarantee for every update. Some other headless full-suite work ran
alongside this measurement. All automated input was synthetic.

## Measurement qualifications and remaining limits

The coding agent's 60-second memory runs report summed process high-water marks
of **2,525.2 MiB before olfaction** and **2,875.4 MiB with the corrected feature**.
The two AI windows account for about 1,009.6 and 1,004.6 MiB in the latter run.
These are sums of per-process peaks, not a simultaneous whole-machine peak;
shared resident pages can appear in several processes. PSS is also supplied.
This re-review audited those measurements but did not rerun the memory experiment.

Both saved recordings end with `size_limit`: the corrected run saved 2,773 of
4,164 captured frames, and the baseline saved 3,445 of 4,176. Thus the measurement
started with recording enabled and includes time after the cap stopped saving
frames. It should not be described as 60 seconds of continuous disk recording.
The roughly 48-second recording limit and the debugger's large retained-history
memory remain development-tool limits to address before growing diagnostics.

One cost-table wording correction: the widest centered sample visits 16,641
candidate cell centers, of which 11,047 are measured. The remaining 5,594 are
3,749 outside the circle, 1,841 solid and 4 blind; none are off-map in that specific
benchmark. Off-map coverage is tested in the edge fixtures. This corrects the
report's description, not the algorithm or measured sample duration.

Coverage remains intentionally coarse, and freshness remains one band per scent
class. Full-field historical replay is unavailable. `make check` now needs a
display because it includes two rendered probes; a displayless runner needs an
appropriate graphical test environment. These disclosed limits do not reopen
R1–R3.

For owner QA, use `make dev_scent P1=archer P2=orc`, select **Olfaction** in each
Senses window and use **F8** for the separate host field. The implementation
record contains the blind-tracker option for isolating smell from vision.

Only review/status documents and ignored verification artifacts were changed by
the Team Lead in this re-review. Runtime code and the original review harnesses
were not modified. Nothing was staged or committed.

## Initial findings — historical, now resolved

Everything below records the rejected first candidate on 2026-09-11. Its failures
and missing measurements are historical; the disposition above is current.

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

## Initial independent verification — historical

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

## Initial architecture assessment — historical

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

## Initial review changes and handback — historical

The Team Lead added `tests/olfaction_review/`, this review, the archived original
assignment and the correction packet, and updated roadmap status. No runtime
implementation or existing regression harness was changed. Nothing was staged
or committed. The coding agent owns the corrective implementation and returns
an updated report for independent re-review.
