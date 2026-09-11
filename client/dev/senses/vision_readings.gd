extends RefCounted

const Reader = preload("res://dev/ai/trace_reader.gd")
const FACING_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


static func current(sample: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if sample.is_empty() or sample.status != "Sampled": return rows
	var origin := Vector2(sample.pose.position[0], sample.pose.position[1])
	for index in int(sample.focused_count):
		var sighting: Dictionary = sample.focused[index]
		var point := Vector2(sighting.position[0], sighting.position[1])
		rows.append({"number": rows.size() + 1, "quality": "Focused", "observation_id": sighting.observation_id,
			"subject": sighting.subject, "kind": sighting.kind, "appearance_id": sighting.appearance_id,
			"position": sighting.position, "distance": origin.distance_to(point), "facing": sighting.facing,
			"locomotion": sighting.locomotion})
	for index in int(sample.cue_count):
		var cue: Dictionary = sample.cues[index]
		var bearing := (Reader.facing_index(sample.pose.facing) + int(cue.sector)) % 8
		rows.append({"number": rows.size() + 1, "quality": "Peripheral", "observation_id": cue.observation_id,
			"sector": cue.sector, "band": cue.band, "direction": FACING_NAMES[bearing]})
	return rows


static func coordinates(point: Array) -> String:
	return "(%.1f, %.1f)" % [float(point[0]), float(point[1])]


static func direction(facing: String) -> String:
	return FACING_NAMES[Reader.facing_index(facing)]
