# Checkpoint 3E: development overlay

Each client can display a small **DEV / FPS / PING** panel in the upper-right corner. It stays visible through Lobby, character/map selection, Countdown, and the arena, including audience windows. Each window reports its own FPS and round-trip ping to the Odin host.

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

## Measurements and ownership

- **FPS** uses Godot's average rendered frame rate. It initially shows `--` until a positive sample is available. [Engine.get_frames_per_second](https://docs.godotengine.org/en/4.6/classes/class_engine.html#class-engine-method-get-frames-per-second)
- **PING** is ENet's smoothed round-trip time in milliseconds for this client's connection to the host. It uses existing transport measurements, including automatic ENet pings, so no application message or Odin change is needed. This measures transport RTT, not total input-to-display delay. [ENet peer statistics and automatic ping](https://docs.godotengine.org/en/4.6/classes/class_enetpacketpeer.html)
- Connecting/disconnected clients show **PING: --**, with immediate refresh on connection changes. FPS keeps updating while disconnected.
- Labels refresh every 250 ms. The overlay ignores mouse input and uses a separate CanvasLayer above the screen and arena HUD, so cameras and screen transitions do not move it.

`client/main.gd` owns the development-mode gate. `client/ui/debug_overlay.gd` and `.tscn` own presentation and refresh timing. `GameConnection.get_ping_ms()` exposes a read-only value, returning `-1` without a connected host. Normal runs never instantiate or update the overlay.

## Verification

Godot import/script checks passed, as did the existing five-client movement check with `--dev`. Separate graphical runs with two players and an audience verified visible FPS/ping in development mode and no overlay in normal mode. Those runs exercised selection, countdown, movement, disconnect/reconnect, and the minimum audience window size. Screenshots were inspected; logs and captures are under `build/verification/dev-overlay-*`.
