class_name CharacterArtifact
extends RefCounted

const Exports = preload("res://characters/import/character_exports.gd")
const AnimationSet = preload("res://characters/character_animation_set.gd")
const Contract = preload("res://content/character_contract.gd")


static func write(candidate: Exports, sources, directory: String, input_digest: String) -> Dictionary:
	var art = candidate.art
	var document := {"schema_version": 1, "scope": "art_preview_only", "module_key": candidate.module_key,
		"contract_id": candidate.contract_id, "contract_version": candidate.contract_version,
		"export_api_version": candidate.export_api_version, "input_digest": input_digest,
		"gameplay_definition": candidate.gameplay_definition, "ai": candidate.ai,
		"source_inventory": sources.manifest, "bindings": art.bindings,
		"metrics": {"reference_span_px": art.reference_span_px,
			"body_rect_px": [art.body_rect_px.position.x, art.body_rect_px.position.y, art.body_rect_px.size.x, art.body_rect_px.size.y],
			"foot_anchor_px": [art.foot_anchor_px.x, art.foot_anchor_px.y]}, "clips": {}}
	var keys: Array = art.clips.keys()
	keys.sort()
	for clip_index in keys.size():
		var key: String = keys[clip_index]
		var clip: Dictionary = art.clips[key]
		var frames: Array[Dictionary] = []
		for index in clip.frames.size():
			var relative := "frames/%03d/%04d.png" % [clip_index, index]
			var path := directory.path_join(relative)
			var origin: Dictionary = sources.origins.get(key, {}).get(str(index), {})
			if origin.is_empty(): return {"error": sources.fail("serialize", relative, "Missing source lineage for %s frame %d" % [key, index])}
			sources.note("serialize", "started", {"output": relative, "origin": origin})
			if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
				return {"error": sources.fail("serialize", relative, "Cannot create processed frame directory")}
			var image: Image = clip.frames[index].get_image()
			if image == null or image.save_png(path) != OK:
				return {"error": sources.fail("serialize", relative, "Cannot write processed PNG")}
			frames.append({"path": relative, "sha256": FileAccess.get_sha256(path), "origin": origin})
			sources.note("serialize", "pass", {"output": relative, "origin": origin})
		document.clips[key] = {"fps": clip.fps, "loop": clip.loop, "frames": frames}
	var path := directory.path_join("artifact.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"error": sources.fail("serialize", path, "Cannot write artifact metadata")}
	file.store_string(JSON.stringify(document, "  ", true) + "\n")
	file.close()
	return {"error": "", "path": path, "digest": FileAccess.get_sha256(path)}


# Data-only loading: does not invoke an importer or read original inputs.
static func read(path: String, expected_digest := "") -> Dictionary:
	if not FileAccess.file_exists(path): return {"error": "Processed artifact missing: " + path}
	if not expected_digest.is_empty() and FileAccess.get_sha256(path) != expected_digest:
		return {"error": "Processed metadata SHA-256 mismatch: " + path}
	var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary or doc.get("schema_version") != 1 or doc.get("scope") != "art_preview_only":
		return {"error": "Unsupported processed artifact schema: " + path}
	for field in ["module_key", "contract_id", "contract_version", "export_api_version"]:
		if not doc.get(field) is String: return {"error": "Invalid artifact field: " + field}
	for field in ["metrics", "clips", "gameplay_definition", "ai"]:
		if not doc.get(field) is Dictionary: return {"error": "Invalid artifact field: " + field}
	if not doc.get("bindings") is Array or not doc.bindings.all(func(value): return value is Dictionary):
		return {"error": "Invalid processed bindings"}
	if not _numbers(doc.metrics.get("body_rect_px"), 4) or not _numbers(doc.metrics.get("foot_anchor_px"), 2) or not Contract.positive(doc.metrics.get("reference_span_px")):
		return {"error": "Invalid processed body metrics"}
	var candidate := Exports.new()
	candidate.module_key = doc.module_key
	candidate.contract_id = doc.contract_id
	candidate.contract_version = doc.contract_version
	candidate.export_api_version = doc.export_api_version
	candidate.gameplay_definition = doc.gameplay_definition
	candidate.ai = doc.ai
	var art := AnimationSet.new()
	var body: Array = doc.metrics.body_rect_px
	var foot: Array = doc.metrics.foot_anchor_px
	art.reference_span_px = doc.metrics.reference_span_px
	art.body_rect_px = Rect2(body[0], body[1], body[2], body[3])
	art.foot_anchor_px = Vector2(foot[0], foot[1])
	art.bindings.assign(doc.bindings)
	for key: String in doc.clips:
		var clip = doc.clips[key]
		if not clip is Dictionary or not clip.get("frames") is Array: return {"error": "Invalid processed clip: " + key}
		var frames: Array[Texture2D] = []
		for frame: Variant in clip.frames:
			if not frame is Dictionary or not frame.get("path") is String or not frame.get("sha256") is String or not frame.path.begins_with("frames/") or ".." in frame.path.split("/") or "\\" in frame.path:
				return {"error": "Invalid processed frame path/hash: " + key}
			var frame_path := path.get_base_dir().path_join(frame.path)
			if not FileAccess.file_exists(frame_path) or FileAccess.get_sha256(frame_path) != frame.sha256:
				return {"error": "Processed frame missing or SHA-256 mismatch: " + frame_path}
			var image := Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(frame_path)) != OK:
				return {"error": "Cannot decode processed PNG: " + frame_path}
			frames.append(ImageTexture.create_from_image(image))
		art.clips[key] = {"fps": clip.get("fps"), "loop": clip.get("loop"), "frames": frames}
	candidate.art = art
	var contract := Contract.new()
	var error := contract.load_for_id(candidate.contract_id)
	if not error.is_empty(): return {"error": error}
	return {"error": "", "candidate": candidate, "report": contract.inspect(candidate), "document": doc, "artifact_path": path}


static func read_current(key: String, family := "characters") -> Dictionary:
	if not key.is_valid_identifier(): return {"error": "Invalid processed module key"}
	if family not in ["characters", "players"]: return {"error": "Unknown asset family"}
	var directory := ProjectSettings.globalize_path("res://../build/processed/" + family).path_join(key)
	var pointer = _json(directory.path_join("current.json"))
	var latest = _json(directory.path_join("latest_attempt.json"))
	if not pointer is Dictionary or not pointer.get("generation") is String:
		return {"error": "No successful processed output for %s. Process this module, or select Latest processed candidate to inspect an incomplete attempt." % key, "latest_attempt": latest}
	var generation: String = pointer.generation
	if generation.length() != 64 or not generation.is_valid_hex_number(): return {"error": "Invalid generation pointer"}
	var result := read(directory.path_join("generations/" + generation + "/artifact.json"), generation)
	result["latest_attempt"] = latest
	result["generation"] = generation
	return result


# Explicit inspection of an incomplete attempt. Never changes current.json.
static func read_latest_candidate(key: String, family := "characters") -> Dictionary:
	if not key.is_valid_identifier(): return {"error": "Invalid processed module key"}
	if family not in ["characters", "players"]: return {"error": "Unknown asset family"}
	var directory := ProjectSettings.globalize_path("res://../build/processed/" + family).path_join(key)
	var latest = _json(directory.path_join("latest_attempt.json"))
	if not latest is Dictionary or not latest.get("staged_artifact") is String or not latest.get("candidate_digest") is String or latest.candidate_digest.length() != 64:
		return {"error": "The latest attempt has no complete processed candidate. Inspect the processing report.", "latest_attempt": latest}
	var result := read(latest.staged_artifact, latest.candidate_digest)
	result["latest_attempt"] = latest
	result["generation"] = latest.candidate_digest
	return result


static func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null


static func _numbers(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count and value.all(func(number): return (number is int or number is float) and is_finite(float(number)))
