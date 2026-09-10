# Checkpoint 3E: development overlay

Each client can display a **DEV / FPS / PING** panel in the upper-right corner, with collision visibility controls. The panel stays visible through Lobby, character/map selection, Countdown, and the arena, including audience windows. Each window reports its own FPS and round-trip ping to the Odin host. Collision geometry appears in the active arena only.

## Run in development mode

Run the host normally, then launch each desired window with `DEV=1`:

```sh
make run_server
make run_client DEV=1
make run_client DEV=1
make run_audience DEV=1
```

`DEV=1` passes the application argument `--dev`. Direct Godot launches can use:

```sh
godot --path client -- --dev --host=127.0.0.1 --port=7000
godot --path client -- --dev --audience --host=127.0.0.1 --port=7000
```

Normal `make run_client` and `make run_audience` runs have no overlay. The panel is instantiated only when `--dev` is present **and** `OS.is_debug_build()` is true. Release exports cannot enable it through that flag. [Godot debug-build detection](https://docs.godotengine.org/en/4.6/classes/class_os.html#class-os-method-is-debug-build)

`make dev_arena` already enables development mode on both players and any audience windows:

```sh
make dev_arena P1=archer P2=orc ARENA=tiny_swords_village
# Add AUDIENCE=1 for an independently controlled spectator window.
```

## Collision controls

- **F3 / Colliders:** show or hide all collision drawing while retaining the selected filters. Starts enabled in dev mode.
- **F4 / Filters:** expand or collapse the category checkboxes. Closing the panel keeps the drawings visible.
- **All colliders / None:** select all six collision categories or clear them. For buildings only, press None, then check Buildings.
- Filters belong to each window, survive lobby/round changes, and reset to defaults when that client restarts. They do not pause or modify gameplay.

| Filter | Color | What it shows |
| --- | --- | --- |
| Buildings | Orange | The blocked building cells used by movement, including cells hidden by building artwork |
| Blocked terrain | Red | All other solid terrain: water, stone, forest, cliffs, and future non-walkable terrain types |
| Elevation barriers | Purple | Edges between walkable cells where the entity center cannot cross to another height; legal stairs remain open |
| Map boundary | Yellow | World limits; the entire movement circle must stay inside them |
| Players / trainers | Cyan | Trainer ground circles, radius `GameProtocol.TRAINER_RADIUS` (currently 9.6 world units) |
| Characters / gladiators | Green | Each selected character's `footprint_radius` from the shared gameplay catalog (currently 12 world units) |
| Tile grid (reference) | Gray | Optional grid over all tiles, including walkable land; off by default, and not itself a collision shape |

The circles describe **movement against the environment**. Entity-to-entity blocking and combat hitboxes are not implemented yet. Decorative art without a gameplay blocker has no collider to draw. Sprite dimensions, body art bounds, and summon scaling do not resize these footprints.

Debug circles have a center cross and the category's cyan/green color. The thin team-colored ground rings are the existing ownership markers and remain visible when collision debugging is off.

The drawings use each client's displayed ground positions: prediction/correction for its trainer, interpolation for remote entities, and the delayed received timeline for an audience. They do not bypass audience delay or claim to display the host's instantaneous positions. They remain attached when the audience pans or zooms; player camera behavior is unchanged. Hidden, unrevealed characters have no drawn circle until materialization begins.

The controls accept mouse clicks without taking keyboard focus. Scrolling over the panel does not zoom an audience camera; outside the panel the normal camera controls work.

## Measurements and ownership

- **FPS** uses Godot's average rendered frame rate. It initially shows `--` until a positive sample is available. [Engine.get_frames_per_second](https://docs.godotengine.org/en/4.6/classes/class_engine.html#class-engine-method-get-frames-per-second)
- **PING** is ENet's smoothed round-trip time in milliseconds for this client's connection to the host. It uses existing transport measurements, including automatic ENet pings, so no application message or Odin change is needed. This measures transport RTT, not total input-to-display delay. [ENet peer statistics and automatic ping](https://docs.godotengine.org/en/4.6/classes/class_enetpacketpeer.html)
- Connecting/disconnected clients show **PING: --**, with immediate refresh on connection changes. FPS keeps updating while disconnected.
- Labels refresh every 250 ms. The panel uses a separate CanvasLayer above the screen and arena HUD, so cameras and screen transitions do not move it. Only the panel consumes mouse input; the rest of the overlay passes it through.

`client/main.gd` owns the development-mode gate. `client/ui/debug_overlay.gd` and `.tscn` own presentation and refresh timing. `GameConnection.get_ping_ms()` exposes a read-only value, returning `-1` without a connected host. Normal runs never instantiate or update the overlay.

`client/dev/collision_geometry.gd` builds cached static geometry from `ArenaCatalog.is_blocked` and `step_is_allowed`, the same rules used by movement prediction and mirrored in `server/arena.odin`. Buildings are distinguished by the shared `building` terrain key, not by a sprite's pixel bounds. The map and catalogs remain the source of truth.

`client/dev/collision_overlay.gd` draws that cached geometry above the arena art, and updates the four entity footprints after movement presentation each frame. The static draw commands rebuild on map/filter changes. Hiding colliders skips geometry collection and drawing. The overlay adds no physics bodies, server changes, packets, or authoritative gameplay state. Godot's built-in collision viewer cannot show the host's custom movement queries, so this overlay draws their shared geometry explicitly.

## Verification

Godot import/script checks passed, as did the existing five-client movement check with `--dev`. Separate graphical runs with two players and an audience verified visible FPS/ping in development mode and no overlay in normal mode. Those runs exercised selection, countdown, movement, disconnect/reconnect, and the minimum audience window size. Screenshots were inspected; logs and captures are under `build/verification/dev-overlay-*`.

Collision checks:

```sh
make check_collision_overlay
# Also render and capture the overlay with the same real-host scenarios:
godot --path client --script "$PWD/tests/collision_overlay_check.gd" -- --server="$PWD/build/server" --dev
```

`tests/collision_overlay_check.gd` checks all four maps against movement geometry, a stair/elevation fixture, two players plus delayed audience, summon sizing, independent filters, synthesized keyboard/mouse input, normal-mode absence, camera input, minimum window layout, and map changes. Graphical captures go to `build/verification/collision-overlay/`. This test uses synthesized input rather than a physical keyboard/mouse session.
