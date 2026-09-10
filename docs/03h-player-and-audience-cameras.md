# Player and audience cameras

Each Godot client owns its camera. Both characters' state is available to everyone; [checkpoint 3I](03i-audience-delay.md) now delays the audience feed by five seconds by default. Camera position, zoom, and follow choices stay local and immediate.

| Role | View | Controls |
| --- | --- | --- |
| Player 1 | Own character centered, fixed 150% zoom | WASD / arrows move the character |
| Player 2 | Own character centered, fixed 150% zoom | WASD / arrows move the character |
| Each audience member | Independent free camera; starts with the whole map visible | Wheel or + / − to zoom; right/middle mouse drag or WASD / arrows to pan |

Audience can use **0 / Home / Whole map** to reset the view, or **1 / 2 / Follow P1 / Follow P2** to follow a character. Following starts at 150%; zoom still works while following. Panning leaves follow mode and continues from the current position. The audience-only buttons also offer zoom in/out and show the current percentage. The minimum zoom fits the whole map; the maximum is 300%. Free camera centers stay inside the arena bounds.

For example, P1 can walk along the path while staying at the center of their window. P2 sees the same movement from their own centered view. One viewer can zoom in on P1, while another pans to the upper terrace. Neither viewer changes either fighter's camera or movement.

## Fighter centering

Fighters have no overview, follow-other-player, zoom, or pan controls. Tab no longer switches their view. The camera tracks the final rendered character position after local prediction and reconciliation, so camera follow adds no smoothing delay. During the countdown it centers on the assigned spawn.

The camera keeps the character centered even at the map boundary. This deliberately allows the dark background beyond the finite map to appear near its edges. Clamping the camera to the map would push the character away from screen center. Window resizing keeps the fixed zoom and centered character.

## Ownership and files

| File / class | Responsibility |
| --- | --- |
| `client/world/arena_camera.gd` — `ArenaCamera : Camera2D` | Role lock, free pan, cursor-anchored zoom, optional audience follow, zoom bounds, resize and input reset |
| `client/world/game_arena.gd` — `GameArena` | Supply the rendered follow target; route pointer/key input; update audience controls; preserve existing fighter input and networking |
| `client/world/game_arena.tscn` | Camera controller and separate audience control row |
| `client/main.tscn` | Let pointer events pass through the empty screen container to the arena |
| `tests/camera_check.gd` | Real Odin host and four clients in separate viewports; input routing, screen centering, independence, limits, resize, focus, HUD clicks and optional captures |

`configure_role()` resets camera state on a new round. Snapshots do not reset a spectator's view. `select_view()` enforces fighter ownership even if called directly. Pointer zoom starts only on unhandled world input, so HUD buttons remain clickable. Drag/key release and focus loss clear held camera input. Returning to the lobby disables the camera; the next arena starts with the role's default view.

No protocol, server simulation, movement packets, or shared content format changes are needed. This is presentation code and follows the existing validated development relaunch behavior for GDScript/scene edits.

Godot reference: [Camera2D centering, zoom and smoothing](https://docs.godotengine.org/en/4.6/classes/class_camera2d.html). Screen-center tests check the viewport transform as well as the camera node's position.

## Run and verify

```sh
make dev_arena P1=triangle P2=diamond ARENA=meadow_crossing AUDIENCE=2
make check_camera
make check
# Optional rendered captures of the same camera checks:
godot --path client --script ../tests/camera_check.gd -- --server="$PWD/build/server"
```

The graphical check saves player-center, player-at-boundary, audience follow/zoom, free-camera, and 800×760 overview screenshots in `build/verification/cameras/`. Checks inject input through each client's viewport; they do not substitute for physical mouse/keyboard testing or Internet performance measurements.
