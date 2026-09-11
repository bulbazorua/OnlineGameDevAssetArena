extends RefCounted

const Contract = preload("res://dev/search/search_contract.gd")
const SHORT_DIRECTIONS := ["N ", "NE", "E ", "SE", "S ", "SW", "W ", "NW"]


static func age(tick: int, earlier: int) -> float:
	return float((tick - earlier) & 0xffffffff) / 60.0


# What the searcher is doing with its nose: the class and coarse bearing it acts on,
# never a source position. Older records without scent say so.
static func scent_line(search: Dictionary) -> String:
	if not search.has("scent"): return "Scent: not recorded in this schema"
	var scent: Dictionary = search.scent
	if not scent.valid: return "Scent: no usable reading (%d episodes so far)" % int(search.get("scent_episodes", 0))
	var bearing := "≈ %s" % scent.bearing if scent.bearing_valid else "no usable direction"
	var discount := " · %d own-trail zones discounted" % int(scent.discounted_zones) if int(scent.discounted_zones) > 0 else ""
	return "Scent: %s %s · %s · %s · reading #%d%s" % [scent.class, str(scent.strength).to_lower(), str(scent.freshness).replace("_", " ").to_lower(), bearing, int(scent.observation_id), discount]


static func text(search: Dictionary, tick: int, intent: Dictionary, result: Dictionary) -> String:
	if not Contract.valid(search): return "No search state in this record."
	var p: Dictionary = search.profile
	var lines := PackedStringArray([
		"[b]%s[/b] · %s" % [search.state.replace("_", " ").to_upper(), search.transition.replace("_", " ")],
		"Own tick %d · state age %.1fs · %s" % [tick, age(tick, int(search.state_tick)), "LONG RELOCATION" if search.relocating else "local movement"],
		"Evidence: %s · belief confidence %.2f · %.2fs old" % [search.evidence, search.confidence, age(tick, int(search.evidence_tick))],
		"Target: %s" % ("subject %d at %s (%s)" % [int(search.target), str(search.target_position), "seen" if search.target_visible else "last seen"] if int(search.target) > 0 else "unknown"),
		"Search center: %s · radius %.0f" % [str(search.center) + " (hypothesis)" if search.center_valid else "none", search.radius],
		"Cue bearing: %s · origin %s%s" % [search.cue_direction if search.cue_valid else "none", str(search.cue_origin) if search.cue_valid else "unknown", " (from the nose)" if search.get("cue_from_scent", false) else ""],
		scent_line(search),
		"Repeated weak cues: %s" % ("temporarily ignored after failed investigation" if search.cue_cooldown else "eligible"),
		"Heading: %s · leg remaining %.2fs" % [search.heading, maxf(0, float((int(search.leg_deadline) - tick + 2147483648) & 0xffffffff) - 2147483648) / 60.0],
		"Request: %s %s · confirmed: %s %s" % [intent.kind, str(intent.direction), result.kind, str(result.displacement)],
		"Relocations %d · abandoned %d · blocked %d · acquisitions %d" % [int(search.relocation_count), int(search.abandoned_count), int(search.blocked_count), int(search.acquisition_count)],
		"[b]Direction scores at tick %d[/b] (kept until reconsidered)" % int(search.scored_tick),
		"[code]   total  persist random evidence local recent block",
	])
	for index in 8:
		var c: Dictionary = search.choices[index]
		var row := "%s %6.2f %6.2f %6.2f %7.2f %5.2f %6.2f %5.2f" % [SHORT_DIRECTIONS[index], c.total, c.persistence, c.exploration, c.evidence, c.locality, -c.recent_penalty, -c.blocked_penalty]
		lines.append("[color=#6ff5aa]" + row + " ← chosen[/color]" if Contract.FACINGS[index] == search.heading else row)
	lines.append("[/code][b]Private visits %d / %d[/b] · %.0fs retention · %.0f-unit regions" % [int(search.visit_count), int(p.memory_capacity), p.history_ticks / 60.0, p.region_size])
	for index in int(search.visit_count):
		var visit: Dictionary = search.visits[index]
		var seconds := age(tick, int(visit.visited_tick))
		lines.append("%s · %.1fs old · strength %.2f · %s" % [str(visit.position), seconds, maxf(0, 1 - seconds * 60 / p.history_ticks), "opponent seen here" if visit.opponent_seen else "visited; no opponent seen"])
	lines.append("Legs %.1fs / local %.1fs / relocation %.1fs · evidence %.1fs" % [p.extensive_leg_ticks / 60.0, p.intensive_leg_ticks / 60.0, p.relocation_ticks / 60.0, p.evidence_ticks / 60.0])
	lines.append("Random stream: %d · learned preferences: not implemented" % int(search.random_state))
	lines.append("Visit marks are private history. Blank space is unknown. No planned route.")
	return "\n".join(lines)
