# Configurable audience delay

The Odin host delays the spectator feed by **5 seconds by default**. Players receive live state. Audience clients receive only historical state, so removing client-side rendering code cannot expose current positions.

```sh
# Normal host: everyone joining as audience receives a five-second delay.
make run_server AUDIENCE_DELAY=5

# Isolated development scenario, with the same host-enforced setting.
make dev_arena P1=triangle P2=diamond ARENA=meadow_crossing AUDIENCE=2 AUDIENCE_DELAY=5

# Immediate spectator feedback for local testing.
make dev_arena AUDIENCE=1 AUDIENCE_DELAY=0

# Fractional seconds are supported too.
make dev_arena AUDIENCE=1 AUDIENCE_DELAY=1.25
```

`AUDIENCE_DELAY` accepts a finite number from **0 to 60 seconds**. The direct host flag is `--audience-delay=5`; the launcher accepts the same flag. Fractions are rounded up to whole milliseconds. Choose the value when starting the host; changing it requires a restart. The setting applies equally to explicit audience members and connections assigned to audience because both fighter slots are occupied. A viewer cannot override it through client arguments.

## One coherent spectator timeline

Selection, character picks, map choice, Ready status, countdown, movement, membership, and round resets all use the same delay. This prevents a live session update from leaking positions or revealing a new round ahead of the delayed world stream. Audience count is also historical on audience screens; player screens show the current count.

| Wall time | Players | Audience with a 5-second delay |
| --- | --- | --- |
| 10 s | P1 starts walking north | Sees state from about 5 s |
| 15 s | Sees current movement | Begins seeing that northward movement |
| 20 s | Returns to lobby | Continues watching the earlier arena |
| 25 s | Sees the current lobby/selection | Receives the return to lobby |

Welcome is immediate and includes the assigned delay. When a new host has insufficient history, viewers see a buffering message and receive no match state until history matures. A late join receives the latest sufficiently old state immediately; reconnecting does not reset or bypass the shared timeline. Repeated Hello replies and rejected commands never include the live round for delayed audience connections.

Audience camera pan, zoom, and follow selection remain local and immediate. Follow tracks the **delayed** character positions. Screens display the delay, while the development Ping value remains the actual network round-trip time; the intentional spectator delay is not added to Ping.

## Host implementation

`Audience_Stream` stores copies of `Session` in one bounded ring buffer shared by every spectator. It captures at most 20 frames per second, even when no spectators are connected. A frame becomes eligible only after the configured amount of **monotonic wall time** has elapsed. Simulation catch-up ticks cannot release it early.

The ring holds at most `ceil(delay_ms / 50) + 2` frames: 102 at the default five seconds, 1,202 at the maximum. Each frame is independent of live mutations. No queue is allocated per viewer. Zero delay bypasses the history and uses the original live broadcast path.

At release, revision changes produce a reliable full SessionState; ordinary arena updates use the existing unreliable WorldState channel. Joins are seeded with a full historical SessionState. Under a host stall, release advances to the newest eligible frame rather than sending a burst of every missed sample. Normal sampling/network/interpolation can add a little more latency; the configured value is a minimum information delay. Very short intermediate selection changes within one 50 ms sample can be coalesced.

| File / type | Responsibility |
| --- | --- |
| `server/audience.odin` / `Audience_Stream`, `Audience_Frame` | Bounded capture history and wall-time release |
| `server/network.odin` / `Network_Host`, `Client` | Split live/delayed recipients, historical joins/replies, per-viewer revision tracking |
| `server/main.odin` / `Options.audience_delay` | Validate seconds and drive history after simulation updates |
| `server/protocol.odin`, `client/network/protocol.gd` | Protocol 6 Welcome: assigned role and enforced delay in milliseconds |
| `client/network/game_connection.gd` | Remember/reset delay, explain buffering, format the delay label |
| `client/main.gd`, `client/world/game_arena.gd` | Show delay alongside selection and arena state |
| `Makefile`, `tools/dev_session.py` | Expose `AUDIENCE_DELAY` and account for it during launcher startup |
| `server/audience_test.odin`, `tests/audience_delay_check.gd` | Buffer timing/bounds and packet-level timeline checks |

This phase changes the protocol to **version 6** because Welcome now contains the delay. Update host and client together; incompatible versions are rejected. All other message layouts and player movement rules remain unchanged. Future gameplay messages such as attacks, damage, AI decisions, or results must also pass through this historical feed rather than broadcasting live events to spectators.

## Verification

```sh
make check_audience_delay
make check
```

The integration check records packets before client presentation and verifies the default delay for selection, movement, countdown, and reset, including explicit/overflow/late/reconnecting viewers and repeated Hello/command replies. It also checks immediate fighter movement and audience camera zoom. Other gameplay regression checks explicitly use zero delay. The development-workflow check validates bad values, zero-delay reloads, and a real launch with a 1.25-second delay.
