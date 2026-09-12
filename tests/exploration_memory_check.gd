extends SceneTree

const Memory = preload("res://dev/senses/exploration_memory.gd")
const MemoryPanel = preload("res://dev/senses/exploration_memory_panel.gd")


func _initialize() -> void:
	_run.call_deferred()


func _record(owner: int, entity: int) -> Dictionary:
	return {"owner_id": owner, "entity_id": entity, "round_id": 5, "map_id": 1, "tick": 3600,
		"search": {"position": [160, 96], "target": 999, "target_position": [9999, 9999], "visit_count": 3,
			"profile": {"region_size": 64, "memory_capacity": 16, "history_ticks": 3600}, "visits": [
				{"position": [64, 96], "visited_tick": 3600, "opponent_seen": false},
				{"position": [150, 110], "visited_tick": 1800, "opponent_seen": true},
				{"position": [320, 80], "visited_tick": 0, "opponent_seen": false},
				{"position": [9999, 9999], "visited_tick": 3600, "opponent_seen": true}]}}


func _run() -> void:
	create_timer(10).timeout.connect(func(): push_error("Exploration memory check did not finish."); quit(1))
	var world := {"active": true, "round_id": 5, "map_id": 1, "entities": [3, 4]}
	var records: Array[Dictionary] = [_record(1, 3), _record(2, 4)]
	records[1].search.visits[0].position = [640, 320]
	var own := Memory.for_owner(records, 1, world)
	assert(own.owner_id == 1 and own.entity_id == 3 and own.visits.size() == 2)
	assert(own.visits[0].region == [1, 1] and own.visits[0].age_ticks == 0 and own.visits[0].strength == 1)
	assert(own.visits[1].age_ticks == 1800 and own.visits[1].strength == 0.5 and own.visits[1].opponent_seen)
	assert(not own.has("target") and not own.has("target_position") and own.visits.all(func(visit): return visit.position[0] < 200))
	own.visits[0].position[0] = -100
	assert(records[0].search.visits[0].position[0] == 64, "Display changed source memory")
	var replacement := world.duplicate(true)
	replacement.entities[0] = 13
	assert(Memory.for_owner(records, 1, replacement).is_empty() and not Memory.for_owner(records, 2, replacement).is_empty())
	replacement = world.duplicate(true)
	replacement.round_id += 1
	assert(Memory.for_owner(records, 1, replacement).is_empty())
	replacement.active = false
	assert(Memory.for_owner(records, 2, replacement).is_empty())
	var wrapped := _record(1, 3)
	wrapped.tick = 6
	wrapped.search.visit_count = 1
	wrapped.search.visits[0].visited_tick = 4294967290
	assert(Memory.project(wrapped).visits[0].age_ticks == 12)
	wrapped.search.profile.history_ticks = 12
	assert(Memory.project(wrapped).visits.is_empty())
	var panel := MemoryPanel.new()
	root.add_child(panel)
	panel.configure(1)
	panel.size = Vector2(1160, 650)
	own = Memory.for_owner(records, 1, world)
	panel._set_memory(own)
	panel._select_region(own.visits[1].key)
	assert(panel.selected_key == own.visits[1].key and panel._map.selected_key == panel.selected_key)
	assert("(150.0, 110.0)" in panel.details.text)
	panel.feed.error = ""
	panel.feed.updated_ms = Time.get_ticks_msec()
	panel._record_received_ms = panel.feed.updated_ms
	panel._refresh_status(panel.feed.updated_ms)
	assert(panel.live_status == "LIVE")
	panel._refresh_status(panel.feed.updated_ms + 1000)
	assert(panel.live_status == "STALE" and panel.memory.visits[1].age_ticks == 1800)
	panel._set_memory(Memory.for_owner(records, 1, world))
	assert(panel.selected_key == own.visits[1].key)
	panel.feed.world = world
	panel.feed.records = records
	panel.update_source("user://missing-memory-fixture", "fixture", "fixture", replacement)
	assert(panel.memory.is_empty() and panel.selected_key.is_empty() and panel.table.get_root().get_child_count() == 0)
	panel.queue_free()
	await process_frame
	print("PASS: private exploration projection, bounded visits, decay, tick wrap, selection, frozen stale ages and lifecycle clearing.")
	quit(0)
