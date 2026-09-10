# Checkpoint 3D: countdown, arena entry, and movement

Historical checkpoint: [checkpoint 3G](03g-land-arenas.md) expands the maps, updates spawn positions, adds stair/elevation rules, and replaces the default player overview with a follow camera. Countdown and network replication remain as described here.

Implemented and verified locally. This user-requested checkpoint combines arena entry with the first authoritative movement slice. It does not add combat, AI, or terrain bonuses.

## Match flow

Both players Ready → host locks choices → **5, 4, 3, 2, 1** → the host creates two live characters at the chosen map's spawn cells. Players and audience see the same countdown and map; late viewers receive the current phase and state. A player leaving cancels the match and clears both picks. Either player may return everyone to the lobby; viewers may disconnect without changing the match.

The host advances at 60 fixed ticks per second. Countdown lasts 300 simulation ticks and publishes each displayed second. Lifecycle updates use reliable channel 0. Input and world-position updates use sequenced unreliable channel 1, so old movement packets do not hold up newer ones. The host sends full positions at 20 Hz.

## Movement and camera

WASD and arrow keys move only the connection's own character. The host receives direction bits, never client coordinates. It normalizes diagonals, applies a fixed 180-unit/second speed, blocks water/stone/boundaries using the shared footprint and grid, and slides along walls. Missing input heartbeats stop motion after 250 ms. Focus loss releases local keys.

The client predicts its own movement at 60 Hz, reconciles from host positions and acknowledged input sequences, and replays unacknowledged input. Small visual corrections are smoothed. Remote players and audience views interpolate between 20 Hz positions. The server remains authoritative.

Each game window has its own Camera2D, centered and zoomed to fit the selected arena with room for the HUD. Camera changes never modify world coordinates. Players see a white ownership ring; audience sees both player colors. Preview spawn markers are hidden in the live arena.

## Files and ownership

- `server/session.odin`: Countdown and InArena phases; countdown ticks, reset/return, and input permissions.
- `server/movement.odin`: live `Character`, fixed-step countdown/spawning, bounded directional input, movement and acknowledgement state.
- `server/arena.odin`: shared circle/terrain clearance used for spawn and movement.
- `server/main.odin`, `network.odin`: fixed-step loop, channel-specific sends, reliable lifecycle publication and 20 Hz world publication.
- `server/protocol.odin`: protocol 5, Input (10), WorldState (11), ReturnToLobby (7), countdown and entity records.
- `client/session/session_snapshot.gd`: live character state and server tick.
- `client/network/protocol.gd`, `game_connection.gd`: decode/validate world updates, ignore stale rounds/ticks, send input, keep reliable state and positions coherent.
- `client/world/character_movement.gd`: matching movement/terrain rules for local prediction.
- `client/world/game_arena.gd`, `.tscn`: world, Camera2D, countdown/HUD, character views, keyboard input, prediction/reconciliation and remote interpolation.
- `client/main.gd`, `.tscn`: route all clients to countdown/live arena, preserve existing selection screens.
- Tests extend the existing connection/content/selection checks and add countdown, movement authority, collision, camera, focus, late audience, and reset coverage.

## Wire outline

Protocol 5 uses explicit little-endian integers. Position fields use unsigned world units × 256; no native struct or floating-point byte layout is sent. Entity records contain runtime ID, character definition ID, owner, position, acknowledged input sequence, and applied direction bits. Reliable SessionState carries phase, countdown seconds, server tick and entity records. WorldState carries round, tick and both entity records; packets from previous rounds or older ticks are ignored.

Packet limit rises to 128 bytes for the full session packet with two entities. New scene rendering and movement are local/Internet-correctness checks; they do not establish WAN latency or maximum audience capacity.

## Run this checkpoint

From the repository root, use separate terminals:

```sh
make run_server
make run_client
make run_client
make run_audience
```

Start selection, choose a character in each player window, and optionally choose another arena. Press Ready in both windows. Every window shows **5, 4, 3, 2, 1**, then the two selected characters spawn. Focus either player window and move with **WASD or arrow keys**. P1 is blue; P2 is orange. The white ring identifies the character controlled by that window. Audience sees both moving characters and can join during the match. Return to lobby allows either player to reset and select again.

```mermaid
sequenceDiagram
    participant P1 as Player 1
    participant H as Odin host
    participant P2 as Player 2
    participant A as Audience
    P1->>H: Ready with selected character and map
    P2->>H: Ready with selected character and map
    loop 5, 4, 3, 2, 1
        H-->>P1: Countdown
        H-->>P2: Same countdown
        H-->>A: Same countdown
    end
    H->>H: Spawn both selected characters
    H-->>P1: InArena and spawn positions
    H-->>P2: InArena and spawn positions
    H-->>A: InArena and spawn positions
    P1->>P1: Predict rightward movement immediately
    P1->>H: Right held, input sequence
    H->>H: Move P1 at next fixed step; check terrain
    H-->>P1: Positions and acknowledged input
    H-->>P2: Same positions
    H-->>A: Same positions
```

## Verification

`make check` runs 14 Odin tests and six Godot checks. `make check_movement` runs the focused live-host check, including all countdown numbers, five-second duration, selected shapes, independent inputs, prediction with incoming snapshots paused, matching positions across five clients, audience joining during Countdown/InArena, input permissions/timeouts, focus loss, collision, fresh entities after replay, and reset on fighter departure. Existing selection checks also verify cancellation by leaving during Countdown.

Three separate graphical Godot processes were exercised with synthetic mouse and keyboard events. Both player cameras were current in their own windows. Final authoritative positions matched exactly in P1, P2, and audience: Triangle `(270, 240)` and Diamond `(496, 114)` in that run. Screenshots of countdown, spawns, movement, and the audience at the minimum window size were inspected under `build/verification/phase3d-*.png`. The graphical harness and logs also live there as ignored local verification artifacts.

Physical keyboard acceptance, WAN delay/loss, and maximum audience throughput have not been measured. The implemented slice is movement; combat and AI remain later checkpoints.
