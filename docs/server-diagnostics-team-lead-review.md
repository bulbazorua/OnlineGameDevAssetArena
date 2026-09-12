# Odin diagnostics extraction: independent Team Lead review

Date: 2026-09-12 (Asia/Manila).

## Findings

No introduced functional regression was found.

### P3: Make the caller's lifecycle obligations explicit

[diagnostics.odin:82](../server/diagnostics/diagnostics.odin#L82) stores the
`directory` and `run_id` string headers without cloning their backing bytes.
The writer reads those strings until shutdown. The new ownership document should
say that the caller keeps both strings alive and unchanged until `close` returns;
they are borrowed configuration, unlike the owned fingerprint and grid copies.

Also, the comment at [diagnostics.odin:109](../server/diagnostics/diagnostics.odin#L109)
says close stops accepting jobs, but [queue.odin:29](../server/diagnostics/queue.odin#L29)
does not reject jobs when `stopping` is set. The actual contract is a single
main-thread producer that finishes capturing before calling close. Close signals
the writer to drain and exit; it does not stop some other producer thread.

The existing host obeys both requirements, and the implementation matches the
old behavior. This is a nonblocking documentation correction, not a request to
change allocation, queue policy or concurrency during the refactor.

## Disposition

**ACCEPTED WITH A NONBLOCKING LIFECYCLE-DOCUMENTATION NOTE.**

The extraction delivers the intended ownership boundary without an observed
change to gameplay, packets, private sensing, recordings or the existing dev UI.

This acceptance is specific to the diagnostics extraction. It does not close the
earlier dev UI notes, establish fresh-clone test bootstrapping, or authorize new
features. Owner physical-input/visual acceptance remains separate.

## Source and boundary review

The package has nine focused production files and exactly six public production
operations: `options_valid`, `open`, `close`, `record_decisions`,
`capture_world` and `capture_scent`.

Writer execution, queue operations, rotation, record/view conversion, hex
encoding, replay writes and feed publishers are private. The five public
`test_*` probes are separately named and documented; no production caller uses
them. They preserve deterministic no-writer saturation checks instead of
introducing a timing-dependent writer race into those tests.

The host retains startup, launch options, scenario coordination, network reset
authorization, the reset console notice and packet encoding. The scenario files
were renamed without changing their bodies. No reverse dependency from simulation
to diagnostics was introduced.

The reviewed dependency changes are bounded:

- The launch gate receives the four values it checks instead of the host `Options`.
- The host supplies the protocol version written into the replay header.
- `host_capture_world` returns before encoding when the diagnostics handle is nil.
- The package copies the host's valid packet slice into owned bounded storage before returning.
- Journal rotation is an extracted helper; the unused `ai_debug_publish` was removed.

The writer/feed procedures and recorded data structures were compared with the
pre-extraction code, accounting for names, package imports and visibility.
The queue/drop/sequence rules, publication cadence, delivery clocks, fan cache,
field quantization, private projections and shutdown implementation remain the
same. Procedure visibility is compiler-enforced; writable-field ownership is
still a documented convention.

Moved tests retain their baseline assertions. The split scent test keeps both
package-owned capture/publication checks and real host-step wiring coverage.
The host still checks exact lobby and full-arena packets, journal rotation,
complete shutdown, retained trace provenance and serial/threaded behavior.

## Independent source identity

Evidence root: `build/verification/server-diagnostics-independent-20260912/`.

The candidate source manifest passed before and after the main verification run.
The complete candidate path set also matched before and after, detecting additions
or deletions outside the listed hashes.

Protected baseline manifests passed for `client/`, `tools/`, `tests/`,
`server/ai/`, `server/perception/`, `server/observations/`,
`server/content/` and `server/simulation/`.

The supplied manifest excludes instruction files and generated/cache directories;
this is not a claim that every filesystem object was hashed. `CLAUDE.md` was not
accessed. No Git command was used.

No production code, existing test, fixture or build rule was edited during review.
Reviewer additions are the independent evidence/probe and this document. Nothing
was staged or committed.

Evidence: [gate exit codes](../build/verification/server-diagnostics-independent-20260912/exit-codes.txt),
[candidate hashes](../build/verification/server-diagnostics-independent-20260912/candidate-source.sha256),
[post-run source check](../build/verification/server-diagnostics-independent-20260912/source-after.log)
and [post-run path comparison](../build/verification/server-diagnostics-independent-20260912/paths-after.diff).

## Fresh gates

Tools: Odin `dev-2026-03-nightly`, Godot `4.6.stable.official.89cea1439`,
Python 3.12.3, display `:0`.

| Independent gate | Result |
| --- | --- |
| Diagnostics package, normal build, no ENet linker flags | Exit 0; 10 tests |
| Diagnostics package, debug build, no ENet linker flags | Exit 0; 10 tests |
| `make check` | Exit 0; 195 Odin test executions and 44 PASS markers |
| Optimized release host build | Exit 0 |
| Release connection, selection, arena selection, movement and audience-delay client checks | All exit 0 |
| Graphical AI debugger workflow | Exit 0 |
| Graphical scent workflow | Exit 0 |
| Graphical senses-window workflow | Exit 0 |
| Graphical development workflow | Exit 0 |
| Fresh debug host tests from the preserved pre-extraction source | Exit 0 |
| Deterministic recorded-value comparison | Exit 0 |
| Baseline-host recording through the fresh candidate's matching-content reader | Exit 0 |
| Post-run candidate/protected hashes and scoped path set | Passed |

The full-suite count includes repeated normal/debug executions. Its package
counts are content 9, simulation 30, diagnostics 10 and host 21 in each build;
AI 18 and perception 17; vision 3, olfaction review 3 and olfaction coverage 4
in both builds.

The suite includes the existing release diagnostic-option rejection gate.
Scripted native-window checks covered reload, failed saves/launches, private
readings, stale recovery, reset, inspector close, replay and cleanup. These are
not physical keyboard/mouse tests.

Logs: [full suite](../build/verification/server-diagnostics-independent-20260912/check.log),
[summary](../build/verification/server-diagnostics-independent-20260912/check-summary.txt),
[graphical debugger](../build/verification/server-diagnostics-independent-20260912/ai-debugger-graphical.log),
[graphical scent](../build/verification/server-diagnostics-independent-20260912/scent-graphical.log),
[graphical senses](../build/verification/server-diagnostics-independent-20260912/senses-graphical.log)
and [graphical development](../build/verification/server-diagnostics-independent-20260912/dev-graphical.log).

## Value-level recording parity

The agent's `compare_records.py` checks shapes, selected headers and enum sets.
It turns ordinary numeric/string/bool values into type descriptions, so its
passing result is not proof that recorded gameplay values match.

The independent check closes that gap using the existing deterministic
60-tick journal fixture. The baseline fixture was freshly generated by running
the old host's debug tests. The candidate fixture came from the fresh full suite.
Fixture paths were taken from each test's own output, not guessed from the newest
staging directory.

All of the following matched:

- All 120 retained decision records, including inputs, before/after agents, action outcomes, private memories, host audits and display geometry.
- All 60 replay frames, with exact packet hex and the associated per-creature records.
- Complete replay header/end records, including fingerprint, seed, versions and final counters.
- Final `senses.json`, `search.json` and `scent.json`, including field levels/ages and lifecycle data.

Normalization is explicit and narrow: diagnostic wall-clock/duration fields,
thread identities, and the snapshot's replay byte count derived from the varying
timestamp text. Simulation ticks, sample IDs, sequences, positions, enum values,
array order/length, fingerprints and packet bytes were not erased.
Unknown negative times and zero thread identities were preserved. A sensitivity
check confirms that changing an input tick is detected.

This is recorded-value parity for a controlled fixture, not deterministic
re-simulation of arbitrary recordings.

Evidence: [comparison script](../build/verification/server-diagnostics-independent-20260912/value_parity.py),
[results and source paths](../build/verification/server-diagnostics-independent-20260912/value-parity/comparison.json)
and [execution log](../build/verification/server-diagnostics-independent-20260912/value-parity.log).
The raw baseline and candidate fixture files are preserved beside the result.

## Old recordings and the live trail

A recording produced by the baseline host decoded and sought successfully
through the generation-1 reader staged by the fresh candidate graphical
debugger run. The same check also exercises the legacy schema-1 fixture.
The fresh graphical debugger already exercised its candidate-produced recording.

Evidence: [replay compatibility log](../build/verification/server-diagnostics-independent-20260912/replay-compat.log)
and [exact recording/reader paths](../build/verification/server-diagnostics-independent-20260912/replay-compat/sources.txt).

The fresh moving-emitter run sampled 49 positions. All 29 path entries at least
two tiles behind the trainer contained scent, covering 26 distinct cells.
A walked cell away from the bodies, `[13,5]`, decayed from **107 to 34 in
12 seconds** in the host publication.

Both minimaps were live and their displayed counts matched corresponding host
publications; F8 was checked the same way. These views have independent clocks:
their saved snapshots need not share a publication ID, and later screenshots
need not show the same cell count as the earlier JSON capture.

The fresh minimap and F8 images were visually inspected. The trail remains
visible and the minimap still labels host-world data separately from private
nose readings. The previously noted range-ring clipping issue remains unchanged.

Evidence: [trail JSON](../build/verification/server-diagnostics-independent-20260912/graphical/scent/moving-emitter-trail.json),
[minimap](../build/verification/server-diagnostics-independent-20260912/graphical/scent/senses1-olfaction.png)
and [F8](../build/verification/server-diagnostics-independent-20260912/graphical/scent/p1-scent-heatmap.png).

## Costs and evidence limits

Fresh graphical senses delivery p95 was **87.3-103.4 ms**, below the existing
150 ms p95 gate. The largest individual sample was approximately **237.7 ms**;
a passing p95 is not a maximum-latency guarantee.

Maximum recorded inspector update times were 1.860 and 1.878 ms. Field-read
maxima in that workflow were 131 microseconds in both inspectors. The diagnostic
writers reported zero dropped records.

The agent's paired 45-second whole-host benchmark was inspected, not rerun:
debug diagnostics-on CPU totals were 24.94 vs 24.87 seconds, and diagnostics-off
totals were 0.58 seconds on both sides. The fresh reviewer timing above is
scenario-specific; it does not independently establish identical whole-host
cost or release-build performance.

Evidence: [fresh performance data](../build/verification/server-diagnostics-independent-20260912/graphical/senses/performance.json).
All four fresh graphical sandboxes have `.keep-logs` and are indexed in
[graphical-sandboxes.txt](../build/verification/server-diagnostics-independent-20260912/graphical-sandboxes.txt).

Physical input, exported-client execution, arbitrary window sizes, a new
filesystem-fault campaign and release timing were not independently exercised.

## Cleanup still open before new features

- Clarify the borrowed configuration strings and single-producer shutdown contract noted above.
- Complete the three previously recorded dev UI P3 items: plot-only clipping, calling the Python overview validator and correcting the rendered pixel-count wording.
- Fix the existing clean-start overview test setup. The preserved baseline's first log fails to resolve `ArenaCatalog` when the Godot import cache is absent; the overview target lacks an import prerequisite. The agent's later baseline passes used the initialized cache and complete asset-source copy. This issue predates the extraction; the reviewer did not create a separate fresh clone or fix it here.

These are bounded follow-ups, not reasons to reopen the accepted simulation
refactor or add another diagnostics framework.

Related records: [assignment](delegation.md), [coding-agent handback](server-diagnostics-coding-agent-report.md),
[diagnostics architecture](codebase/server-diagnostics.md) and
[prior dev UI review](dev-arena-overview-team-lead-review.md).

