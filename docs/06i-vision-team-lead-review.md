# 6B.1 Team Lead review

Initial review and correction re-review: **2026-09-11**, against the uncommitted
candidate described in [the coding-agent report](06h-vision-coding-agent-report.md).

**Current decision: 6B.1 passes Team Lead technical re-review. R1–R3 are closed.**
The unchanged independent regression harness passes in both builds, the expanded
suites pass, full `make check` exits 0 and graphical debugger integration exits 0.
No blocking correctness findings remain in the correction scope. Owner physical
mouse/keyboard feedback remains outstanding; this is not a claim of that coverage.

[Delegation.md](delegation.md) now describes **6B.1.1**, the dedicated live senses
windows and vision filters. Those windows are not part of the accepted 6B.1
implementation. The owner clarified that they show current detections only;
trace/log/history, memory and interpretation UI stay in the decision/replay tools.

## Correction re-review and independent proof

Pinned evidence root:
`build/verification/vision-team-lead-rereview-20260911-7611bml0/`.
The earlier handoff is preserved there as `delegation-before-rereview.md`.

| Area | Re-review result |
| --- | --- |
| R1: edges/corners | Closed. The new enumeration considers both neighbors at a closed boundary and retains the exact cell-touch check. Original regression cases pass; the expanded 4,000-segment exhaustive comparison also passes. |
| R2: supported range | Closed. Accepted queries no longer hit the 70 × 70 box cap. Host/client bounds agree; the 128 × 128 / 16-unit tile / 2,048-unit range cases pass with bounded work. |
| R3: individual replacement | Closed. Per-slot binding leaves the other creature and round settings intact. Both-slot lifecycle coverage and the original independent test pass. |
| Early pause | The fixed inspector pins its first available decision while staying paused. Current headless and graphical integrations force this case for P2 and pass. |
| Harness integrity | Compared `tests/vision_review/vision_review_test.odin` with the copy preserved in the first Team Lead graphical run: no difference. It is now included in `make check_vision_review`, `make check_vision` and full `make check`. |

| Independent command/check | Result and artifact |
| --- | --- |
| `make check` | **Exit 0**, `make-check.log`; includes normal perception/AI/host suites (9 / 7 / 41), 3 + 3 Team Lead regression tests, headless debugger/replay integration and the full existing game/development checks. |
| `odin test server/perception -debug` | **Exit 0**, 9 tests, `perception-debug.log`. |
| `odin test server/ai -debug` | **Exit 0**, 7 tests, `ai-debug.log`. |
| `odin test server -debug` | **Exit 0**, 41 tests, `host-debug.log`; linked with the repository ENet library. |
| `python3 tests/ai_debugger_check.py --graphical` | **Exit 0**, `debugger-graphical.log`; two native AI DEBUG windows and synthetic early-pause coverage. |
| Code/document checks | Inspected the geometry, lifecycle, inspector and test changes. Comment-group length check on correction source files found no groups over three lines. No runtime code was changed by the Team Lead. |

Headless integration artifacts are pinned at
`build/verification/ai-debugger-20260911-042230-174861/`; its P2 driver reports
`passed: true` and `early_pause: true`. Graphical artifacts are pinned at
`build/verification/ai-debugger-20260911-042641-188446/`. Inspected:

- `native-windows.txt`: separate P1/P2 AI DEBUG windows alongside clients.
- `build/dev/20260911-042641-188447/ai1-vision.png`: retained sample age and
  sampled facing remain distinct from the current decision's facing.
- `build/dev/20260911-042641-188447/ai1-vision-host.png`: real map cells and red
  map boundary; host evidence stays separately labelled.
- `replay-vision-p1.png`: recorded visual evidence and its source tick.

The coding agent's negative-control source was compared with the fixed inspector:
only the four-line first-decision handling block differs. Its saved failure log
has the original empty-selection signature. That supports the early-pause cause
and fix; the exact user input that triggered the first uninstrumented failure was
not recorded. The Team Lead inspected this negative control and independently
reran the fixed path, rather than claiming to have rerun the negative control.

The independent debug measurements were about **19.3 µs per three-candidate sample**,
**0.49 ms per 65-ray fan**, and **6.86 µs mean / 50.48 µs max** per serial tick on
the supported-envelope workload. These are local test measurements, with other
verification running on this PC; they exclude end-to-end scheduling/display
latency and are not larger-battle capacity evidence.

Remaining limits: physical input and an exported Godot release binary were not
tested. Existing host-label overlap remains a nonblocking readability follow-up;
generic inspector titles belong in 6B.1.1. The coarse fan, planar center-point
sight and telemetry recording/publish limits remain documented. The next live
senses view must be measured against its own latency and readability requirements.

## Initial findings — historical record, now resolved

The sections below preserve the first candidate's failures and initial evidence.
Their failure descriptions and test counts are historical; the disposition above
is current.

### R1 — P1: opaque wall edges leak focused sightings

Location: [grid_visibility.odin](../server/perception/grid_visibility.odin#L73).

On a 32-unit grid, make only cell `(4, 4)` opaque. Its closed footprint spans
`(128, 128)` through `(160, 160)`. A vertical sight segment from `(160, 96)` to
`(160, 192)` runs along its right edge. Production reports clear sight and delivers
a focused sighting. The corresponding left-edge segment at `x = 128` blocks.
The bottom edge and a segment ending exactly at the bottom-right corner leak too;
reversing the segment reproduces the failures.

This contradicts the candidate's documented rule that touching any closed opaque
cell blocks sight. The candidate-cell bounds omit the opaque neighbor on some
exact boundaries. A creature can therefore receive detailed evidence that the
chosen occlusion rule forbids.

Acceptance: all sides, endpoint touches and corner touches follow one documented
rule, independent of ray direction. Nearby genuinely clear rays stay clear.
Actual delivered samples and the rendered visibility geometry must agree.

### R2 — P2: valid tuning creates false occlusion on an empty map

Locations: [grid_visibility.odin](../server/perception/grid_visibility.odin#L77),
[vision.odin](../server/perception/vision.odin#L59) and
[arena.odin](../server/arena.odin#L156).

The catalogs accept a 128 × 128 map with 16-unit tiles and a 64-gameplay-unit
vision range, equivalent to 2,048 world units. With no opaque cells, an observer
at `(8, 8)` facing a subject at `(1448, 1448)` should see it: the distance is about
2,036.47 world units. Instead the sample reports `Occluded` and supplies no sighting.
The shorter control ray succeeds.

The accepted query covers a 91 × 91 bounding box, exceeding the internal 70 × 70
work limit. The implementation record calls this limit outside gameplay cases,
but it is reachable with accepted content. Default 8-unit vision is unaffected.

Acceptance: supported content must produce correct, bounded perception throughout
its accepted range. Runtime work limits must not silently invent cover. Keep host
and client validation, display geometry and documentation consistent with the
supported envelope, and measure the worst supported case after correction.

### R3 — P2: replacing P1 erases P2's private experience

Location: [battle.odin](../server/battle.odin#L25).

The regression lets two same-definition creatures acquire real memories through
900 production simulation ticks. It replaces only P1's runtime entity ID in the
same round, then calls the production binding operation. P1 correctly starts
fresh, but P2 also loses its agent state, retained eye sample, sampling schedule
and action timing. The operation rebuilds both instances whenever either changes.

The assignment explicitly requires resetting or replacing one instance to leave
the other's private state intact. Normal whole-round resets still need to clear
both. Individual replacement is a foundation requirement; this review does not
request a new player-facing replacement feature.

Acceptance: instance replacement clears only that instance. Preserve the other
creature's memory, attention, evidence timestamps, sensing schedule and action
timing. Whole-round reset and same-definition isolation must continue to work.

## Initial independent verification

Evidence root:
`build/verification/vision-team-lead-20260911-032822/` (pinned with `.keep-logs`).

| Check | Team Lead result |
| --- | --- |
| `make check_perception check_ai check_session` | Exit 0: 6 perception, 7 AI and 39 host tests. Pinned copy: `baseline.log`. |
| Existing suites with `-debug` | Exit 0: 6 perception, 7 AI and 39 host tests. `perception-debug.log`, `ai-debug.log`, `host-debug.log`. |
| [Independent regression harness](../tests/vision_review/README.md) | Normal and debug builds compile, then exit 1; all three tests fail. `vision-review-tests.log` and `vision-review-tests-debug.log`. |
| Headless debugger integration | Exit 0. Real workers, both inspectors, observation isolation, recorded replay, retained samples, downward graphs, reload, release gate and cleanup pass. `debugger-headless.log`. |
| Graphical integration | First attempt exited 1: P2 was paused with no selected trace while its live reader advanced. The retry exited 0 and recorded both native AI DEBUG windows through `wmctrl`. `debugger-integration.log` and `debugger-graphical-retry.log`. |
| Rendered evidence | Inspected the agent's captures and new captures from the independent graphical retry: live vision, host diagnostics and replay. Focus/periphery, requested/confirmed facing and recorded sample time are present. This does not validate every geometry or event boundary. |
| Full `make check` | Reported passing by the coding agent; not independently rerun in this review. Targeted reruns and new negative checks are the independent evidence. |
| Physical mouse/keyboard and exported Godot release | Not tested by the Team Lead. Synthetic integration and the existing release gate do not establish this coverage. |

The graphical retry artifacts are pinned at
`build/verification/ai-debugger-20260911-033615-116451/`. Its
`native-windows.txt` records separate P1/P2 inspectors; live captures are under
`build/dev/20260911-033615-116452/`, and `replay-vision-p1.png` is at the artifact
root. The successful headless artifacts are pinned at
`build/verification/ai-debugger-20260911-033521-114078/`.

The first graphical failure did not recur in the retry and has no established
code cause. Keep its log when comparing future runs. The initial branch-detail concern
about future memory was not established on emitted traces and is **not** a
confirmed finding. The next report should retain causal event-step coverage,
including memory additions, refreshes and expiry.

One presentation follow-up remains visible in the new host-view capture: labels
for nearby rejected candidates overlap. This is a readability issue in the
privileged diagnostic overlay, separate from the three acceptance failures.

The new harness is separate from the existing Make targets. Its tests use literal
boundary cases and production APIs, rather than reproducing the sight algorithm.
The correction pass must retain these guarantees in the normal verification path.

## Initial architecture and deviation assessment

- The brain's value input contains its own observations and state. The privileged
  query and host audit remain outside that input. Peripheral cues expose only
  observation ID, direction sector and range band. Inspection and the existing
  hidden-world checks support this boundary.
- Separate native workers still receive both pre-action contexts before collection.
  Host action resolution remains authoritative. Both workers are joined in the
  same simulation tick: variable reasoning across ticks remains roadmap work.
- Terrain schema 2 and migrated content fingerprints are reasonable for making
  sight blocking explicit. An array of sense bindings is reasonable for detecting
  duplicate bindings. Neither choice is rejected by this review.
- The 28 KiB trace ceiling is acceptable for this two-creature slice: the existing
  worst-case test reproduced 27,526 bytes against a 28,672-byte limit. Keep all
  snapshot/replay limits and oversized-record reporting aligned.
- The candidate reports about 100 ms of writer publishing per 250 ms cycle and
  roughly 100 seconds of recording before the 128 MiB cap. These are scaling and
  manual-QA constraints, not evidence of capacity for larger battles. Preserve the
  explicit recording-stop status; reassess telemetry cost before adding senses.
- The independent baseline's 3,600-tick serial workload averaged about 2.2 µs per
  tick, with a 12.18 µs maximum. This excludes dedicated-thread scheduling and
  writer/UI work. It is not an end-to-end battle latency measurement.

## Initial correction assignment

Keep the correction focused on R1–R3 and any reproducible debugger failure. Do not
add the remaining senses, combat, moods, persistent learning or new scheduling
semantics in this pass. Preserve the existing default tuning and QA launch flow.

Apply the owner's comment rules to touched code: plain human language, one line
preferred, three lines maximum. Dense technical explanations belong in
`docs/codebase/`; hard-to-follow control flow should be refactored into named,
focused operations. The comment-length spot check found no adjacent full-line
comment groups over three lines in the changed code; that does not establish that
all explanations meet the owner's plain-language standard.

Return corrected test evidence, updated documentation and any remaining limits.
Team Lead re-review and the owner's manual feedback are still required before
acceptance.
