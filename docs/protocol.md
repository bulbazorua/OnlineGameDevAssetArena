# Arena protocol, version 11

Version 11 adds trainer running, authoritative energy and a separate movement-start clock. It retains version 10's public target-found flag and acquisition tick. Restart host and clients together. Private search memory, observations and target identity remain excluded. See [running and alert presentation](05c-trainer-running-and-target-alert.md) and [opponent search](06m-naturalistic-opponent-search.md).

## Transport and header

ENet over IPv4 UDP, default `127.0.0.1:7000`, with compression disabled. Odin uses pinned ENet 1.3.17; Godot uses [ENetConnection](https://docs.godotengine.org/en/4.6/classes/class_enetconnection.html) and [ENetPacketPeer](https://docs.godotengine.org/en/4.6/classes/class_enetpacketpeer.html) directly.

Both peers negotiate **two channels**. Channel **0** carries reliable ordered lifecycle messages. Channel **1** carries sequenced unreliable Input and WorldState packets (flags 0). There is no cross-channel ordering guarantee: a world update may arrive before the reliable arena-entry message, in which case the client ignores it and waits for the next update.

One application message per packet. Multibyte integers are explicitly **unsigned little endian**. No native struct layout or string terminator is sent.

| Offset | Field | Value |
| --- | --- | --- |
| 0–3 | Magic | ASCII `OGAA`, hex `4f 47 41 41` |
| 4 | Version | `0b` |
| 5 | Kind | The message kind below |

## Messages

| Kind | Direction | Payload after header | Total bytes | Channel |
| --- | --- | --- | --- | --- |
| 1 Hello | Client → host | Join preference `u8`, content fingerprint `32 bytes` | 39 | 0 |
| 2 Welcome | Host → joining client | Assigned role `u8`, audience delay in milliseconds `u32` | 11 | 0 |
| 3 SessionState | Host → joined clients | Full state, detailed below | 32 or 164 | 0 |
| 4 StartSelection | Player → host | Expected round `u32` | 10 | 0 |
| 5 SelectCharacter | Player → host | Expected round `u32`, character ID `u16` | 12 | 0 |
| 6 SetReady | Player → host | Round `u32`, character ID `u16`, map ID `u16`, desired Ready `u8` | 15 | 0 |
| 7 ReturnToLobby | Player → host | Expected round `u32` | 10 | 0 |
| 8 CommandRejected | Host → sender | Sender-visible round `u32`, rejected kind `u8`, reason `u8` | 12 | 0 |
| 9 SelectArena | Player → host | Expected round `u32`, map ID `u16` | 12 | 0 |
| 10 Input | Player → host | Round `u32`, sequence `u32`, direction/run mask `u8` | 15 | 1 |
| 11 WorldState | Host → joined clients | Round, tick, two gladiators, two trainers, summon ticks, four locomotion records, two target alerts and two trainer-energy records | 147 | 1 |
| 12 DevResetSearch | Development player → host | Expected round `u32` | 10 | 0 |

Boolean values must be exactly 0 or 1. Exact message lengths, header, channel, and enum values are validated.

Hello preference 0 requests an available player slot, falling back to audience when both are occupied. Preference 1 requests audience even when player slots are free. Welcome role 0 means audience; 1 and 2 identify players. Character definition IDs are separate: 1 Circle, 2 Square, 3 Triangle, 4 Diamond, 5 Archer, 6 Orc. Trainer definition ID 1 means Player1 in its separate definition namespace. Runtime entity IDs identify individual spawns and are unique across both families.

Authority comes from the welcomed connection. Commands never contain a claimed owner or position. Duplicate Hello returns the same Welcome and the latest state allowed for that connection: live for players, historical for delayed audience (or no state while the buffer warms up). It never changes membership. Audience members must reconnect to claim a vacant player slot; there is no automatic promotion.

`DevResetSearch` is a development-only addition within protocol 10; normal state packet layouts are unchanged. It requires a debug host with `--dev --bind=127.0.0.1`, the Search controller and completed summoning. The host validates connected, separated spawn positions before starting a new round with fresh runtime entities and private memories. Clients receive the normal reliable session update; delayed audiences and replay follow their existing timelines. Rejection reasons 9 (`DevOnly`) and 10 (`SearchResetUnavailable`) explain disabled tools or insufficient space. Older running hosts must be restarted before using the new debug command.

## Shared content fingerprint

Both programs load canonical JSON from `client/content/data/`. The host accepts `--content-dir=<directory>`. The client also validates local character visuals and terrain atlas mappings before connecting.

The active files, in hash order, are **`arenas.json`, `characters.json`, `senses.json`, `terrains.json`**. Olfaction changed `senses.json` to schema 2 and `terrains.json` to schema 3, so the fingerprint differs from earlier builds. For each file, sorted by relative forward-slash path, SHA-256 receives:

```text
u32le(path byte length) + UTF-8 relative path + u32le(file byte length) + raw file bytes
```

Visual assets and Godot metadata are excluded. JSON whitespace changes affect the fingerprint. Use identical data and restart both programs after content edits. The fingerprint checks compatibility; it is not authentication. Trainers walk at **120 world units/second** and run at **240**, at **60 Hz**. These rules and energy tuning are implemented in both languages and require a protocol update if changed incompatibly.

The host checks the fingerprint before assigning membership. Mismatch disconnects with reason 2; the client shows **Update game content**. Invalid catalogs prevent startup or connection. Terrain IDs, rows, spawns, and footprint clearance are validated by both programs.

The current arena catalog uses **schema 2**: each map includes matching `rows` and `elevation_rows`, whose digits encode levels 0–3. Both sides reject malformed height rows. Legacy schema-1 maps are flat and remain supported for fixtures; older readers reject schema 2. The terrain catalog is **schema 3** and requires an explicit `blocks_vision` boolean and a `scent` medium (`open`, `water` or `solid`) per terrain, each independent of `walkable` (water blocks walking, not sight, and carries scent briefly). `senses.json` (schema 2) holds profiles with a `vision` object and an `olfaction` object (`receptor`: enabled, `range_units` 0–32, `sample_interval_ticks` 1–60, `estimates_freshness`; `emitter`: enabled, `scent_class` human/orc, `intensity` 0–4), one `trainer_emitter`, and exactly one binding per selectable character; see [checkpoint 6B.1](06g-focused-and-peripheral-vision.md) and [6B.2](06n-olfactory-trails.md). The character catalog remains schema 1. These content-schema versions are separate from the version-11 wire layouts below.

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
| 32, 52 | Gladiator records | 20 bytes each, layout below; InArena only |
| 72, 92 | Trainer records | 20 bytes each; InArena only |
| 112–113 | Summon elapsed ticks | `u16`, 0–90; InArena only |
| 114, 120 | Gladiator locomotion records | 6 bytes each, same order as gladiator records; InArena only |
| 126, 132 | Trainer locomotion records | 6 bytes each, same order as trainer records; InArena only |
| 138, 143 | Creature target-alert records | 5 bytes each: active `u8` (0/1), acquisition tick `u32`; InArena only |
| 148, 156 | Trainer energy records | 8 bytes each; InArena only; layout below |

Welcome precedes the first full state on channel 0. Its delay field is at offset 7, unsigned little-endian milliseconds, range 0–60,000; fighters must receive zero. Players receive live full states when membership, phase, picks, readiness, or countdown change. Audience receives the same information from the host history after its configured delay (default 5,000 ms), sampled at up to 20 Hz. Late viewers receive the newest eligible historical state, never the current live countdown/positions. No state is sent during initial history warmup. See [audience delay](03i-audience-delay.md).

Revision increases per lifecycle change; movement only advances server tick. Round increases on selection start, a different map, ReturnToLobby, or fighter departure. Audience changes preserve the round and live entities. Reconnecting clears client revision/tick history. Within one round, entity identities must stay stable and summon progress cannot decrease.

Lobby has no picks, Ready flags, map, countdown, or characters. Other phases require both players and a known map. Ready requires a selected character. Countdown requires both Ready and no spawned entities. InArena requires both Ready, two gladiators matching the selected characters, and two trainers using definition 1. Each family has owners 1 and 2, and all four entity IDs are unique. The client validates identities, catalog IDs, position bounds, and monotonic summon progress before display.

## Entity and WorldState layouts

Every gladiator or trainer record uses these offsets relative to its start:

| Offset | Field | Encoding |
| --- | --- | --- |
| 0–3 | Runtime entity ID | `u32`, nonzero, allocated anew for each spawn |
| 4–5 | Definition ID within the record’s family | `u16` |
| 6 | Owner | `u8`, 1 or 2 |
| 7–10 | X | `u32`, world units × 256, rounded |
| 11–14 | Y | `u32`, world units × 256, rounded |
| 15–18 | Acknowledged input sequence | `u32`, latest input used by a simulation step |
| 19 | Input mask | `u8`, current host direction/run request; zero for autonomous creatures |

WorldState has round at offset 6, server tick at 10, character count at 14 (always 2), gladiator records at 15 and 35, trainer records at 55 and 75, summon elapsed ticks at 95, and gladiator locomotion records at 97 and 103, and trainer locomotion records at 109 and 115. Gladiator input masks and acknowledgments must be zero. Trainer masks must be zero during summoning. Neither packet includes a separate trainer count: two trainers are required whenever two gladiators exist. The host sends full world state every third simulation tick, **20 Hz**. Snapshots carry no deltas, so one lost packet does not prevent decoding the next.

Each six-byte locomotion record has:

| Relative offset | Field | Encoding |
| --- | --- | --- |
| 0 | Locomotion | `u8`: 0 idle, 1 walk, 2 run (trainers only) |
| 1 | Facing | `u8`: 0 north, 1 north_east, 2 east, 3 south_east, 4 south, 5 south_west, 6 west, 7 north_west |
| 2–5 | State start tick | `u32`; tick when locomotion last changed (spawn tick initially) |

Locomotion describes actual movement, not requested intent. Idle preserves the last
facing. A blocked move can cause a partial slide for its final tick, then idle.
The client rejects unknown values, future state-start ticks (serial comparison),
walking during summoning, or regressing state-start ticks within a stable entity.
Elapsed animation time uses wrap-safe subtraction. Stable locomotion does not
reset its start tick on each packet.

Trainer energy records are at offsets **131, 139** in WorldState and **148, 156**
in SessionState:

| Relative offset | Field | Encoding |
| --- | --- | --- |
| 0–1 | Energy | `u16`, 0–600 |
| 2 | Recovery delay remaining | `u8`, 0–60 ticks |
| 3 | Exhausted lock | `u8`, 0/1 |
| 4–7 | Movement start tick | `u32`, no later than the action start tick |

The movement clock preserves the original first-step preparation across walk/run
switches. The locomotion clock still starts each new animation. Audience history
and recorded world frames retain both clocks and energy values.

Clients ignore older/equal world ticks, packets from other rounds, and world packets received outside InArena. Serial comparison handles `u32` wraparound. Reliable membership updates can arrive after newer world updates; the client keeps the newer positions while applying the updated membership/revision.

## Selection, countdown, and return

- StartSelection requires two players, Lobby, and the current round. The first arena is the default. Simultaneous starts produce one new round; the other request becomes stale.
- SelectCharacter requires Selecting and a valid ID. Mirrors are allowed. Changing a pick clears only that player's Ready.
- SelectArena requires Selecting and a known map. Changing it clears both Ready flags and advances the round while preserving picks.
- SetReady requires Selecting and matching round, character, and map. It sets an explicit boolean. Repeating an already satisfied choice/Ready while Selecting returns unchanged state.
- The second Ready enters Countdown for **300 simulation ticks**. The host publishes 5 immediately to players, then 4, 3, 2, 1 at one-second intervals; delayed audience receives that countdown on its historical timeline. At zero it creates two trainers at the map’s spawn centers, reserves two gladiators on nearby clear land, and enters InArena with summon elapsed ticks zero.
- Selection/Ready changes and movement are rejected during Countdown. Neither client can choose a different spawn or end the countdown early.
- ReturnToLobby is accepted from either fighter during Countdown or InArena. It clears picks, map, Ready, countdown, and entities while preserving connections.
- A fighter departure resets the session to Lobby; audience sees this reset on its delayed timeline. Audience departure only changes the count.

## Summoning

The host increments summon elapsed ticks once per simulation step, saturating at **90** (1.5 seconds). Trainer input is suppressed throughout those steps; normal movement starts on the following step. Gladiator positions and IDs are present from arena entry but the client hides them before tick **36**. Trainers play the existing `advise` gesture; a procedural orb travels toward each summon location. From tick 36 a ring/particle effect and scale/opacity fade reveal the selected gladiator. Materialization reaches full size at tick 60; the gesture/effect ends at tick 90.

The client interpolates only between received summon values, freezes on a paused feed, and snaps to completion at 90. Audience history includes both entity families and this clock. A late viewer receiving a completed summon displays the resulting entities without replaying it. Reset/departure clears all views and effects; there are no delayed spawn callbacks. See [trainer and summon checkpoint](05a-trainers-and-summoning.md).

## Input, simulation, and presentation

Input offsets are round at 6, sequence at 10, and mask at 14. Bits are **Left=1, Right=2, Up=4, Down=8, Run=16**; zero stops. Run without a direction does not move or spend energy. Opposites cancel and diagonals are normalized. Bits outside 0–31 are malformed.

Each trainer begins with 600 energy. A translated running tick spends 2, allowing
300 running ticks (five seconds). A run step resets a 60-tick recovery delay;
walking or resting then restores one energy per tick. Exhaustion falls back to
walking and locks running until energy reaches 120 and Space has been released.
No client command can set energy. Summon locks, input timeout and collision apply
to both speeds. All resource and movement fields participate in reconciliation.

The client sends input every physics tick (60 Hz), including zero-mask heartbeats. The host retains only newer sequences for that connection's trainer; duplicates/older inputs are ignored without a reliable reply. Input cannot advance simulation. The host moves trainers only at fixed steps, stops input after **15 steps without a newer heartbeat** (250 ms), and never accepts client coordinates. Packet bursts cannot increase movement speed. Initial input sequence is zero; the first normal sample is one.

Trainer movement uses a **9.6-world-unit radius** circular footprint against blocked terrain and boundaries. X then Y collision resolution permits wall sliding. Grass, ground, sand, tall grass, and stairs are walkable; water, stone, forest, cliffs, and buildings block movement. A movement step between different elevation levels is allowed only when the difference is one and either endpoint cell is stairs. Host simulation and client prediction apply the same rule. Terrain bonuses and character-to-character collision are deferred.

The owner immediately predicts the walk action. Translation begins after 8 preparation ticks (133 ms); Player1 renders its first two walk poses in 33 ms each, then resumes normal clip timing. Releasing input, opposing keys, blocked terrain or an input timeout cancels preparation. Reconciliation copies authoritative position, locomotion, facing and state-start tick, then replays unacknowledged inputs through the same fixed-step motion rule. Small visual corrections decay smoothly; corrections over 64 units snap. Prediction history is capped at 120 samples, and missing world updates suspend prediction after 500 ms. Remote trainers use `CharacterMotionPresenter` and the received action clock, including preparation and stop boundaries. The player camera follows their trainer. Autonomous characters interpolate received positions and sample public locomotion/facing/state age. All clients treat them as remote; trainer input prediction never drives them. A stalled feed freezes at its last received character sample. Gaps over 30 ticks snap to the received state. Focus loss clears held keys. This provides immediate local response; Internet latency and packet-loss performance still require measurement.

## Autonomous character authority

The Odin `Simulation` owns private `Battle_Runtime` beside the public `Session`.
The host's default `Search` controller begins after summoning and proposes actions
from its own visual evidence and private history. The stationary `Observe`
controller remains available for receptor QA. Shared action rules produce the
public locomotion fields; turning changes facing by one 45° step per six ticks
without translation. Settings are host-owned: clients do not predict AI. Private
sightings, cues, scent readings, memory and the host scent field never appear in
player or audience packets. No AI command packet is accepted from fighters or audience.

`walk` begins with 12 ticks of stationary first-step preparation. Its state-start
tick includes that preparation; the first displacement is at start + 12. A legal
collision-resolved direction supplies the facing before translation. Godot uses
the same timing to keep interpolation out of preparation and finish translation
before an idle transition. This uses the existing character fields and host history.

Audience history copies public session values only, including these locomotion
records. It contains no agent pointers, private cognitive memory or random state.
The same delayed session/world encoders carry character position and action, so
no live AI side channel can bypass audience delay. See [checkpoint 6A](06b-autonomous-idle-walk.md).

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
| 9 DevOnly | Search reset requires a local debug host running Search |
| 10 SearchResetUnavailable | Connected ground cannot fit separated search spawns |

Malformed messages disconnect with reason **1**; content mismatch uses **2**. Membership is released exactly once. Host loss clears local identity, session, camera, and characters and returns the client to Lobby.

The host supports **4,095 total connections**, matching [ENet 1.3.17's peer limit](https://github.com/lsalzman/enet/blob/v1.3.17/include/enet/protocol.h). With two fighters, up to 4,093 slots are available for audience. This is a transport ceiling, not a measured viewer capacity. Hello/Welcome timeout is five seconds. ENet timeout factor is 32, minimum 1500 ms, maximum 5000 ms. Host packet cap is **256 bytes**, queued incoming data cap **4096 bytes per peer**.

Implementations: [Odin codec](../server/protocol.odin), [session rules](../server/session.odin), [movement](../server/movement.odin), [Godot codec](../client/network/protocol.gd), [connection](../client/network/game_connection.gd), and [arena presentation](../client/world/game_arena.gd). `make check` covers the content, session, connection, selection, countdown, movement, and camera checks.

Audience command rejection replies use the latest released historical round ID (zero before any history is available). They never expose the live round. Transport Welcome/disconnect and ENet ping remain immediate; gameplay, membership, and reset state use the delayed timeline.

## Target-found presentation

WorldState appends the same two five-byte records at offsets 121 and 126. An active alert is younger than 60 simulation ticks. Repeated packets preserve the original acquisition tick. This conveys a visible reaction only, with no target coordinates, identity or brain state. Delayed audiences use their historical session state. Protocol-9 and protocol-10 recordings use an explicit replay adapter. Version 9 receives inactive alerts; both old formats receive full trainer energy, no exhaustion and movement clocks copied from their old action clocks. Live transport rejects older versions. The creature body hop and its fixed ground shadow are sampled from acquisition age; replay pause and seek do not start local tweens.
