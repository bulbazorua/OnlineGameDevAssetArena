# Arena protocol, version 6

Checkpoint **3I** adds a host-enforced audience delay to the existing Lobby → Selecting → Countdown → InArena flow. Version 6 extends Welcome with the configured delay; restart host and clients together after updating from version 5.

## Transport and header

ENet over IPv4 UDP, default `127.0.0.1:7000`, with compression disabled. Odin uses pinned ENet 1.3.17; Godot uses [ENetConnection](https://docs.godotengine.org/en/4.6/classes/class_enetconnection.html) and [ENetPacketPeer](https://docs.godotengine.org/en/4.6/classes/class_enetpacketpeer.html) directly.

Both peers negotiate **two channels**. Channel **0** carries reliable ordered lifecycle messages. Channel **1** carries sequenced unreliable Input and WorldState packets (flags 0). There is no cross-channel ordering guarantee: a world update may arrive before the reliable arena-entry message, in which case the client ignores it and waits for the next update.

One application message per packet. Multibyte integers are explicitly **unsigned little endian**. No native struct layout or string terminator is sent.

| Offset | Field | Value |
| --- | --- | --- |
| 0–3 | Magic | ASCII `OGAA`, hex `4f 47 41 41` |
| 4 | Version | `06` |
| 5 | Kind | The message kind below |

## Messages

| Kind | Direction | Payload after header | Total bytes | Channel |
| --- | --- | --- | --- | --- |
| 1 Hello | Client → host | Join preference `u8`, content fingerprint `32 bytes` | 39 | 0 |
| 2 Welcome | Host → joining client | Assigned role `u8`, audience delay in milliseconds `u32` | 11 | 0 |
| 3 SessionState | Host → joined clients | Full state, detailed below | 32 or 72 | 0 |
| 4 StartSelection | Player → host | Expected round `u32` | 10 | 0 |
| 5 SelectCharacter | Player → host | Expected round `u32`, character ID `u16` | 12 | 0 |
| 6 SetReady | Player → host | Round `u32`, character ID `u16`, map ID `u16`, desired Ready `u8` | 15 | 0 |
| 7 ReturnToLobby | Player → host | Expected round `u32` | 10 | 0 |
| 8 CommandRejected | Host → sender | Sender-visible round `u32`, rejected kind `u8`, reason `u8` | 12 | 0 |
| 9 SelectArena | Player → host | Expected round `u32`, map ID `u16` | 12 | 0 |
| 10 Input | Player → host | Round `u32`, sequence `u32`, direction mask `u8` | 15 | 1 |
| 11 WorldState | Host → joined clients | Round `u32`, server tick `u32`, count `u8`, two character records | 55 | 1 |

Boolean values must be exactly 0 or 1. Exact message lengths, header, channel, and enum values are validated.

Hello preference 0 requests an available player slot, falling back to audience when both are occupied. Preference 1 requests audience even when player slots are free. Welcome role 0 means audience; 1 and 2 identify players. Character definition IDs are separate: 1 Circle, 2 Square, 3 Triangle, 4 Diamond. Runtime entity IDs identify individual spawns.

Authority comes from the welcomed connection. Commands never contain a claimed owner or position. Duplicate Hello returns the same Welcome and the latest state allowed for that connection: live for players, historical for delayed audience (or no state while the buffer warms up). It never changes membership. Audience members must reconnect to claim a vacant player slot; there is no automatic promotion.

## Shared content fingerprint

Both programs load canonical JSON from `client/content/data/`. The host accepts `--content-dir=<directory>`. The client also validates local character visuals and terrain atlas mappings before connecting.

The active files, in hash order, are **`arenas.json`, `characters.json`, `terrains.json`**. For each file, sorted by relative forward-slash path, SHA-256 receives:

```text
u32le(path byte length) + UTF-8 relative path + u32le(file byte length) + raw file bytes
```

Visual assets and Godot metadata are excluded. JSON whitespace changes affect the fingerprint. Use identical data and restart both programs after content edits. The fingerprint checks compatibility; it is not authentication. Version 6 fixes movement speed at **180 world units/second** and simulation frequency at **60 Hz**; those rules are implemented in both languages and require a protocol update if changed incompatibly.

The host checks the fingerprint before assigning membership. Mismatch disconnects with reason 2; the client shows **Update game content**. Invalid catalogs prevent startup or connection. Terrain IDs, rows, spawns, and footprint clearance are validated by both programs.

The current arena catalog uses **schema 2**: each map includes matching `rows` and `elevation_rows`, whose digits encode levels 0–3. Both sides reject malformed height rows. Legacy schema-1 maps are flat and remain supported for fixtures; older readers reject schema 2. Terrain and character catalogs remain schema 1. This content-schema change does not alter the version-6 wire layouts below.

## SessionState layout

| Offset | Field | Encoding |
| --- | --- | --- |
| 6–9 | Round ID | `u32` |
| 10–13 | Revision | `u32` |
| 14 | Phase | `0` Lobby, `1` Selecting, `2` Countdown, `3` InArena |
| 15 | Player mask | Bit 0 = P1 present, bit 1 = P2 present |
| 16–17 | Audience count | `u16` |
| 18–19 | Map ID | `u16`, zero in Lobby |
| 20–21 | P1 selected character ID | `u16`, zero means no selection |
| 22 | P1 Ready | `u8`, 0/1 |
| 23–24 | P2 selected character ID | `u16` |
| 25 | P2 Ready | `u8`, 0/1 |
| 26 | Countdown seconds | `u8`, 5…1 in Countdown, zero otherwise |
| 27–30 | Server tick | `u32`, increases once per fixed simulation step |
| 31 | World character count | `u8`, 2 in InArena, zero otherwise |
| 32 onward | Character records | 20 bytes each, layout below |

Welcome precedes the first full state on channel 0. Its delay field is at offset 7, unsigned little-endian milliseconds, range 0–60,000; fighters must receive zero. Players receive live full states when membership, phase, picks, readiness, or countdown change. Audience receives the same information from the host history after its configured delay (default 5,000 ms), sampled at up to 20 Hz. Late viewers receive the newest eligible historical state, never the current live countdown/positions. No state is sent during initial history warmup. See [audience delay](03i-audience-delay.md).

Revision increases per lifecycle change; movement only advances server tick. Round increases on selection start, a different map, ReturnToLobby, or fighter departure. Audience changes preserve the round and live entities. Reconnecting clears client revision/tick history.

Lobby has no picks, Ready flags, map, countdown, or characters. Other phases require both players and a known map. Ready requires a selected character. Countdown requires both Ready and no spawned entities. InArena requires both Ready and two unique entity IDs/owners, with definitions matching the selected characters. The client validates identities, catalog IDs, and position bounds before display.

## Character and WorldState layouts

Every character record uses these offsets relative to its start:

| Offset | Field | Encoding |
| --- | --- | --- |
| 0–3 | Runtime entity ID | `u32`, nonzero, allocated anew for each spawn |
| 4–5 | Character definition ID | `u16` |
| 6 | Owner | `u8`, 1 or 2 |
| 7–10 | X | `u32`, world units × 256, rounded |
| 11–14 | Y | `u32`, world units × 256, rounded |
| 15–18 | Acknowledged input sequence | `u32`, latest input used by a simulation step |
| 19 | Direction mask | `u8`, current host input direction |

WorldState has round at offset 6, server tick at 10, character count at 14 (always 2), and records at 15 and 35. The host sends full world state every third simulation tick, **20 Hz**. Snapshots carry no deltas, so one lost packet does not prevent decoding the next.

Clients ignore older/equal world ticks, packets from other rounds, and world packets received outside InArena. Serial comparison handles `u32` wraparound. Reliable membership updates can arrive after newer world updates; the client keeps the newer positions while applying the updated membership/revision.

## Selection, countdown, and return

- StartSelection requires two players, Lobby, and the current round. The first arena is the default. Simultaneous starts produce one new round; the other request becomes stale.
- SelectCharacter requires Selecting and a valid ID. Mirrors are allowed. Changing a pick clears only that player's Ready.
- SelectArena requires Selecting and a known map. Changing it clears both Ready flags and advances the round while preserving picks.
- SetReady requires Selecting and matching round, character, and map. It sets an explicit boolean. Repeating an already satisfied choice/Ready while Selecting returns unchanged state.
- The second Ready enters Countdown for **300 simulation ticks**. The host publishes 5 immediately to players, then 4, 3, 2, 1 at one-second intervals; delayed audience receives that countdown on its historical timeline. At zero it creates two characters at the map's spawn centers and enters InArena.
- Selection/Ready changes and movement are rejected during Countdown. Neither client can choose a different spawn or end the countdown early.
- ReturnToLobby is accepted from either fighter during Countdown or InArena. It clears picks, map, Ready, countdown, and entities while preserving connections.
- A fighter departure resets the session to Lobby; audience sees this reset on its delayed timeline. Audience departure only changes the count.

## Input, simulation, and presentation

Input offsets are round at 6, sequence at 10, and mask at 14. Direction bits are **Left=1, Right=2, Up=4, Down=8**; zero stops. Opposites cancel and diagonals are normalized. Bits outside 0–15 are malformed.

The client sends input every physics tick (60 Hz), including zero-mask heartbeats. The host retains only newer sequences for that connection's character; duplicates/older inputs are ignored without a reliable reply. Input cannot advance simulation. The host moves characters only at fixed steps, stops input after **15 steps without a newer heartbeat** (250 ms), and never accepts client coordinates. Packet bursts cannot increase movement speed. Initial input sequence is zero; the first normal sample is one.

Movement uses the selected character's circular footprint against blocked terrain and boundaries. X then Y collision resolution permits wall sliding. Grass, ground, sand, tall grass, and stairs are walkable; water, stone, forest, cliffs, and buildings block movement. A movement step between different elevation levels is allowed only when the difference is one and either endpoint cell is stairs. Host simulation and client prediction apply the same rule. Terrain bonuses and character-to-character collision are deferred.

The owner predicts movement locally, then reconciles from authoritative positions and acknowledged input sequences, replaying pending samples. Small visual corrections decay smoothly; corrections over 64 units snap. Prediction history is capped at 120 samples, and missing world updates suspend prediction after 500 ms. Remote characters interpolate over the 50 ms snapshot interval. Focus loss clears held keys. This provides immediate local response; Internet latency and packet-loss performance still require measurement.

## Rejections, limits, and disconnection

Well-formed commands that violate session rules receive CommandRejected and remain connected:

| Reason | Meaning |
| --- | --- |
| 1 AudienceReadOnly | Sender does not control a player slot |
| 2 WrongPhase | Action does not apply in this phase |
| 3 StaleRound | Request belongs to another round |
| 4 UnknownCharacter | ID is absent from the host catalog |
| 5 SelectionChanged | Ready does not match the selected character |
| 6 NeedTwoPlayers | Start requires both slots |
| 7 UnknownArena | Map ID is absent from the host catalog |
| 8 ArenaChanged | Ready names a different arena |

Malformed messages disconnect with reason **1**; content mismatch uses **2**. Membership is released exactly once. Host loss clears local identity, session, camera, and characters and returns the client to Lobby.

The host supports **4,095 total connections**, matching [ENet 1.3.17's peer limit](https://github.com/lsalzman/enet/blob/v1.3.17/include/enet/protocol.h). With two fighters, up to 4,093 slots are available for audience. This is a transport ceiling, not a measured viewer capacity. Hello/Welcome timeout is five seconds. ENet timeout factor is 32, minimum 1500 ms, maximum 5000 ms. Host packet cap is **128 bytes**, queued incoming data cap **4096 bytes per peer**.

Implementations: [Odin codec](../server/protocol.odin), [session rules](../server/session.odin), [movement](../server/movement.odin), [Godot codec](../client/network/protocol.gd), [connection](../client/network/game_connection.gd), and [arena presentation](../client/world/game_arena.gd). `make check` covers the content, session, connection, selection, countdown, movement, and camera checks.

Audience command rejection replies use the latest released historical round ID (zero before any history is available). They never expose the live round. Transport Welcome/disconnect and ENet ping remain immediate; gameplay, membership, and reset state use the delayed timeline.
