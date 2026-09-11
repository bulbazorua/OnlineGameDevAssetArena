extends RefCounted

const STATES := ["Extensive_Search", "Intensive_Search", "Investigate", "Last_Known_Position", "Pursue"]
const REASONS := ["Search_Extensive", "Search_Intensive", "Investigate", "Last_Known_Position", "Pursue"]
const TRANSITIONS := ["No_Evidence", "Focused_Opponent", "Directional_Cue", "Target_Lost", "Reached_Last_Position", "Evidence_Expired", "Cue_Expired", "Investigation_Abandoned", "Scent_Trail", "Scent_Presence", "Scent_Faded"]
const FACINGS := ["North", "North_East", "East", "South_East", "South", "South_West", "West", "North_West"]
const EVIDENCE := ["None", "Focused", "Cue", "Focused_Memory", "Cue_Memory", "Scent", "Scent_Memory"]
const SCENT_CLASSES := ["Human", "Orc"]
const SCENT_STRENGTHS := ["None", "Weak", "Medium", "Strong"]
const SCENT_FRESHNESS := ["Unknown", "Old", "Recent", "Very_Recent"]
# Trace schema 3 recorded search without smell; schema 4 adds the scent evidence fields.
const LATEST_SCHEMA := 4


static func number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func integer(value: Variant, minimum := 0, maximum := 4294967295) -> bool:
	return number(value) and value == floor(value) and value >= minimum and value <= maximum


static func vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(number)


static func valid_scent_evidence(value: Variant) -> bool:
	if not value is Dictionary or not value.get("valid") is bool or not value.get("bearing_valid") is bool: return false
	if value.get("class") not in SCENT_CLASSES or value.get("strength") not in SCENT_STRENGTHS or value.get("freshness") not in SCENT_FRESHNESS or value.get("bearing") not in FACINGS: return false
	return integer(value.get("observation_id")) and integer(value.get("observed_tick")) and integer(value.get("discounted_zones"), 0, 16)


static func valid(value: Variant, schema := LATEST_SCHEMA) -> bool:
	if not value is Dictionary or value.get("state") not in STATES or value.get("transition") not in TRANSITIONS: return false
	if schema >= 4:
		if not valid_scent_evidence(value.get("scent")) or not integer(value.get("scent_episodes")) or not value.get("cue_from_scent") is bool: return false
		if value.scent.valid and value.scent.strength == "None": return false
	elif value.has("scent") or value.has("scent_episodes") or value.has("cue_from_scent"):
		return false
	if value.get("evidence") not in EVIDENCE or value.get("heading") not in FACINGS or value.get("cue_direction") not in FACINGS: return false
	for key in ["started", "leg_active", "relocating", "center_valid", "cue_valid", "target_visible", "weak_episode_active", "cue_cooldown"]:
		if not value.get(key) is bool: return false
	for key in ["random_state", "leg_deadline", "scored_tick", "state_tick", "blocked_count", "relocation_count", "abandoned_count", "evidence_tick", "observation_id", "cue_tick", "target", "target_tick", "acquired_tick", "acquisition_count", "weak_episode_tick", "ignore_cues_until"]:
		if not integer(value.get(key)): return false
	for key in ["scored_position", "position", "blocked_origin", "center", "cue_origin", "target_position"]:
		if not vector(value.get(key)): return false
	if not number(value.get("confidence")) or value.confidence < 0 or value.confidence > 1 or not number(value.get("radius")) or value.radius < 0: return false
	if not valid_profile(value.get("profile")): return false
	if not integer(value.get("visit_count"), 0, int(value.profile.memory_capacity)): return false
	if not value.get("visits") is Array or value.visits.size() != 16: return false
	for visit in value.visits:
		if not visit is Dictionary or not vector(visit.get("position")) or not integer(visit.get("visited_tick")) or not visit.get("opponent_seen") is bool: return false
	if not value.get("choices") is Array or value.choices.size() != 8: return false
	for choice in value.choices:
		if not choice is Dictionary: return false
		for key in ["persistence", "exploration", "evidence", "locality", "recent_penalty", "blocked_penalty", "total"]:
			if not number(choice.get(key)): return false
	if not value.get("blocked_until") is Array or value.blocked_until.size() != 8 or not value.blocked_until.all(integer): return false
	if not value.get("blocked") is Array or value.blocked.size() != 8 or not value.blocked.all(func(item): return item is bool): return false
	if value.target_visible and (value.target == 0 or value.evidence != "Focused" or value.state != "Pursue"): return false
	if value.evidence in ["Cue", "Cue_Memory"] and value.target != 0: return false
	return true


static func valid_profile(value: Variant) -> bool:
	if not value is Dictionary or not integer(value.get("memory_capacity"), 1, 16): return false
	for key in ["history_ticks", "evidence_ticks", "blocked_ticks", "extensive_leg_ticks", "intensive_leg_ticks", "relocation_ticks"]:
		if not integer(value.get(key), 1, 36000): return false
	for key in ["region_size", "arrival_radius", "pursuit_distance", "local_radius", "maximum_local_radius", "persistence", "exploration", "cue_weight", "history_weight"]:
		if not number(value.get(key)) or value[key] <= 0 or value[key] > 4096: return false
	if value.has("self_trail_ticks") or value.has("scent_weight"):
		if not integer(value.get("self_trail_ticks"), 1, 36000) or not number(value.get("scent_weight")) or value.scent_weight <= 0 or value.scent_weight > 4096: return false
	return value.maximum_local_radius >= value.local_radius and value.relocation_ticks > value.extensive_leg_ticks
