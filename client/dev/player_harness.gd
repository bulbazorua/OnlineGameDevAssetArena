class_name PlayerHarness
extends "res://dev/character_harness.gd"


func _init() -> void:
	contract_path = Contract.PLAYER_PATH
	registry_path = "res://players/packages/registry.json"
	artifact_family = "players"
	module_path = "res://players/packages/player1"
	harness_title = "Player harness · trainer art"
	harness_description = "All eight states are required. Player1 uses one authored view with explicit mirroring; directional sheets can be added per player."
	unverified_label = "PLAYER GAMEPLAY NOT VERIFIED"
	missing_roles = ["advise"]
