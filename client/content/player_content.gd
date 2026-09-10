class_name PlayerContent
extends RefCounted

const Artifact = preload("res://characters/character_artifact.gd")
const Protocol = preload("res://network/protocol.gd")
var art


func load_catalog() -> String:
	art = null
	var path := "res://generated/players/catalog.json"
	if not FileAccess.file_exists(path): return "Missing player art bundle. Run make prepare_players."
	var bundle = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not bundle is Dictionary or bundle.get("schema_version") != 1 or not bundle.get("modules") is Dictionary:
		return "Invalid player art bundle."
	var entry = bundle.modules.get("player1")
	if not entry is Dictionary or not entry.get("artifact") is String or not entry.get("digest") is String or entry.digest.length() != 64 or not entry.artifact.begins_with("res://generated/players/player1/") or ".." in entry.artifact.split("/"):
		return "Invalid Player1 runtime artifact."
	var result := Artifact.read(entry.artifact, entry.digest)
	if not result.error.is_empty(): return result.error
	var candidate = result.candidate
	if not result.report.art_pass or candidate.contract_id != "player.trainer" or candidate.module_key != "player1" or candidate.gameplay_definition.get("identity", {}).get("key") != "player1":
		return "Player1 does not satisfy the trainer contract."
	var definition: Dictionary = candidate.gameplay_definition
	if not is_equal_approx(definition.footprint_radius_units * definition.gameplay_size * 32.0, Protocol.TRAINER_RADIUS):
		return "Player1 footprint differs from the host's trainer radius."
	art = candidate
	return ""


func configure_view(view, definition_id: int, owner: int) -> void:
	assert(definition_id == Protocol.TRAINER_DEFINITION_ID and art != null)
	view.configure_art(art.art, owner, art.gameplay_definition.gameplay_size, art.gameplay_definition.footprint_radius_units)
	view.start_animation()
	view.animator.facing = "east" if owner == 1 else "west"
	view.observe_motion(Vector2.ZERO)
