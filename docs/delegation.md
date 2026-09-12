# Odin diagnostics cleanup: coding-agent packet

Status: **READY FOR CODING AGENT. NOT IMPLEMENTED OR ACCEPTED.**

This is cleanup before the next features. Extract the server's existing diagnostic
writer and feeds into one clearly owned package. Do not add mechanics, telemetry
features, UI changes, or another architectural layer merely for future use.

## 1. Assignment and working arrangement

The coding agent implements this packet. The Team Lead independently reviews the
source and verification afterward. Hand back through the owner; do not spawn
another agent or start a follow-on task.

The completed server work was the `content` and `simulation` extraction plus R1
procedure visibility. The diagnostics extraction was proposed but never included
in those accepted changes.

The latest dev UI work is technically accepted with three nonblocking notes.
Preserve that implementation. In particular, the shared arena views, shared
radars, real scent trail, private readings and exploration memory must keep
working against the same published data.

Prior records:

- [Server R1 acceptance](server-refactor-r1-team-lead-review.md).
- [Archived dev UI packet](dev-arena-overview-delegation.md).
- [Dev UI acceptance and remaining notes](dev-arena-overview-team-lead-review.md).
- [Current server architecture](codebase/server-architecture.md).
- [Shared dev UI architecture](codebase/dev-arena-overview.md).

Follow the applicable repository instructions. Codex must not access `CLAUDE.md`,
including through recursive reads or checksum commands. Preserve all existing
dirty work. Do not stage, commit, reset, revert unrelated work, or change Git
configuration. If someone else changes a file during the assignment, stop and
realign with the owner.

## 2. Success means

A developer can trace:

`host step -> diagnostic capture -> owned queue/slot -> writer -> versioned file -> existing viewer`

The package name explains who owns the diagnostic state. Its public operations
are small and understandable. The host cannot accidentally call writer-internal
steps through a public procedure.

The simulation still has no dependency on diagnostics. Diagnostics never changes
a creature's knowledge, decision, movement, memory or learning.

This is one extraction, not a general-purpose logging framework.

## 3. Source-grounded starting map

These are responsibilities observed during the preceding source review. Audit
their current callers before editing; do not infer ownership from the prefix alone.

| Current file | Actual responsibility | Intended home |
| --- | --- | --- |
| `server/dev_ai_debug.odin` | `AI_Debug` lifetime; bounded job queue; main-thread capture sequence; writer thread; history, journals, delivery clocks, display-fan cache; decision-record assembly | `server/diagnostics/`, split into focused files where useful |
| `server/dev_replay.odin` | World capture and replay header, frames, limits and final status | `server/diagnostics/`; codec calls stay in the host |
| `server/dev_senses.odin` | Private sense projection and live senses publication | `server/diagnostics/` |
| `server/dev_search.odin` | Private search publication, plus an unrelated host reset-console notice | Publication in diagnostics; reset notice stays host-side |
| `server/dev_scent.odin` | Bounded host-field capture, quantization, levels/ages and live scent publication | `server/diagnostics/` |
| `server/dev_scenario.odin` | Validate launch scenario and start the session through simulation APIs | Stays in the host |
| `server/host_simulation.odin` | Tick coordination; record decisions, capture world, capture scent | Stays in the host; imports diagnostics |
| `server/main.odin` | Options, lifecycle and connecting subsystems | Stays in the host |
| `server/network.odin`, `server/protocol.odin` | Requests, reset authorization, wire encoding and sending | Stay in the host |

The useful separation is ownership, not moving everything named `dev_*`.

In particular, `dev_log_search_reset` only prints an accepted command's result.
Keep it with host coordination rather than adding a diagnostics public operation
solely to relocate that procedure. Keep its output and invocation unchanged.

Renaming the host scenario file to `scenario.odin` is permitted if useful, with
mechanical references updated. It is not a reason to move scenario state into
diagnostics.

## 4. Package boundary

Create `server/diagnostics/`.

Use responsibility names such as `writer.odin`, `journal.odin`, `replay.odin`,
`senses.odin`, `search.odin` and `scent.odin`. The exact private file split is
the coding agent's choice. Do not create a package per feed or procedure.

Dependency direction:

```text
server host -> diagnostics -> existing simulation/content/ai/perception/observations
server host -> existing simulation, workers, networking and codec

simulation/content/ai/perception/observations -X-> diagnostics or host
client/dev <- existing versioned files, unchanged
```

The diagnostics package must not import the host package, ENet, client scripts or
launch tooling. Do not create a `common`, `shared`, generic context or new
protocol package to break a cycle.

The expected host-facing operations are lifecycle/configuration, decision
recording, world capture and scent capture. Names such as `open`, `close`,
`options_valid`, `record_decisions`, `capture_world` and `capture_scent` are
appropriate; justify any additional public operation by a real caller.

Writer entry points, queue manipulation, journal rotation, view conversion,
hex/JSON helpers, delivery bookkeeping, replay writes, fan caching and
`publish_*` procedures are internal. Mark them package-private or file-private
as appropriate. A writer procedure passed to the thread API does not need to be
public to the host.

Publish only types and constants that an actual boundary needs. Do not claim that
hiding a type name makes its fields private: Odin field ownership remains a
convention. Document allowed readers/writers separately from compiler-enforced
procedure visibility.

## 5. Resolve the two real host dependencies

### World packet encoding and replay protocol version

Today `ai_debug_capture_world` calls `protocol_encode_session` and
`protocol_session_size`. The replay header also reads `PROTOCOL_HEADER[4]`.

Keep the codec authoritative in the host. Supply the diagnostics boundary with
the encoded packet, its valid length and the metadata needed for its existing
world record. Pass the protocol version from the host; do not duplicate or
hard-code another protocol authority.

Preserve the existing packet bytes and valid length. If using a slice or pointer,
copy the bytes into owned bounded storage before the capture operation returns.
Never queue a borrowed stack buffer or a pointer into the live session.

Preserve the disabled path: when diagnostics is absent, do not encode and copy an
extra world packet every tick merely because encoding moved to the caller.

Do not change packet capacity, protocol fields or replay framing to simplify this
extraction. Add focused coverage for packet lifetime/length and disabled capture.

### Launch options

Today `ai_debug_options_valid` accepts the host's entire `Options` struct but
checks only the development flag, bind address, output directory and run ID.

Use those explicit values or a small diagnostics-specific configuration. Do not
move `Options` into diagnostics or pass the entire host context.

Preserve rejection messages and behavior, debug-build gating, loopback restriction,
absolute-directory requirement and missing-directory behavior. A release build
must continue to reject diagnostic launch options and run normally without them.

## 6. Ownership, timing and behavior invariants

The diagnostics state has one stable allocation from open to close. Preserve
which thread owns each counter, queue, file, history, cache and clock.

Main-thread capture can synchronously read the relevant simulation values, but
must not retain live simulation pointers. Prefer focused inputs; do not build a
large duplicate world/context structure just to avoid an honest borrowed read.

The one intentional diagnostic mutation of caller-owned temporary data is the
confirmed Outcome trace appended to the response trace. Preserve its timing and
exactly-once behavior. Do not mutate the adopted agent or session through that
path.

Preserve these existing properties:

- Decision recording happens after both authoritative resolutions, then world capture, then scent capture.
- Before/after agent values, pre-resolution facing, confirmed position/facing, receptor audits, worker timings and sample provenance retain their meanings.
- Both brain jobs are still submitted before collection. Their thread/mailbox code is not part of this refactor.
- Only copied jobs cross the diagnostic queue. The writer alone owns serialization, file writes, history processing and fan computation.
- Queue capacity, drop policy, sequence behavior, history limits and oversized-record accounting remain unchanged.
- Shutdown drains pending work, publishes final state, finishes the replay, joins the writer, then releases its buffers and grid copies.
- The separate scent lock protects the same capture slot. Copy only when the existing field/round/map rules require it; invalidation and stale handling remain unchanged.
- Scent levels, classes, quantization, newest-deposit ages and byte limits remain unchanged.
- Fresh-sample publication, periodic publication, draining between owner snapshots and separate scent cadence remain unchanged.
- No new allocations, JSON work, file work, blocking waits or extra full-agent/full-field copies are added to the simulation hot path.
- Diagnostic errors remain contained. Attaching, disabling, overflowing or closing diagnostics must not change authoritative gameplay.

Document the exact producer/consumer lifetime at each public boundary. Do not
describe a mutex as protecting fields it does not actually protect.

## 7. Compatibility and exclusions

Keep every current filename, schema, field name, unit, class ordering, enum
meaning, run/fingerprint binding, timestamp origin, sequence and reset rule.

Current recorded contracts include protocol 11, AI trace 5, senses 4, search 2,
scent 1 and replay envelope 5. Confirm them in the starting tree and preserve
that tree's values; this packet does not authorize a version bump.

The viewer must still distinguish developer-only host field data from private
nose readings and personal exploration memory. Nothing may infer a scent
emitter's identity or feed host truth into creature knowledge.

Excluded from implementation scope:

- All Godot production code, shared dev UI, radar drawing, minimap behavior and feature-specific readers/controllers.
- Server simulation, content, AI, perception and observations behavior or APIs.
- Networking behavior, action validation, reconnect, audience delay and packet formats.
- Scent/perception algorithms, gameplay tuning, random draws and tick ordering.
- Per-tick hashes, new replay/determinism architecture, new telemetry and log-volume features.
- Global event buses, plugins, generic serializers, dependency-injection frameworks and other future-feature scaffolding.
- Unrelated bug fixes, formatting sweeps and broad documentation rewrites.

The three P3 notes from the dev UI review remain separate cleanup work: plot-only
clipping, the uncalled Python overview helper and the pixel-count wording.
Do not fix them inside this extraction or present them as closed.

## 8. Test placement and API discipline

Move tests with the responsibility they test. Keep end-to-end host tests in the
host. Do not make writer internals public just to avoid moving a test.

Starting points:

- `server/dev_senses_test.odin`: diagnostic projection and delivery-clock tests belong with diagnostics.
- `debug_journals_rotate_and_shutdown_publishes_complete_history`, `worst_case_record_fits_the_declared_ceilings` and `oversized_diagnostics_are_dropped_and_counted_without_touching_gameplay` currently live in `server/brain_workers_test.odin`; separate their diagnostic responsibilities from the worker-equivalence tests.
- `scent_field_capture_matches_the_field_and_its_publication_stays_bounded` currently lives in `server/host_simulation_test.odin`; put internal capture/publication checks in diagnostics while retaining meaningful host capture-wiring coverage.
- Keep serial/threaded equivalence, audience isolation, lifecycle replacement, trace loss and delivered-coverage integration exercised through `host_simulation_step`.

Preserve every baseline assertion and its measurement. Do not replace a
deterministic no-writer queue-saturation test with a timing-sensitive writer race.
If an external test genuinely requires special construction or inspection,
isolate and document that test-only path rather than pretending it is production
API.

Provide a baseline-test-to-destination map. Identify splits and additions
explicitly. Independent review probes and fixtures are not to be weakened or
rewritten. Ask before a necessary change to a reviewer-owned probe.

Run `odin test server/diagnostics` without ENet in normal and debug builds.
Update `check_session` and `check_ai_debugger` so normal discovery includes the
new package. A dedicated package target is optional; `make check` must not
silently lose coverage. Keep `check_arena_overview` and the existing review gates.

## 9. Bounded execution plan

1. Audit the current public callers, state/thread ownership and test placement. Freeze the exact starting dirty tree and establish its build/test baseline.
2. Define the small public boundary, private helpers and packet ownership. Plan the extraction, host wiring, test moves and discovery changes together.
3. Apply the focused extraction. Keep mechanical moves/renames distinguishable from dependency-seam changes and readability changes.
4. Run the focused gates and then full integration/graphical checks. Compare against the preserved baseline, record gaps and hand back for independent review.

Keep changes small enough to review by responsibility. Do not keep polishing
unrelated code after the boundary is complete. If the extraction requires changes
to an excluded system, stop and propose the narrow exception first.

Code must explain itself with names, small focused procedures and clear flow.
Comments are plain-language explanations for non-obvious reasons, not narration.
No comment block may exceed three physical lines. Put deeper explanations in
`docs/codebase/`, not large code comments.

## 10. Baseline and verification contract

Use a fresh evidence root such as
`build/verification/server-diagnostics-<UTC timestamp>/`, with `.keep-logs`.

Record a buildable pre-edit source snapshot, content/path manifests, tool versions,
build flags, environment and exact commands. This baseline is the currently
accepted dirty tree, not an old commit or the pre-UI baseline.

Protect the accepted Godot implementation, content, fixtures, tools and the lower
server packages with pre/post hashes and scoped path lists. A hash manifest alone
does not detect new unlisted files. Preserve filenames containing spaces when
parsing manifests, and exclude `CLAUDE.md` from all access by Codex.

Do not run a baseline and candidate workload concurrently when comparing costs.
Keep both raw logs, commands and exit codes. A prior report is context, not a
substitute for a fresh run against this source identity.

### Required gates

| Gate | Required evidence |
| --- | --- |
| Pre-edit debug build and `make check` | Starting source and any existing failures |
| Candidate `make build_server` | Successful debug host build |
| Diagnostics package, normal and debug | Isolated tests without ENet |
| `make check_session check_ai_debugger` | Existing/new package discovery, worker/diagnostic integration and release rejection gate |
| Optimized release host build | Existing build flags; no diagnostic linkage/configuration regression |
| `make check` | Full suite, explicit test/PASS accounting and unchanged independent fixtures |
| Graphical AI debugger workflow | Writer/journals, viewer responsiveness, capture/replay, closing and cleanup |
| Graphical senses workflow | Private readings, separate clocks, stale recovery, paused brain, arena/local views and lifecycle |
| Graphical scent workflow | Real moving trail and decay, both minimaps/F8 agreement, privacy, reset and recorded olfaction |
| Graphical development workflow | Launch, source reload, failed-save recovery and cleanup |
| Release client smoke checks | Connection, selection, arena selection, movement and audience delay |
| Before/after source identity | Candidate unchanged by gates; protected scopes unchanged |

Use the existing graphical entry points:

```sh
python3 tests/ai_debugger_check.py --godot=godot --odin=odin --graphical
python3 tests/senses_windows_check.py --godot=godot --odin=odin --graphical
python3 tests/scent_check.py --godot=godot --odin=odin --graphical
python3 tests/dev_workflow_check.py --godot=godot --odin=odin --graphical
```

Respect configured tool paths if they differ. Record display availability;
headless execution alone is not rendered or physical-input proof.

### Comparisons that matter for this extraction

- Verify the host-supplied packet/version seam against existing exact wire fixtures. Add focused packet-copy lifetime and nil/disabled-path coverage.
- Keep the existing gameplay equivalence tests with diagnostics absent, attached and dropping records.
- Compare baseline/candidate record fields and schemas for the same controlled scenario. Normalize only genuinely variable metadata such as run paths and wall-clock timing; list every normalization.
- Decode and seek a recording produced by the preserved baseline host through the existing matching-content client harness. Keep legacy replay coverage. Do not confuse content-fingerprint mismatch with protocol incompatibility.
- Exercise normal close, overflow, oversized records, size-limit status, failed output, invalidation and reset with existing checks or focused additions where coverage is missing.
- Measure representative host cost with diagnostics on and off, queue/drop behavior, field capture and viewer delivery on the same machine/content/seed/build flags. Explain any repeatable regression before attempting unrelated optimizations.
- Preserve the existing graphical delivery p95 threshold. Report maximum latency separately; a passing p95 is not a maximum-latency guarantee.
- Preserve fresh captures, bounded timing data and source identities. A compilation pass does not prove a trail, private-data separation or a readable viewer.

If a gate fails, report the failure and cause without removing assertions,
increasing tolerances or changing fixtures merely to turn it green. Separate any
proposed behavior fix from this structural refactor.

## 11. Allowed files and documentation

Expected source scope:

- New `server/diagnostics/` code and owning tests.
- Removal/movement of the five diagnostic source files listed above, retaining the host-only reset notice.
- Narrow host wiring in `main.odin`, `host_simulation.odin` and any genuinely affected host caller.
- Host scenario naming only if chosen, with no behavioral changes.
- Diagnostic test moves and narrow host-test integration updates.
- Makefile test discovery and focused additional tests.
- Live architecture documentation and the handback.

Do not change Godot production files or lower server packages. Existing external
integration scripts should normally run unchanged; justify any necessary
mechanical path/import adjustment before broadening the scope.

Update `docs/codebase/server-architecture.md` and relevant live file-map/build
references. Add a focused `docs/codebase/server-diagnostics.md` explaining:

- Where new diagnostic output belongs and how an existing feed flows end to end.
- Which thread owns which state, and when borrowed inputs become owned copies.
- Every public production operation and its external callers.
- Which procedures are private, and which field ownership rules are conventions.
- Debug/release gating, queue/shutdown behavior, compatibility and test commands.

Keep historical reports intact. The current dev UI acceptance remains separate;
this task neither redesigns it nor erases its outstanding notes.

## 12. Handback

Write `docs/server-diagnostics-coding-agent-report.md`, marked
**READY FOR INDEPENDENT REVIEW, NOT ACCEPTED**.

Include:

- Starting/final source identities, preserved baseline and evidence paths.
- Responsibility/file map, dependency direction and production API/visibility audit.
- Thread/lifetime map, including packet buffer ownership and disabled-path behavior.
- Exact changed files, test relocation/assertion map and deliberate additions.
- Commands, exit codes, test totals, rendered evidence and performance comparisons.
- Baseline/candidate compatibility results and any unavailable, failed or untested coverage.
- Any remaining risks or separately proposed changes.

All changes stay unstaged and uncommitted. You may append one handback link to
this packet; do not rewrite its scope or acceptance criteria.

The Team Lead will independently review and test the candidate. This assignment
is complete only when its boundary is clearer and the existing game and dev
viewers still behave the same, not merely when files have moved.

---

Handback: [server diagnostics coding-agent report](server-diagnostics-coding-agent-report.md) (READY FOR INDEPENDENT REVIEW, NOT ACCEPTED).
