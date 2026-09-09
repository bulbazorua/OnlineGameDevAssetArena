.DEFAULT_GOAL := help

ODIN ?= odin
GODOT ?= godot
CLIENT_ARGS ?=
PYTHON ?= python3
SERVER_BIND ?= 127.0.0.1
SERVER_HOST ?= 127.0.0.1
SERVER_PORT ?= 7000
CONTENT_DIR ?= client/content/data

.PHONY: help build_server run_server run_client run_audience check_client check_session check_connection check_selection check_content check_arena_content check_arena_selection check_movement import_client check ccx cc

help:
	@echo "make run_server  - build and start the Odin host"
	@echo "make run_client  - start the Godot client"
	@echo "make run_audience - start a Godot client as audience"
	@echo "make check_client - import and check the Godot scripts"
	@echo "make check_session - check Odin session/content rules and protocol bytes"
	@echo "make check_connection - run the client/host integration check"
	@echo "make check_selection - check character selection with real clients and host"
	@echo "make check_content - check both content readers and wire fixtures"
	@echo "make check_arena_content - check terrain data, rendered cells, and coordinates"
	@echo "make check_arena_selection - check shared arena choices and Ready resets"
	@echo "make check_movement - check countdown, cameras, networked movement, and resets"
	@echo "make check - run all current checks"
	@echo "Options: SERVER_PORT=7000 SERVER_BIND=127.0.0.1 SERVER_HOST=127.0.0.1 CONTENT_DIR=client/content/data"

build/deps/libenet.a: tools/build_enet.py
	$(PYTHON) tools/build_enet.py

build_server: build/deps/libenet.a
	$(ODIN) build server -out:build/server -debug -extra-linker-flags:"-L$(abspath build/deps)"

run_server: build_server
	./build/server --bind=$(SERVER_BIND) --port=$(SERVER_PORT) --content-dir="$(CONTENT_DIR)"

run_client: import_client
	$(GODOT) --path client $(CLIENT_ARGS) -- --host=$(SERVER_HOST) --port=$(SERVER_PORT)

run_audience: import_client
	$(GODOT) --path client $(CLIENT_ARGS) -- --host=$(SERVER_HOST) --port=$(SERVER_PORT) --audience

import_client:
	$(GODOT) --headless --path client --editor --import

check_client: import_client
	$(GODOT) --headless --path client --script res://main.gd --check-only

check_connection: build_server check_client
	$(GODOT) --headless --path client --script $(abspath tests/connection_check.gd) -- --server=$(abspath build/server)

check_session: build/deps/libenet.a
	$(ODIN) test server -out:build/session_tests -extra-linker-flags:"-L$(abspath build/deps)"

check_selection: build_server check_client
	$(GODOT) --headless --path client --script $(abspath tests/selection_check.gd) -- --server=$(abspath build/server)

check_content: check_session check_client
	$(GODOT) --headless --path client --script $(abspath tests/content_check.gd)

check_arena_content: check_session check_client
	$(GODOT) --headless --path client --script $(abspath tests/arena_content_check.gd)

check_arena_selection: build_server check_client
	$(GODOT) --headless --path client --script $(abspath tests/arena_selection_check.gd) -- --server=$(abspath build/server)

check_movement: build_server check_client
	$(GODOT) --headless --path client --script $(abspath tests/movement_check.gd) -- --server=$(abspath build/server)

check: check_content check_arena_content check_connection check_selection check_arena_selection check_movement

ccx:
	codex --dangerously-bypass-approvals-and-sandbox

cc:
	claude --dangerously-skip-permissions
