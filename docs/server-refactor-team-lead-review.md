# Server refactor: independent Team Lead review

Reviewed 2026-09-12. **Status: changes requested for R1; not accepted yet.**

Assignment: [delegation](delegation.md). Handback:
[coding-agent report](server-refactor-coding-agent-report.md).

## Finding

### R1: narrow the simulation's exported mutation API (P2)

The package extraction leaves implementation-only mutation procedures public.
Examples are [trainer_tick_energy](../server/simulation/trainers.odin#L52),
[character_resolve_intent](../server/simulation/character_actions.odin#L32),
[receptor_bind](../server/simulation/senses.odin#L36),
[senses_prepare](../server/simulation/senses.odin#L128), and
[scent_environment_tick](../server/simulation/scent_environment.odin#L67).
Their production callers are inside `simulation`; the host does not need these
entry points. Relevant direct unit tests are in that package too.

This is an encapsulation finding, not an observed gameplay regression. The
exported procedures let future host code bypass the owning phases: for example,
changing trainer energy outside its motion step, resetting receptors separately
from creature binding, or resolving an action without recording its result in
the agent. They also make the public API larger than the intended host contract.
Odin's field-visibility limitation does not prevent hiding these procedures.

Requested correction: audit the simulation exports and make implementation-only
helpers package-private, or file-private where appropriate. Keep the actual
external lifecycle, phase, worker and diagnostic contracts public. Do not add
forwarding wrappers, new packages, gameplay changes, or long comments to do this.
Reconcile the architecture/API inventory with the resulting exports. Preserve
the tests and rerun the affected package gates and final integration checks.

## Code and coverage review

- Compared current production procedures and moved tests with the retained
  pre-refactor source, rather than comparing against the older clean commit.
- Session commands, countdown/arena entry, movement, trainer motion, content
  parsing, geometry, and codec changes preserve their existing behavior under
  the package/name changes inspected.
- The pre-step summon gate, scent update, frozen sensing phase, both decisions,
  ordered action resolution and feedback remain intact. Both worker requests
  are submitted before collection. Mailbox synchronization and shutdown remain
  intact; the catalog and writer/worker lifetimes remain correctly ordered.
- Diagnostic record construction was checked against its original location in
  `battle_tick`, including pre-action facing, original samples, confirmed
  outcomes and post-action agent state. Audience history still copies public
  session values, not private battle state.
- Original test assertions were retained. The increase from 61 to 63 tests
  comes from splitting coverage/diagnostic and trainer/wire responsibilities,
  not additional independent behavioral assertions. The independent vision
  fixture changes are imports, names and calls to the relocated serial step.
- The new content and simulation packages are included in normal and debug
  test discovery. No new production comment block over three lines was found
  in the reviewed changes.

## Independently executed verification

Evidence root: `build/verification/server-refactor-20260912/independent-review/`.
The source manifest identifies the reviewed server, test/tool source and
Makefile. Its final consistency check passed after the verification runs.

| Gate | Result | Evidence relative to that root |
| --- | --- | --- |
| `make build_server` | Exit 0 | `build-server.log` |
| `make check` | Exit 0; 42 PASS markers | `check.log`, `check-summary.txt` |
| Content / simulation / host Odin packages | 9 / 30 / 24 tests, normal and debug, all passed | `check.log` |
| AI / perception | 18 / 17 tests passed | `check.log` |
| Independent vision / olfaction / coverage packages | 3 / 3 / 4 tests, normal and debug, all passed | `check.log` |
| Optimized non-debug host build | Exit 0 | `release/build.log` |
| Release connection, selection, arena selection, movement and audience-delay client checks | All five exit 0 | `release/*_check.log` |
| Actual pre-refactor recording plus legacy replay fixture | Exit 0; 1,048 production frames, seek/playback and validation assertions passed | `replay/check.log`, `replay/replay-check.json` |
| Graphical scent, senses windows, AI debugger and development workflow | All four exit 0 | `graphical/*_check.log`, `graphical/evidence-directories.txt` |
| Rebuilt preserved baseline root tests | 61 tests passed | `baseline-session-tests.log` |
| Fresh candidate simulation repeat | 30 tests passed | `candidate-simulation-tests.log` |
| Baseline/candidate search outcome comparison | Identical acquisition ticks and maximum squared travel on all four maps, each simulated for 18,000 ticks per version | `baseline-search-outcomes.txt`, `candidate-search-outcomes.txt`, `search-outcome-comparison.txt` |

The graphical senses harness measured delivery p95 between 85.1 and 101.9 ms
across the two eyes/noses and passed its latency limits. This is scripted
rendered coverage, not physical keyboard/mouse testing. Graphical sandbox
evidence has `.keep-logs` markers.

The old-recording check used a copy of the baseline-host recording and its
matching staged QA content/client, with the current repository replay test.
The repository Godot script manifest matches the pre-refactor manifest. The
original recording was not modified.

The preserved source manifest verified successfully. Hash checks also confirmed
unchanged cognition, perception, observation contracts, tools, content and the
independent olfaction/coverage fixtures. The only differences under `tests/`
are the two reported files: the development workflow path changes and the
independent vision fixture's package adaptation.

Report correction: the handback reverses the independent olfaction package
counts. The actual runs contain **3** tests in `tests/olfaction_review` and
**4** in `tests/olfaction_coverage`; both pass in both modes.

## Limits and reviewer-owned failed experiment

- A separate reviewer-written cross-version, tick-by-tick parity probe did not
  compile: it imported duplicate Odin package names and dynamically indexed a
  constant array. This is a review-harness error, not a candidate build failure.
  Its log and source remain under `parity-normal.log` and `parity/main.odin`.
  It was not counted as passing evidence. Permission to correct it was requested;
  it remains unmodified pending that decision. No debug run of that probe ran.
- The successful search outcome comparison above is narrower than full runtime
  equality between baseline and candidate on every tick. The existing candidate
  serial/threaded runtime-equality tests did pass independently.
- Physical keyboard/mouse interaction and an exported client were not exercised.
- The coding agent's retained performance procedure and results were inspected.
  Whole-host debug CPU/memory measurements and release performance were not
  independently benchmarked here. The small reported serial QA-path slowdown
  remains a disclosed tradeoff, not evidence of a measured production-host
  slowdown. The fresh scenario runs were used for correctness comparison.
- Historical document links to moved files remain as disclosed in the handback.
  The proposed diagnostics package and per-tick hashing are not approved or
  implemented by this review.

## Disposition

No new gameplay or multiplayer regression was found in the inspected changes
or completed verification. The content boundary and explicit battle phases are
useful improvements, but R1 should be corrected before closing this cleanup.
Keep that correction small and separate from any diagnostics extraction.

The Team Lead changed no production code or existing regression tests, and did
not stage or commit changes. This review adds only its document and local
verification artifacts.
