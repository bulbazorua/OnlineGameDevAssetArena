extends RefCounted


static func matches(record: Dictionary, owner: int, world: Dictionary) -> bool:
	if owner not in [1, 2] or not world.get("active", false) or world.get("entities", []).size() != 2: return false
	return record.get("owner_id") == owner and record.get("entity_id") == world.entities[owner - 1] and record.get("round_id") == world.get("round_id") and record.get("map_id") == world.get("map_id")


static func for_owner(records: Array[Dictionary], owner: int, world: Dictionary) -> Dictionary:
	for record in records:
		if matches(record, owner, world): return project(record)
	return {}


static func project(record: Dictionary) -> Dictionary:
	var search: Dictionary = record.search
	var profile: Dictionary = search.profile
	var visits: Array[Dictionary] = []
	for index in int(search.visit_count):
		var visit: Dictionary = search.visits[index]
		var age := (int(record.tick) - int(visit.visited_tick)) & 0xffffffff
		if age >= int(profile.history_ticks): continue
		var cell := Vector2i(floori(visit.position[0] / profile.region_size), floori(visit.position[1] / profile.region_size))
		visits.append({"number": index + 1, "key": "%d,%d" % [cell.x, cell.y], "region": [cell.x, cell.y],
			"position": visit.position.duplicate(), "visited_tick": int(visit.visited_tick), "age_ticks": age,
			"strength": 1.0 - float(age) / profile.history_ticks, "opponent_seen": visit.opponent_seen})
	return {"owner_id": int(record.owner_id), "entity_id": int(record.entity_id), "round_id": int(record.round_id),
		"map_id": int(record.map_id), "tick": int(record.tick), "position": search.position.duplicate(),
		"capacity": int(profile.memory_capacity), "retention_ticks": int(profile.history_ticks),
		"region_size": float(profile.region_size), "visits": visits}


static func coordinates(point: Array) -> String:
	return "(%.1f, %.1f)" % [float(point[0]), float(point[1])]
