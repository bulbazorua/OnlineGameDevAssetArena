extends RefCounted

# Current-only rows from one delivered nose sample. Nothing is carried over from
# an earlier sample, and a row never gains a position or an identity.
const FACING_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const CLASS_COLORS := {"Human": Color("ffb454"), "Orc": Color("7de2b2")}
const STRENGTH_WORDS := {"None": "none", "Weak": "weak", "Medium": "medium", "Strong": "strong"}
const FRESHNESS_WORDS := {"Unknown": "age unknown", "Old": "old trace", "Recent": "recent trace", "Very_Recent": "very recent trace"}
const COVERAGE_WORDS := {"Unsampled": "not measured", "Partial": "partly measured", "Sampled": "measured"}


# How much of its reach the nose really measured, zone by zone. A sample without
# coverage (older recordings) is honest about not knowing rather than claiming ground.
static func coverage_counts(sample: Dictionary) -> Dictionary:
	var counts := {"recorded": false, "sampled": 0, "partial": 0, "unsampled": 0}
	if sample.is_empty() or sample.get("status") != "Sampled" or not sample.get("coverage") is Array or sample.coverage.size() != 16: return counts
	counts.recorded = true
	for zone in sample.coverage:
		match str(zone):
			"Sampled": counts.sampled += 1
			"Partial": counts.partial += 1
			_: counts.unsampled += 1
	return counts


static func coverage_summary(sample: Dictionary) -> String:
	var counts := coverage_counts(sample)
	if not counts.recorded: return "Coverage not recorded: how much of the reach was measured is unknown."
	if counts.sampled + counts.partial == 0: return "No ground was measured: the whole reach is unknown, not empty."
	return "Measured %d of 16 zones fully, %d partly; %d unknown." % [counts.sampled, counts.partial, counts.unsampled]


# Short note for the decision debugger and replay lines beside the nose sample.
static func coverage_note(sample: Dictionary) -> String:
	if sample.is_empty() or sample.get("status") != "Sampled": return ""
	var counts := coverage_counts(sample)
	if not counts.recorded: return ", coverage not recorded"
	return ", %d measured / %d partly / %d unknown zones" % [counts.sampled, counts.partial, counts.unsampled]


static func current(sample: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if sample.is_empty() or sample.status != "Sampled": return rows
	for index in int(sample.reading_count):
		var reading: Dictionary = sample.readings[index]
		var sampled_zones := 0
		for zone in reading.zones:
			if zone != "None": sampled_zones += 1
		rows.append({"number": rows.size() + 1, "observation_id": reading.observation_id, "class": reading.class,
			"strength": reading.strength, "freshness": reading.freshness, "bearing_valid": reading.bearing_valid,
			"direction": FACING_NAMES[FACING_NAMES.size() - 1 if reading.bearing == "North_West" else _facing_index(reading.bearing)],
			"zones": reading.zones, "zones_with_scent": sampled_zones})
	return rows


static func _facing_index(value: String) -> int:
	return ["North", "North_East", "East", "South_East", "South", "South_West", "West", "North_West"].find(value)


static func color_of(scent_class: String) -> Color:
	return CLASS_COLORS.get(scent_class, Color("c8c8c8"))


static func summary(row: Dictionary) -> String:
	var bearing := "≈ %s" % row.direction if row.bearing_valid else "no usable direction"
	return "%s scent · %s · %s" % [row.class, STRENGTH_WORDS[row.strength], bearing]


static func details(row: Dictionary) -> String:
	var bearing := "approximately %s" % row.direction if row.bearing_valid else "present with no usable direction"
	return "%s scent · reading #%d\nStrength %s · %s · bearing %s\n%d of 16 sampled zones hold this scent. Which body left it, how many, and where exactly are unknown." % [row.class, int(row.observation_id), STRENGTH_WORDS[row.strength], FRESHNESS_WORDS[row.freshness], bearing, int(row.zones_with_scent)]
