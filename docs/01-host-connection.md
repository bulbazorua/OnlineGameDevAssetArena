# Phase 1: Connect the Godot client to the Odin host

Status: implemented and verified locally. This phase establishes the connection and assigns a player ID. The arena, character movement, and AI remain later phases.

Phase 1 is the historical connection checkpoint. The current build extends it with [colored shapes and audience joining](02-shapes-and-audience.md); the [protocol](protocol.md) now describes version 2.

## Run it

Run every command from the repository root. In the first terminal:

```sh
make run_server
```

In a second terminal:

```sh
make run_client
```

The client connects automatically to `127.0.0.1:7000`. The host logs `Player 1 connected; Welcome sent.`, and the game window displays **Connected — Player 1**.

Use **Disconnect** to leave, then **Connect** to join again. Address and port become editable while disconnected. If the host is unavailable, the client displays a timeout after about five seconds and allows retrying.

The host supports two player slots. A second player request receives Player 2 while the first remains connected. Additional clients now join as audience. These roles belong to active connections; reconnecting can reuse a released player ID.

To use another port:

```sh
make run_server SERVER_PORT=7100
make run_client SERVER_PORT=7100
```

The host binds to the local computer by default. For a later test between computers on the same network, use `make run_server SERVER_BIND=0.0.0.0`, then connect to that computer's reachable IPv4 address using the client fields or `make run_client SERVER_HOST=<host-ip>`.

## Requirements and build output

The current host build targets Linux. It needs Odin with `vendor:ENet`, a C compiler (`cc`), `ar`, and Python 3.12 or newer. The client uses Godot 4.6 and the Compatibility renderer.

The first server build downloads ENet **1.3.17**, verifies its SHA-256, and builds a static library under `build/deps/`. This version matches the installed Odin vendor bindings. The helper retains ENet's source and license in that folder. Downloading is required only when the source archive is absent; subsequent builds use the cached archive/library.

`build/server` is the host executable. Generated builds, dependency files, verification artifacts, and `client/.godot/` are ignored by Git. Godot `.uid` and `.import` sidecar files remain eligible for version control.

## What this phase proves

Godot's `ENetConnection` and Odin's ENet bindings exchange our own small [Hello/Welcome protocol](protocol.md). Both programs service their connection; the client only reports Connected after a valid Welcome arrives.

The client provides connecting, connected, disconnected, rejected, and timeout states. The server validates the Hello message before assigning the connection's player ID. ENet handles reliable delivery and connection-liveness checks.

## Verification

```sh
make check_client
make check_connection
```

`check_client` imports the Godot project and checks the main script. `check_connection` builds the host and starts its own local host on an available port. It exercises the actual client scene and verifies:

- Successful connection and the visible Player 1 label.
- A second connection with a distinct ID.
- Disconnect and reconnect through the button signal.
- Rejection of empty, malformed, unknown-message, and wrong-version Hello packets.
- Continued operation of the valid connection after those rejections.
- Detection of a stopped host and timeout when retrying without a host.

The screen was also rendered with Godot's OpenGL renderer, and synthetic mouse clicks exercised Disconnect and Connect. Local screenshots and logs are in `build/verification/`. Physical mouse/keyboard acceptance and Internet latency have not been tested.
