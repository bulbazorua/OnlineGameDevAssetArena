.DEFAULT_GOAL := help

ODIN ?= odin
GODOT ?= godot
CLIENT_ARGS ?=
DEV ?= 0
PYTHON ?= python3
SERVER_BIND ?= 127.0.0.1
SERVER_HOST ?= 127.0.0.1
SERVER_PORT ?= 7000
CONTENT_DIR ?= client/content/data
P1 ?= circle
P2 ?= square
ARENA ?= meadow_crossing
AUDIENCE ?= 0
AUDIENCE_DELAY ?= 5
SEED ?= 1
ASSET_SOURCE ?= $(HOME)/CONTENT_CREATION/BulbaZorua/GameAssets/Tiny Swords (Free Pack)/Tiny Swords (Free Pack)
CHARACTER ?= reference16
PLAYER ?= player1
MODULE ?=
CANDIDATE ?= 0
COUNTDOWN ?= 0
WATCH ?= 1
HEADLESS ?= 0
DEV_RUN_SECONDS ?= 0

.PHONY: help build_server run_server run_client run_audience check_client check_session check_connection check_selection check_content check_arena_content check_arena_selection check_movement import_client check ccx cc
.PHONY: dev_arena check_dev check_ai check_character_ai
.PHONY: import_tiny_swords check_tiny_swords_assets check_tiny_swords
.PHONY: check_land check_camera check_audience_delay
.PHONY: character_harness process_character check_character_contract check_asset_pipeline
.PHONY: check_character_modules
.PHONY: prepare_characters check_playable_characters import_runtime_client
.PHONY: player_harness process_player check_player_harness prepare_players check_trainers

help:
	@echo "make check_character_ai - verify autonomous idle/walk and delayed audience state"
	@echo "SEED=42 sets a reproducible character AI seed for run_server or dev_arena"
	@echo "make check_trainers - verify arena trainers, host-timed summoning and audience views"
	@echo "make prepare_players - process and bundle Player1 for arena clients"
	@echo "make player_harness [PLAYER=player1] - isolated trainer art workbench, all eight states required"
	@echo "make process_player [PLAYER=player1] - process trainer originals with provenance and reports"
	@echo "make check_player_harness - verify player contract, processing, sizing and preview controls"
	@echo "make prepare_characters - process and bundle complete character art for the client"
	@echo "make character_harness [MODULE=res://dev/fixtures/characters/reference32] - isolated character art workbench"
	@echo "make character_harness CHARACTER=orc | CHARACTER=archer - processed real-character preview"
	@echo "  Opens an incomplete candidate if no successful build exists; CANDIDATE=1 forces candidate preview"
	@echo "make process_character [MODULE=res://...] - process originals, keep reports, publish validated art"
	@echo "make check_asset_pipeline - verify provenance, saved artifacts and failure recovery"
	@echo "make check_character_modules - process Archer/Orc and verify isolated imports, source pixels and preview"
	@echo "make check_character_contract - verify draft contract, diagnostics, sizing and module interfaces"
	@echo "make import_tiny_swords [ASSET_SOURCE=path] - install licensed Tiny Swords art locally"
	@echo "make dev_arena P1=triangle P2=diamond ARENA=sandbar [AUDIENCE=1 AUDIENCE_DELAY=5 COUNTDOWN=5 WATCH=0]"
	@echo "  Own local host + two clients; watch saves, refresh visuals or reopen the scenario"
	@echo "make check_dev - check the development scenario and reload workflow"
	@echo "make check_tiny_swords - verify local art, village buildings, collision, and scaling"
	@echo "make check_audience_delay - verify host-enforced spectator delay and reconnect isolation"
	@echo "make check_camera - check independent audience cameras and centered fighter views"
	@echo "make check_land - check high-ground traversal and camera controls"
	@echo "make run_server  - build and start the Odin host (AUDIENCE_DELAY=5 seconds; 0 disables)"
	@echo "make run_client  - start the Godot client"
	@echo "make run_audience - start a Godot client as audience"
	@echo "Add DEV=1 to run_client or run_audience for the FPS/ping overlay"
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

import_tiny_swords:
	$(PYTHON) tools/import_tiny_swords.py --source="$(ASSET_SOURCE)"

check_tiny_swords_assets:
	$(PYTHON) tools/import_tiny_swords.py --verify

build/deps/libenet.a: tools/build_enet.py
	$(PYTHON) tools/build_enet.py

build_server: build/deps/libenet.a
	$(ODIN) build server -out:build/server -debug -extra-linker-flags:"-L$(abspath build/deps)"

run_server: build_server
	./build/server --bind=$(SERVER_BIND) --port=$(SERVER_PORT) --content-dir="$(CONTENT_DIR)" --audience-delay="$(AUDIENCE_DELAY)" --seed="$(SEED)"

dev_arena:
	$(PYTHON) tools/dev_session.py --p1="$(P1)" --p2="$(P2)" --arena="$(ARENA)" --audience="$(AUDIENCE)" --audience-delay="$(AUDIENCE_DELAY)" --seed="$(SEED)" --countdown="$(COUNTDOWN)" --watch="$(WATCH)" --godot="$(GODOT)" --odin="$(ODIN)" --run-seconds="$(DEV_RUN_SECONDS)" $(if $(filter 1,$(HEADLESS)),--headless)

run_client: import_runtime_client
	$(GODOT) --path client $(CLIENT_ARGS) -- --host=$(SERVER_HOST) --port=$(SERVER_PORT) $(if $(filter 1,$(DEV)),--dev)

run_audience: import_runtime_client
	$(GODOT) --path client $(CLIENT_ARGS) -- --host=$(SERVER_HOST) --port=$(SERVER_PORT) --audience $(if $(filter 1,$(DEV)),--dev)

prepare_characters:
	$(PYTHON) tools/prepare_characters.py --godot="$(GODOT)"

import_client:
	$(GODOT) --headless --path client --editor --import

prepare_players:
	$(PYTHON) tools/prepare_characters.py --godot="$(GODOT)" --family=players

import_runtime_client: prepare_characters prepare_players
	$(GODOT) --headless --path client --editor --import

check_client: import_runtime_client
	$(GODOT) --headless --path client --script res://main.gd --check-only

check_connection: build_server check_client
	$(GODOT) --headless --path client --script $(abspath tests/connection_check.gd) -- --server=$(abspath build/server)

check_ai:
	@mkdir -p build
	$(ODIN) test server/ai -out:build/ai_tests

check_session: build/deps/libenet.a check_ai
	$(ODIN) test server -out:build/session_tests -extra-linker-flags:"-L$(abspath build/deps)"

check_dev: build_server check_session
	$(PYTHON) tests/dev_workflow_check.py --godot="$(GODOT)" --odin="$(ODIN)"

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

check_land: build_server check_client check_session
	$(GODOT) --headless --path client --script $(abspath tests/land_movement_check.gd) -- --server=$(abspath build/server)

check_camera: build_server check_client
	$(GODOT) --headless --path client --script $(abspath tests/camera_check.gd) -- --server=$(abspath build/server)

check_audience_delay: build_server check_client check_session
	$(GODOT) --headless --path client --script $(abspath tests/audience_delay_check.gd) -- --server=$(abspath build/server)

check_tiny_swords: build_server check_client check_tiny_swords_assets
	$(GODOT) --headless --path client --script $(abspath tests/tiny_swords_check.gd) -- --server=$(abspath build/server)

character_harness: import_client
	$(PYTHON) tools/process_character_assets.py --godot="$(GODOT)" $(if $(strip $(MODULE)),--module="$(MODULE)",--character="$(CHARACTER)") --open-harness $(if $(filter 1,$(CANDIDATE)),--candidate)

process_character:
	$(PYTHON) tools/process_character_assets.py --godot="$(GODOT)" $(if $(strip $(MODULE)),--module="$(MODULE)",--character="$(CHARACTER)")

player_harness: import_client
	$(PYTHON) tools/process_character_assets.py --godot="$(GODOT)" --family=players $(if $(strip $(MODULE)),--module="$(MODULE)",--player="$(PLAYER)") --open-harness $(if $(filter 1,$(CANDIDATE)),--candidate)

process_player:
	$(PYTHON) tools/process_character_assets.py --godot="$(GODOT)" --family=players $(if $(strip $(MODULE)),--module="$(MODULE)",--player="$(PLAYER)")

check_player_harness: import_client process_player
	$(PYTHON) tests/player_assets_check.py --godot="$(GODOT)"
	$(GODOT) --headless --path client --script $(abspath tests/player_harness_check.gd)

check_asset_pipeline:
	$(PYTHON) tests/character_asset_pipeline_check.py --godot="$(GODOT)"

check_character_modules: check_client
	$(PYTHON) tests/character_modules_check.py --godot="$(GODOT)" --prepare-workspace
	$(GODOT) --headless --path client --script $(abspath tests/character_module_views_check.gd)

check_playable_characters: build_server check_client
	$(PYTHON) tests/runtime_characters_check.py --godot="$(GODOT)"
	$(GODOT) --headless --path client --script $(abspath tests/playable_characters_check.gd) -- --server=$(abspath build/server)

check_character_contract: check_client
	$(PYTHON) tools/process_character_assets.py --godot="$(GODOT)" --module=res://dev/fixtures/characters/reference16
	$(PYTHON) tools/process_character_assets.py --godot="$(GODOT)" --module=res://dev/fixtures/characters/reference32
	$(GODOT) --headless --path client --script $(abspath tests/character_contract_check.gd)
	$(PYTHON) tests/character_module_isolation_check.py --godot="$(GODOT)"

check_trainers: build_server check_client
	$(GODOT) --headless --path client --script $(abspath tests/player_step_check.gd) -- --server=$(abspath build/server)

check_character_ai: build_server check_client check_session
	$(GODOT) --headless --path client --script $(abspath tests/character_ai_check.gd) -- --server=$(abspath build/server)

check: check_character_ai check_trainers check_player_harness check_character_contract check_asset_pipeline check_character_modules check_playable_characters check_tiny_swords check_content check_arena_content check_connection check_selection check_arena_selection check_movement check_land check_camera check_audience_delay check_dev

ccx:
	codex --dangerously-bypass-approvals-and-sandbox

cc:
	claude --dangerously-skip-permissions
