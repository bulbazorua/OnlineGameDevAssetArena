class_name SenseCatalog
extends RefCounted

# Shared gameplay sense profiles from senses.json (schema 2). Ranges are gameplay
# units converted once to world units; nothing here derives from art or tiles.
const WORLD_UNITS_PER_GAMEPLAY_UNIT := 32.0
const MAX_OLFACTION_RANGE_UNITS := 32
const SCENT_CLASSES := ["human", "orc"]

class VisionProfile:
	extends RefCounted
	var enabled := false
	var range := 0.0
	var focused_fov_degrees := 0.0
	var overall_fov_degrees := 0.0
	var sample_interval := 0

class OlfactionProfile:
	extends RefCounted
	var enabled := false
	var range := 0.0
	var sample_interval := 0
	var estimates_freshness := false

class ScentEmitter:
	extends RefCounted
	var enabled := false
	var scent_class := ""
	var intensity := 0.0

class SenseProfile:
	extends RefCounted
	var key := ""
	var vision: VisionProfile
	var olfaction: OlfactionProfile
	var emitter: ScentEmitter

var profiles: Array[SenseProfile] = []
var by_key: Dictionary = {}
var bindings: Dictionary = {}
var trainer_emitter: ScentEmitter


func clear() -> void:
	profiles.clear()
	by_key.clear()
	bindings.clear()
	trainer_emitter = null


static func vision_profile_valid(profile: VisionProfile) -> bool:
	for value in [profile.range, profile.focused_fov_degrees, profile.overall_fov_degrees]:
		if not is_finite(value): return false
	return profile.range > 0 and profile.range <= 64 * WORLD_UNITS_PER_GAMEPLAY_UNIT and profile.focused_fov_degrees >= 45 \
		and profile.focused_fov_degrees < profile.overall_fov_degrees and profile.overall_fov_degrees <= 180 \
		and profile.sample_interval >= 1 and profile.sample_interval <= 60


static func olfaction_profile_valid(profile: OlfactionProfile) -> bool:
	return is_finite(profile.range) and profile.range > 0 and profile.range <= MAX_OLFACTION_RANGE_UNITS * WORLD_UNITS_PER_GAMEPLAY_UNIT \
		and profile.sample_interval >= 1 and profile.sample_interval <= 60


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _float32(value: Variant) -> float:
	return PackedFloat32Array([float(value)])[0] # Match Odin f32 storage.


func _parse_vision(vision: Variant, key: String) -> String:
	if not vision is Dictionary or not vision.get("enabled") is bool or not _number(vision.get("range_units")) or not _number(vision.get("focused_fov_degrees")) or not _number(vision.get("overall_fov_degrees")) or not ArenaCatalog.integer_in(vision.get("sample_interval_ticks"), 1, 60):
		return "Vision profile %s needs enabled, finite range/field values and an integer 1–60 sample interval." % key
	if vision.range_units <= 0 or vision.range_units > 64: return "Vision range must be within 0–64 gameplay units."
	var profile := VisionProfile.new()
	profile.enabled = vision.enabled
	profile.range = _float32(float(vision.range_units) * WORLD_UNITS_PER_GAMEPLAY_UNIT)
	profile.focused_fov_degrees = _float32(vision.focused_fov_degrees)
	profile.overall_fov_degrees = _float32(vision.overall_fov_degrees)
	profile.sample_interval = int(vision.sample_interval_ticks)
	if not vision_profile_valid(profile): return "Vision profile %s is outside the supported bounds." % key
	by_key[key].vision = profile
	return ""


# A nose: reach, schedule and whether it can tell how old a trace is.
func _parse_receptor(receptor: Variant, key: String) -> String:
	if not receptor is Dictionary or not receptor.get("enabled") is bool or not _number(receptor.get("range_units")) or not ArenaCatalog.integer_in(receptor.get("sample_interval_ticks"), 1, 60) or not receptor.get("estimates_freshness") is bool:
		return "Olfaction receptor %s needs enabled, a finite range, an integer 1–60 sample interval and estimates_freshness." % key
	if receptor.range_units <= 0 or receptor.range_units > MAX_OLFACTION_RANGE_UNITS: return "Olfactory range must be within 0–32 gameplay units."
	var profile := OlfactionProfile.new()
	profile.enabled = receptor.enabled
	profile.range = _float32(float(receptor.range_units) * WORLD_UNITS_PER_GAMEPLAY_UNIT)
	profile.sample_interval = int(receptor.sample_interval_ticks)
	profile.estimates_freshness = receptor.estimates_freshness
	if not olfaction_profile_valid(profile): return "Olfaction receptor %s is outside the supported bounds." % key
	by_key[key].olfaction = profile
	return ""


# A body's smell. A disabled emitter still names a valid class and intensity.
static func parse_emitter(emitter: Variant) -> ScentEmitter:
	if not emitter is Dictionary or not emitter.get("enabled") is bool or emitter.get("scent_class") not in SCENT_CLASSES or not _number(emitter.get("intensity")):
		return null
	if emitter.intensity <= 0 or emitter.intensity > 4: return null
	var result := ScentEmitter.new()
	result.enabled = emitter.enabled
	result.scent_class = emitter.scent_class
	result.intensity = _float32(emitter.intensity)
	return result


# Both readers reject the same catalogs: unique valid profiles, finite bounded
# tuning even when disabled, one trainer emitter, and exactly one binding per
# selectable character.
func parse(root: Variant, character_keys: Array) -> String:
	clear()
	if not root is Dictionary or not ArenaCatalog.integer_in(root.get("schema_version"), 2, 2) or not root.get("profiles") is Array or root.profiles.is_empty() or root.profiles.size() > 256:
		return "Sense catalog requires schema_version 2 and 1–256 profiles."
	for entry: Variant in root.profiles:
		if not entry is Dictionary or not entry.get("key") is String or not entry.get("vision") is Dictionary or not entry.get("olfaction") is Dictionary:
			return "Each sense profile needs a key, a vision object and an olfaction object."
		var key: String = entry.key
		if key.is_empty() or by_key.has(key): return "Sense profile keys must be unique and non-empty."
		for character in key:
			if not (character >= "a" and character <= "z" or character >= "0" and character <= "9" or character == "_"):
				return "Sense profile keys can only contain lowercase letters, digits, and underscores."
		var sense := SenseProfile.new()
		sense.key = key
		by_key[key] = sense
		var error := _parse_vision(entry.vision, key)
		if error.is_empty(): error = _parse_receptor(entry.olfaction.get("receptor"), key)
		if error.is_empty():
			sense.emitter = parse_emitter(entry.olfaction.get("emitter"))
			if sense.emitter == null: error = "Scent emitter %s needs enabled, a known scent_class and an intensity within 0–4." % key
		if not error.is_empty(): return error
		profiles.append(sense)
	trainer_emitter = parse_emitter(root.get("trainer_emitter"))
	if trainer_emitter == null: return "Sense catalog needs one valid trainer_emitter."
	if not root.get("bindings") is Array or root.bindings.size() != character_keys.size():
		return "Sense catalog needs exactly one binding per selectable character."
	for entry: Variant in root.bindings:
		if not entry is Dictionary or not entry.get("character") is String or not entry.get("profile") is String:
			return "Each sense binding names a character and a profile."
		if not by_key.has(entry.profile): return "Sense binding refers to unknown profile %s." % entry.profile
		if entry.character not in character_keys: return "Sense binding refers to unknown character %s." % entry.character
		if bindings.has(entry.character): return "Character %s has more than one sense binding." % entry.character
		bindings[entry.character] = entry.profile
	for key in character_keys:
		if not bindings.has(key): return "Character %s has no sense binding." % key
	return ""


func profile_for(character_key: String) -> SenseProfile:
	return by_key.get(bindings.get(character_key, ""))


func vision_for(character_key: String) -> VisionProfile:
	var profile := profile_for(character_key)
	return null if profile == null else profile.vision


func olfaction_for(character_key: String) -> OlfactionProfile:
	var profile := profile_for(character_key)
	return null if profile == null else profile.olfaction


func emitter_for(character_key: String) -> ScentEmitter:
	var profile := profile_for(character_key)
	return null if profile == null else profile.emitter
