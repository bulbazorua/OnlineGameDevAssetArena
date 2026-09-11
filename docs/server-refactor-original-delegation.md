# Server refactor: ownership, readability, and regression preservation

Updated **2026-09-12**. **Status: ready for coding-agent implementation; not yet
implemented or accepted.** The previous olfaction assignment remains closed in
[its archived packet](06r-olfaction-closed-delegation.md). Its historical passing
results are not a baseline for this assignment.

## Assignment and roles

Refactor the existing Odin server so a human can find a feature, identify its
state owner, follow its execution, and understand its dependencies. Preserve the
working multiplayer game and development tools. The owner has approved this
structural cleanup, with implementation delegated to the coding agent.

The owner passes this packet to the coding agent and returns the completed
report to the Team Lead. The coding agent owns investigation, implementation
choices, staged changes, and its verification evidence. The Team Lead reserves
its work for independent code review and regression testing. A coding-agent
report saying PASS is required evidence, not final acceptance.

Proceed through the authorized stages without seeking approval for routine
implementation choices. Surface a decision if it requires changed gameplay,
changed compatibility, wider scope, or an unresolved regression. Do not expand
this assignment to solve that decision silently.

Follow the repository instructions appropriate to your agent. Codex must not
access `CLAUDE.md`. Keep changes unstaged and uncommitted. Preserve unrelated
work, accepted fixtures, historical reports, and existing recordings. Do not
publish, deploy, or change Git/host configuration.

## Outcome and scope

- Make startup, authoritative simulation, content ownership, and host adapters
  understandable through package names, file responsibilities, and small APIs.
- Preserve the existing `ai`, `perception`, and `observations` boundaries where
  they already provide clear separation.
- Make session lifecycle and the perception-to-action sequence easy to follow.
- Reduce access to unrelated mutable state and make allowed mutations explicit.
- Preserve runtime behavior, performance, diagnostics, and test discovery.
- Change Godot code only where the server refactor demonstrably requires a
  compatibility or integration adjustment. Preserve its established structure.

Do not add learning, persistent memories, combat mechanics, senses, creature
variations, players, or match capacity. Do not change algorithms, tuning,
serialization, transport, worker scheduling, or replay architecture as cleanup.
Do not introduce ECS, services, an event bus, generic dependency injection, a
plugin framework, or a catch-all `common`/`shared`/`utils` package.

The current inspected AI implements observation and search with Hold, Move, and
Face intents. Mood and learned memory are explicitly marked unimplemented in
the orchestrator. Future design documents are not evidence of shipped features.

## Source-grounded starting points

These are audit leads from the Team Lead's source inspection, not permission to
infer a dependency from a filename. Inspect current definitions and callers.

| Area | Current evidence | Refactoring concern |
| --- | --- | --- |
| Startup and fixed step | `server/main.odin`: `run_host`; `server/simulation.odin`: `simulation_tick` | Host coordination, simulation work, worker execution, and diagnostic capture need clear boundaries. |
| Session and entity lifecycle | `server/session.odin`; `server/movement.odin`: `Character`, `session_tick`, `session_enter_arena`; `server/trainers.odin`: `session_next_entity` | Lifecycle and state definitions are distributed across movement and trainer responsibilities. |
| Battle decisions and actions | `server/battle.odin`: `battle_tick`; `server/brain_workers.odin`; `server/character_actions.odin` | Preserve preparation, both decisions, ordered resolution, feedback, and diagnostic capture while exposing their sequence. |
| Sensing and private knowledge | `server/senses.odin`; `server/perception/`; `server/observations/`; `server/ai/` | Keep privileged world queries outside brain inputs and preserve independent sample and memory clocks. |
| Commands and publication | `server/network.odin`: `network_receive`; `server/session.odin`: `session_apply`; `server/protocol.odin` | Wire commands, session operations, development resets, and public snapshots currently share the root package. Resolve dependency direction before extraction. |
| Content and static arenas | `server/content.odin`, `content_senses.odin`, `characters.odin`, `arena.odin` | Define catalog lifetime and query ownership. `content_hash_file` currently depends on `protocol_write_u32`; preserve digest bytes when removing that dependency. |
| Audience and developer tools | `server/audience.odin`, `dev_ai_debug.odin`, `dev_replay.odin`, other `dev_*.odin` | Preserve delayed timelines, copied captures, bounded queues, schemas, and writer lifetime. |
| Godot integration | `client/network/game_connection.gd`, `protocol.gd`; `client/session/session_snapshot.gd`; `client/dev/` | Preserve decoding, snapshot continuity, interpolation inputs, and diagnostic readers. |

Read [battle runtime lifecycle](codebase/battle-runtime-lifecycle.md),
[opponent search](codebase/opponent-search.md),
[olfaction](codebase/olfaction.md), and [the protocol record](protocol.md)
alongside the corresponding production code.

## Readability and encapsulation requirements

- Use names that describe the domain operation and the state being changed.
  A coordinating proc should reveal the sequence through meaningful calls.
- Split a proc when a helper names a coherent responsibility. Avoid arbitrary
  length limits, trivial forwarding chains, and one package per proc or type.
- Keep ordinary control flow readable. Short code does not mean compressed
  statements, dense expressions, or generic names with unexplained flags.
- Prefer clear code to comments. A comment explains a non-obvious reason or
  constraint in plain, everyday words, preferably in one line.
- A comment block must never exceed three physical lines. Do not use adjacent
  blocks to bypass the limit. Put deeper explanations in `docs/codebase/`.
- Define the public API and permitted mutation paths before extracting a
  package. Use the existing Odin private/file-private conventions for helpers.
- Avoid exposing mutable internals through convenience accessors. Document
  returned values and borrowed data where ownership or lifetime is non-obvious.
- Give helpers the state they need. The owning coordinator may receive its
  complete runtime; unrelated lower-level helpers should not receive it.
- Do not force Godot to mirror Odin packages or add a generic shared-source
  directory for the cross-language protocol.

## Proposed boundaries

Start with these candidates and justify the final boundaries through actual
dependencies. A cohesive flat package is acceptable. Every extraction must
explain a smaller API, clearer owner, independent testability, or a more local
future change; folder appearance alone is insufficient.

| Location | Intended responsibility |
| --- | --- |
| `server/` | Executable startup and host adapters: connections, publication, worker execution, and development output. |
| `server/content/` (candidate) | Catalog loading, validation, definition storage, immutable arena data and queries, and allocation lifetime. |
| `server/simulation/` (candidate) | Authoritative session and entity lifecycle, battle runtime, sensing schedules, and action resolution. |
| `server/ai/` (existing) | Private memory and decision operations for one supplied creature agent. |
| `server/perception/` (existing) | Sensory calculations supplied with host-authorized world inputs. |
| `server/observations/` (existing) | Permitted evidence contracts without world lookup capabilities. |

Host coordination calls into simulation and supporting packages. Lower-level
simulation and decision code must not import startup, sockets, UI, or file
writers. `ai` continues to depend on `observations`, without importing world
query capabilities. Content may retain its current perception/profile
relationships. Do not erase necessary domain distinctions to break a cycle.

Simulation stores each creature's private runtime; AI procedures operate on the
supplied agent, and workers use independent copies. Keep application wiring
explicit. Choose the smallest concrete contracts that express this relationship.
The coding agent owns their implementation; this packet does not prescribe a
framework or exact proc signatures.

## Behavior that must survive

### Authority and public compatibility

- The connection supplies the player's role. Preserve command validation,
  revisions, round IDs, stale-input handling, no-op behavior, and membership
  cleanup after failed sends or disconnection.
- Preserve the protocol's current version, bytes, sizes, identifiers, channels,
  reliability choices, and Godot validation and interpolation behavior.
- Preserve content file ordering, digest framing, bytes, accepted schemas,
  validation, and the cross-language compatibility fingerprint.
- Keep public session state separate from private brains and host diagnostics.
- Spectator release uses monotonic wall time, not simulation ticks. Repeated
  Hello, reconnect, and rejection paths must stay on the permitted timeline.
- Preserve independent historical snapshots. Adding reference-owned fields to
  a value-copied record requires a deliberate copy/lifetime design.

### Simulation, cognition, and lifetime

Preserve the observed order, including the pre-step `was_unlocked` decision:

```text
session_tick
battle_sync
scent_environment_tick
senses_prepare
prepare both decision contexts
decide for both creatures
resolve each intent, then record that creature's confirmed result
capture world and scent diagnostics
```

Publication remains in its existing host-loop phases, including dirty session
publication during network polling. Do not silently move it across simulation
steps. Preserve fixed-step/catch-up behavior and snapshot cadence.

- Sample both creatures from the same world phase before either creature acts.
  Preserve retained samples, original evidence times, and independent receptor
  schedules. Re-reading a sample must not create new experience.
- Keep world truth, permitted observations, personal knowledge, public state,
  and host-only diagnostic evidence distinct. Hidden changes must not alter a
  creature's decisions without a change to its permitted inputs or own state.
- Preserve capacities, retention and expiry, eviction/tie rules, search defaults,
  seed derivation, random streams, and the order/count of random draws.
- Round reset clears the appropriate battle state. Replacing one creature
  preserves the other creature's runtime and leaves old ground scent intact.
- Keep walk preparation, turn timing, trainer input/energy, summoning, terrain
  movement, target alerts, and confirmed action feedback unchanged.
- Submit both worker requests before collection and preserve resolution order.
  Maintain serial/worker equivalence, mailbox synchronization, shutdown, and
  stable addresses for started workers and the diagnostic writer.
- Preserve independent copied worker inputs. Slices, pointers, dynamic arrays,
  allocators, and borrowed content may not introduce shared mutable memory or
  outlive their owners through an extraction.

### Diagnostics and development workflows

- Keep JSON serialization, file output, and display geometry on their current
  appropriate threads. Preserve queue bounds, drop behavior, and failure counts.
- Treat trace, live-senses, search, scent, and replay payloads as consumed APIs.
  Directly serialized agent fields and enum names are compatibility-sensitive.
- Preserve replay decoding and seeking for actual pre-refactor recordings,
  including supported historical versions. Retain the original fixtures.
- Preserve development startup/reload, the two clients and companion windows,
  private feeds, overlays, saved controls, reset, and loopback/debug restrictions.
- Do not fix historical inspector memory usage, recording limits, or unrelated
  issues under this assignment. Record newly exposed issues separately.

## Work stages and evidence

### Stage 0: reproducible baseline before runtime edits

Record the starting source identity, including local changes, tool versions,
environment, content, and build flags. Preserve an isolated buildable baseline
source snapshot and its evidence so the Team Lead can reproduce comparisons.
A commit ID alone does not identify a dirty source tree.

Run the existing server build and full checks before refactoring:

```sh
make build_server
make check
```

Retain commands, exit codes, logs, and relevant recordings/captures under a
clearly named `build/verification/server-refactor-*` directory. The full suite
includes rendered probes and requires a display. A blocked check is not a pass;
record the reason and run applicable available checks. If an affected baseline
gate fails, report it before relying on that gate for the corresponding stage.
Do not repair unrelated failures or weaken checks to obtain a green baseline.

Identify the current test packages, public API consumers, source-staging rules,
and scenario workflows before moving files. Package moves must not silently
remove tests from normal verification.

### Stage 1: content and static arena boundary

Use the content/static-arena ownership boundary as the first extraction unless
current source provides a concrete reason it cannot stand independently. Record
the dependency and ownership map and the minimal API before changing it.

Keep parsing, validation, lookups, geometry results, allocation cleanup, and
fingerprints behaviorally identical. Update consumers and owning tests, then
run the affected checks before starting the simulation extraction. If another
small first boundary is necessary, explain why in the report; do not substitute
a broad rewrite.

### Stage 2: lifecycle and simulation boundary

Clarify lifecycle/state placement and the battle phases in small steps. Separate
mechanical moves from procedure cleanup so the changes remain reviewable.
Resolve command, execution, snapshot, and diagnostic dependencies before moving
the authoritative runtime into a package.

Record each stage's changed files, reason, verification, and remaining concerns.
Do not leave duplicate implementations, temporary compatibility layers without
a removal decision, or unrelated cleanup hidden in the final diff. No commits
are required or authorized to create these checkpoints.

### Stage 3: integration and final handoff

Update package test targets, public API consumers, the development runner and
staged-source fixtures as needed. Preserve test meaning when moving or adapting
tests; do not delete, skip, soften, or replace independent regression assertions
to make the candidate pass. List changes to independent review fixtures
explicitly for the Team Lead.

Use the existing targets according to the affected boundary:

| Concern | Existing verification starting points |
| --- | --- |
| Content and arenas | `make check_content check_arena_content check_session` |
| Commands, session and movement | `make check_connection check_selection check_arena_selection check_movement check_land check_trainers check_character_ai` |
| Sensing, search, workers and traces | `make check_vision check_search check_scent check_ai_debugger` |
| Audience timelines and cameras | `make check_audience_delay check_camera` |
| Development tools and views | `make check_dev check_senses_windows check_collision_overlay check_sense_overlay` |
| Final integration | `make build_server` followed by `make check` |

Keep the existing normal/debug independent vision and olfaction regressions in
the normal test path. Explicitly include every new Odin test package; testing
only the root server package is insufficient after extraction. Also build and
exercise the ordinary non-debug host configuration so debug-only behavior does
not conceal release integration failures.

Add focused characterization or regression tests only where an affected
contract lacks coverage. Tests should demonstrate behavior, ownership, or
compatibility, rather than duplicate implementation details.

Exercise two real Godot clients and an audience connection against the host.
Cover connection, selection, arena entry, summoning, trainer movement, creature
behavior, return/reset, and audience reconnect/delay. Run the existing graphical
scenarios for senses, scent, and AI diagnostics using their documented modes.
Headless integration, rendered evidence, and physical keyboard/mouse coverage
must be reported separately. Do not claim physical-input or exported-client
coverage from scripted or editor probes.

For affected hot paths, compare the baseline and candidate with the same build,
content, arena, seed, duration, hardware, and active windows. Use existing
measurements where possible; record their limits. Include memory, available
simulation/worker timing, and diagnostic queue/recording behavior where relevant.
Keep debug-enabled and debug-disabled results distinct. A worker timing measure
does not establish whole-server performance. Investigate material regressions
without changing gameplay or capacities to hide them.

## Deliverables

- Small, reviewable, unstaged server changes with necessary integration updates.
- `docs/codebase/server-architecture.md`: actual package responsibilities,
  dependency direction, state and allocation ownership, mutation paths, tick and
  thread flow, where features belong, and build/test/debug entry points. Update
  affected existing codebase documents to prevent conflicting explanations.
- `docs/server-refactor-coding-agent-report.md`: starting source identity,
  baseline results, final ownership map, staged change summary, changed files,
  changed tests/fixtures, exact reproduction commands, exit codes, evidence
  paths, comparison results, and any untested or blocked requirements.
- Reproducible baseline and candidate evidence, including source snapshots or
  equivalent exact source identification, protocol/content comparisons,
  representative scenario evidence, and actual replay compatibility evidence.

Mark the handoff **READY FOR INDEPENDENT REVIEW**, never accepted. Keep this
assignment's scope intact; add a concise handoff link/status if needed.

## Team Lead independent acceptance

The Team Lead reviews the final code and relevant test changes, checks that each
new boundary has an actual owner and small API, and independently reruns the
affected regressions and final integration gates on the reviewed candidate.
It compares against the retained baseline where a regression is disputed.

Review specifically checks hidden-information access, creature/reset isolation,
sample clocks, worker aliasing and lifetime, action ordering, command authority,
wire/fingerprint compatibility, delayed audience state, and diagnostic/replay
compatibility. It also checks readability without relying on long comments.

Acceptance requires a buildable candidate, preserved test coverage, successful
available regression checks, explained performance comparisons, and no known
new gameplay or multiplayer regression. Missing display, physical-input,
exported-client, or performance evidence remains an explicit limitation, not an
implied pass. The Team Lead reports findings and evidence to the owner before
the assignment is closed.
