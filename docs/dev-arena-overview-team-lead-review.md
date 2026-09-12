# Dev arena overview: independent Team Lead review

Date: 2026-09-12 (Asia/Manila).

## Findings

No blocking regression was found. Three nonblocking follow-ups remain.

### P3: Keep range rings inside the plot area

[arena_overview.gd:115](../client/dev/ui/arena_overview.gd#L115) makes feature layers fill the entire frame. The clipping enabled at line 31 therefore clips to the control, not the arena plot. [scent_field_layer.gd:53](../client/dev/senses/scent_field_layer.gd#L53) draws the full nose-reach circle.

When the nose is near an arena edge, that circle enters the frame's title or footer padding. Fresh live trail captures show it crossing the fit/legend area. Labels remain readable; this is a presentation defect, not a change to sensing or field data.

Follow-up: clip feature drawing to the plot region while keeping the shared coordinate transform and frame labels separate. Cover an observer near an arena edge.

Evidence: [fresh P1 trail view](../build/verification/dev-arena-overview-independent-20260911T231026Z/graphical/scent/senses1-olfaction.png) and [P2 trail view](../build/verification/dev-arena-overview-independent-20260911T231026Z/graphical/scent/senses2-olfaction.png).

### P3: Connect the new Python overview validator

[check_arena_overview](../tests/senses_windows_check.py#L85) adds checks for matching live fields, default views, fitting legends, bounded rebuilds and field-read time, but the harness changes never call it. Those assertions cannot be counted as executed.

The GDScript driver, focused overview test and real scent workflow cover much of the same behavior, so this does not block acceptance. Follow-up: call the helper for both inspectors when their live overview state is ready.

### P3: Report the actual number of pixel checks

[dev_arena_overview_render_check.gd:50](../tests/dev_arena_overview_render_check.gd#L50) labels every result entry a pixel probe. Component-path and placement records are also inserted at lines 111 and 156.

The fresh result contains **40 pixel checks and 8 metadata/placement records**, not 48 pixel checks. All passed. Follow-up: count the categories separately and correct the handback wording.

Evidence: [render results](../build/verification/dev-arena-overview-independent-20260911T231026Z/render/render-results.json).

## Disposition

**ACCEPTED WITH NONBLOCKING NOTES for the delegated implementation scope.**

The requested shared arena views, actual shared radar component and published scent trail are implemented, and the independent gates pass. This is technical acceptance, not a claim that physical-input QA or the owner's final visual preferences were tested.

The three notes above were not fixed during review. No additional server refactor or UI framework is authorized by this acceptance.

## What the source review established

- Vision and Olfaction instantiate the same [local radar frame](../client/dev/ui/sensor_radar.gd), not separate widgets with matching colors.
- Vision, Olfaction and Exploration memory use the same [page layout](../client/dev/senses/sense_page.gd) and [arena frame](../client/dev/ui/arena_overview.gd).
- Shared frames own presentation, transforms and input signals. Feature pages/layers retain their own data interpretation, selection and lifecycle. The generic frames do not import feature feeds.
- Olfaction's host-field reader has its own throttle and clock. The displayed field is checked against the current round, map and geometry.
- Host-world scent remains explicitly labeled developer-only data, separate from private nose readings and personal exploration memory.
- The minimap and F8 use the same [field painter](../client/dev/scent_field_image.gd). The minimap does not invent a trail from body positions or simulate decay locally.
- Existing private-reading limits, stale memory ages, linked selection, reset behavior and local-radar bearing semantics remain covered.
- Existing test changes were reviewed against the preserved baseline. Relocations/access changes did not remove the inspected baseline assertions.

The permanent reuse-first, loosely coupled dev UI rule in `AGENTS.md` remains intact.

## Independent source identity

Evidence root: `build/verification/dev-arena-overview-independent-20260911T231026Z/`.

The candidate's 199-file source manifest passed before and after the fresh gates. Its complete scoped path set also matched, so this check was not limited to hashing already-listed files.

Protected baseline hashes passed for server code, tools, runtime client files and assets outside `client/dev/`, dev fixtures, independent review fixtures and `AGENTS.md`. The complete server source path set also matched. `CLAUDE.md` was excluded and was not accessed.

The agent's disclosed final test-only decay-probe adjustment was accounted for separately from the launch candidate. No production code, agent test, fixture, build rule or permanent rule was edited during this review. No Git command, staging or commit was performed.

Evidence: [exit codes](../build/verification/dev-arena-overview-independent-20260911T231026Z/exit-codes.txt), [final candidate hashes](../build/verification/dev-arena-overview-independent-20260911T231026Z/source-after.log), [final protected hashes](../build/verification/dev-arena-overview-independent-20260911T231026Z/protected-after.log), [candidate path delta](../build/verification/dev-arena-overview-independent-20260911T231026Z/candidate-path-delta.txt) and [server path delta](../build/verification/dev-arena-overview-independent-20260911T231026Z/server-path-delta.txt).

### Reviewer wrapper failure

The first protected-file check failed before any test ran because my wrapper split filenames on whitespace. Twenty-four asset paths containing spaces were truncated.

The owner approved correcting that reviewer-owned wrapper. The replacement preserves the entire SHA-256 filename field; both subsequent protected checks passed. The original failed log and exit code remain in the evidence. This was not a project test failure.

## Fresh verification

Tools: Odin `dev-2026-03-nightly`, Godot `4.6.stable.official.89cea1439`, display `:0`.

| Gate | Result |
| --- | --- |
| Candidate/protected hashes and scoped path sets | Passed |
| `make check_arena_overview` | Exit 0; 150 headless assertions; 40 pixel checks plus 8 metadata/placement records |
| `make check` | Exit 0; 181 Odin test executions, including repeated normal/debug coverage; 44 PASS markers |
| `python3 tests/scent_check.py --godot=godot --odin=odin --graphical` | Exit 0 |
| `python3 tests/senses_windows_check.py --godot=godot --odin=odin --graphical` | Exit 0 |
| Post-run candidate/protected hashes | Passed |

Logs: [focused gate](../build/verification/dev-arena-overview-independent-20260911T231026Z/check_arena_overview.log), [full suite](../build/verification/dev-arena-overview-independent-20260911T231026Z/check_full.log), [suite summary](../build/verification/dev-arena-overview-independent-20260911T231026Z/check-summary.txt), [graphical scent](../build/verification/dev-arena-overview-independent-20260911T231026Z/scent_graphical.log) and [graphical senses](../build/verification/dev-arena-overview-independent-20260911T231026Z/senses_graphical.log).

The full suite covered the existing server, content, networking, private-sensing, exploration, replay and development workflows. Fresh graphical checks also exercised stale recovery, independent clocks, paused-brain behavior, reset, inspector close/reload and cleanup. Scripted input is not physical-input coverage.

### Real trailing scent

The fresh moving-emitter run recorded 49 position samples. All 29 sampled path entries at least two tiles behind the trainer contained published scent, covering 26 distinct cells.

A walked cell away from the bodies, `[3,8]`, decayed from **221 to 108 in 12 seconds**. Its field ticks advanced from 1223 to 1943. This compares host-published levels, not a client prediction.

Both inspectors reported **205 painted cells for publication 32188075, tick 1931**, with matching live fields and no reader errors. The F8 gate independently matched its painted count to the corresponding host publication. Captures need not have identical timestamps.

Evidence: [trail and decay JSON](../build/verification/dev-arena-overview-independent-20260911T231026Z/graphical/scent/moving-emitter-trail.json) and [fresh F8 capture](../build/verification/dev-arena-overview-independent-20260911T231026Z/graphical/scent/p1-scent-heatmap.png).

### Rendered behavior and costs

The shared-page render fixture passed at both configured sizes on a rectangular arena. Its page-only subviewports are distinct from the real native-window captures. Fresh minimum-window and stale-field captures were also visually inspected; field labels, private-reading separation and stale fading remain readable.

The fresh graphical senses run measured delivery p95 values of **80.8-81.2 ms**, below the existing 150 ms p95 gate. The largest individual delivery sample was approximately 180 ms; the gate is not a maximum-latency guarantee.

Maximum recorded inspector update times were 2.647 ms and 1.980 ms in this scenario. Maximum field-read times were 108 and 100 microseconds; the trail run recorded 121 and 115 microseconds. The two diagnostic writers reported zero dropped records.

Evidence: [fresh performance data](../build/verification/dev-arena-overview-independent-20260911T231026Z/graphical/senses/performance.json), [minimum-window view](../build/verification/dev-arena-overview-independent-20260911T231026Z/graphical/senses/senses1-olfaction-minimum.png) and [stale-field view](../build/verification/dev-arena-overview-independent-20260911T231026Z/graphical/senses/senses1-olfaction-arena-stale.png).

## Limits and handoff

- Physical keyboard/mouse use and an exported client were not tested.
- Coverage is limited to the configured 1000x700 and 1200x800 sizes and exercised arenas.
- The agent's 60x28 worst-case cost and memory-growth comparison were not independently rebenchmarked. Fresh timing above is scenario-specific.
- Fresh logs, representative JSON and graphical captures are preserved under the independent evidence root. Both graphical sandboxes also have `.keep-logs`; their paths are recorded in [graphical-sandboxes.txt](../build/verification/dev-arena-overview-independent-20260911T231026Z/graphical-sandboxes.txt).
- The coding-agent report remains unchanged, preserving the distinction between its claims and this independent review.

Related records: [delegation](delegation.md), [coding-agent handback](dev-arena-overview-coding-agent-report.md), [component architecture](codebase/dev-arena-overview.md).

