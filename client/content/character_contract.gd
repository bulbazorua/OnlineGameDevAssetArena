class_name CharacterContract
extends RefCounted

const CharacterExports = preload("res://characters/import/character_exports.gd")
const AssetScale = preload("res://presentation/asset_scale.gd")
const PATH := "res://content/contracts/character_basic_combat/1.0.0-draft.1.json"
var data: Dictionary = {}
var digest := ""


func load_contract() -> String:
	data.clear()
	digest = ""
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null: return "Cannot read character contract: " + PATH
	var bytes := file.get_buffer(file.get_length())
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("roles") is Dictionary or not parsed.get("facings") is Array or not parsed.get("admission_checks") is Array:
		return "Invalid character contract schema."
	if parsed.get("world_units_per_gameplay_unit") != AssetScale.WORLD_UNITS_PER_GAMEPLAY_UNIT:
		return "Character contract and world scale disagree."
	data = parsed
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	digest = hash.finish().hex_encode()
	return ""


func inspect(candidate: CharacterExports) -> Dictionary:
	var checks: Array[Dictionary] = []
	var structure := ""
	if data.is_empty(): structure = "Contract has not loaded."
	elif candidate == null: structure = "Module did not produce CharacterExports."
	elif candidate.module_key.is_empty(): structure = "Export needs a module key."
	elif candidate.contract_id != data.id or candidate.contract_version != data.version or candidate.export_api_version != data.export_api_version:
		structure = "Unsupported contract/export version; expected %s@%s, export %s." % [data.id, data.version, data.export_api_version]
	elif candidate.ai != {"mode": "player_only"}:
		structure = "Checkpoint 4A requires an explicit player_only AI export."
	elif candidate.art == null: structure = "Missing normalized art export."
	_add(checks, "exports", structure)
	var renderable_roles: Array[String] = []
	if structure.is_empty():
		var metrics_error := _metrics_error(candidate)
		_add(checks, "metrics", metrics_error)
		var clips_error := _clips_error(candidate)
		_add(checks, "clips", clips_error)
		var bindings_error := _bindings_error(candidate)
		_add(checks, "bindings", bindings_error)
		for role: String in data.roles:
			var error := _role_error(candidate, role)
			_add(checks, "role." + role, error)
			if metrics_error.is_empty() and clips_error.is_empty() and bindings_error.is_empty() and error.is_empty():
				renderable_roles.append(role)
	var art_pass := checks.all(func(check: Dictionary): return check.status == "pass")
	for id: String in data.get("admission_checks", []):
		checks.append({"id": id, "status": "not_run", "message": "Not verified by the art workbench."})
	return {"contract": data.get("id", ""), "version": data.get("version", ""), "contract_digest": digest,
		"module": "" if candidate == null else candidate.module_key,
		"checks": checks, "art_pass": art_pass, "renderable_roles": renderable_roles,
		"selection_eligible": false, "scope": "art_preview_only"}


func _metrics_error(candidate: CharacterExports) -> String:
	var art = candidate.art
	if not positive(art.reference_span_px) or art.reference_span_px > 4096:
		return "Body reference must be finite and within (0, 4096] pixels."
	if not art.body_rect_px.position.is_finite() or not art.body_rect_px.size.is_finite() or art.body_rect_px.position.x < 0 or art.body_rect_px.position.y < 0 or art.body_rect_px.size.x <= 0 or art.body_rect_px.size.y <= 0:
		return "Invalid authored body rectangle."
	if not is_equal_approx(maxf(art.body_rect_px.size.x, art.body_rect_px.size.y), art.reference_span_px):
		return "Reference span must match the longest side of the authored body."
	if not art.foot_anchor_px.is_finite(): return "Feet anchor must be finite."
	var size = candidate.gameplay_definition.get("gameplay_size")
	var radius = candidate.gameplay_definition.get("footprint_radius_units")
	if not positive(size) or size > 8 or not positive(radius) or radius > 8:
		return "Preview size and footprint must be finite and within (0, 8] gameplay units."
	return ""


func _clips_error(candidate: CharacterExports) -> String:
	var art = candidate.art
	for key: Variant in art.clips:
		var clip: Variant = art.clips[key]
		if not key is String or not clip is Dictionary or not clip.get("frames") is Array or clip.frames.is_empty() or clip.frames.size() > 1024 or not positive(clip.get("fps")) or clip.fps > 240 or not clip.get("loop") is bool:
			return "Clip %s needs 1–1024 textures, positive FPS <= 240 and a loop flag." % str(key)
		for texture: Variant in clip.frames:
			if not texture is Texture2D or texture.get_width() <= 0 or texture.get_height() <= 0:
				return "Clip %s contains an invalid frame texture." % key
			var canvas := Rect2(Vector2.ZERO, texture.get_size())
			if not canvas.encloses(art.body_rect_px) or art.foot_anchor_px.x < 0 or art.foot_anchor_px.y < 0 or art.foot_anchor_px.x > canvas.end.x or art.foot_anchor_px.y > canvas.end.y:
				return "Clip %s body/feet lie outside a source frame." % key
	return ""


func _bindings_error(candidate: CharacterExports) -> String:
	var seen: Dictionary = {}
	for binding: Dictionary in candidate.art.bindings:
		if not binding.get("role") is String or not data.roles.has(binding.role) or not binding.get("facing") in data.facings:
			return "Binding has an unknown role or facing."
		if binding.get("variant") != data.roles[binding.role].variant:
			return "Binding has an unsupported variant."
		var key: String = "%s/%s/%s" % [binding.role, binding.facing, binding.variant]
		if seen.has(key): return "Duplicate binding: " + key
		seen[key] = true
		if not binding.get("flip_h", false) is bool: return "Mirroring must be explicit true/false."
	return ""


func _role_error(candidate: CharacterExports, role: String) -> String:
	var rule: Dictionary = data.roles[role]
	for facing: String in data.facings:
		var binding := candidate.art.binding_for(role, facing, rule.variant)
		if binding.is_empty(): return "Missing %s/%s/%s binding." % [role, facing, rule.variant]
		if binding.get("kind") not in rule.binding_kinds: return "Unsupported binding kind for " + role
		# Shared effects are specified by the contract, but their implementation
		# must land before they can pass; no silent fallback to a healthy pose.
		if binding.kind != "clip": return "Shared effect %s is not implemented in checkpoint 4A." % binding.kind
		var clip: Variant = candidate.art.clips.get(binding.get("clip"))
		if not clip is Dictionary or not clip.get("frames") is Array or clip.frames.size() < rule.minimum_frames:
			return "Missing or insufficient frames for " + role
		if clip.get("loop") != rule.loop: return "Wrong loop policy for " + role
	return ""


static func positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0


static func _add(checks: Array[Dictionary], id: String, error: String) -> void:
	checks.append({"id": id, "status": "pass" if error.is_empty() else "fail", "message": "Valid" if error.is_empty() else error})
