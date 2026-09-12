extends "res://dev/senses/sense_page.gd"

# The Exploration memory page: one creature's private remembered visits from the
# search feed, on the shared arena frame. Its ages freeze when its source is stale.
const Feed = preload("res://dev/search/search_feed.gd")
const Memory = preload("res://dev/senses/exploration_memory.gd")
const MemoryLayer = preload("res://dev/senses/exploration_memory_layer.gd")
const Overview = preload("res://dev/ui/arena_overview.gd")
const READOUT_HINT := "Hover a remembered region for its visit · blank = unvisited or forgotten, not confirmed empty"
var feed := Feed.new()
var owner_id := 0
var memory: Dictionary = {}
var live_status := "WAITING"
var selected_key := ""
var read_us_max := 0
var overview: Overview
var _map: MemoryLayer
var _next_read_ms := 0
var _record_received_ms := 0
var _record_key := ""
var _world: Dictionary = {}


func configure(owner: int) -> void:
	owner_id = owner
	build_layout("REMEMBERED VISITS", ["Visit / region", "Age", "Strength", "Opponent seen"], [135, 75, 90, 130])
	overview = Overview.new()
	overview.title = "ARENA OVERVIEW · remembered visits only"
	overview.legend_lines = ["square = remembered region: green fresh, amber fading",
		"dot = last occupied position · purple = opponent seen",
		"blank = unvisited or forgotten · outline = developer reference"]
	_map = MemoryLayer.new()
	overview.add_layer(_map)
	overview.pointer_pressed.connect(_pressed)
	overview.pointer_moved.connect(_hover)
	overview.pointer_left.connect(func(): readout.text = READOUT_HINT)
	set_view(ARENA_VIEW, overview)
	table.item_selected.connect(_selected)
	summary.text = "Waiting for this creature's remembered visits"
	timing.text = "WAITING · private exploration memory"
	details.text = "Select a remembered region on the map or in the list."
	readout.text = READOUT_HINT


func set_arena(definition: Variant) -> void:
	overview.set_arena(definition)


func update_source(directory: String, run_id: String, fingerprint: String, world: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var changed := world != _world
	_world = world
	if not memory.is_empty() and not Memory.matches(memory, owner_id, world): _set_memory({})
	if now >= _next_read_ms or changed:
		_next_read_ms = now + 100
		var started := Time.get_ticks_usec()
		feed.read_snapshot(directory.path_join("search.json"), run_id, fingerprint)
		read_us_max = maxi(read_us_max, Time.get_ticks_usec() - started)
		var next := Memory.for_owner(feed.records, owner_id, world) if feed.world == world else {}
		var key := "%s/%s/%s" % [next.get("round_id", -1), next.get("entity_id", -1), next.get("tick", -1)]
		if key != _record_key:
			_record_key = key
			_record_received_ms = now
			_set_memory(next)
	_refresh_status(now)


func _refresh_status(now: int) -> void:
	live_status = "LIVE"
	if memory.is_empty(): live_status = "WAITING"
	elif now - feed.updated_ms > 3000: live_status = "DISCONNECTED"
	elif feed.stale() or now - _record_received_ms > 750: live_status = "STALE"
	timing.text = "%s · private exploration memory" % live_status
	if live_status in ["STALE", "DISCONNECTED"]: timing.text += " · last received data; ages are frozen"
	elif memory.is_empty(): timing.text += " · no matching search memory yet"
	if not feed.error.is_empty(): timing.text += " · " + feed.error
	_map.modulate.a = 1.0 if live_status == "LIVE" else 0.35
	overview.set_badge(live_status if memory.is_empty() else "%s · source tick %d" % [live_status, int(memory.tick)], live_status == "LIVE")


func _set_memory(value: Dictionary) -> void:
	memory = value
	var root := table.get_root()
	if root == null: root = table.create_item()
	var visits: Array = memory.get("visits", [])
	while root.get_child_count() > visits.size(): root.get_child(root.get_child_count() - 1).free()
	details.text = "Select a remembered region on the map or in the list."
	summary.text = "No remembered visits available for this creature."
	var selected_item: TreeItem
	if not memory.is_empty():
		summary.text = "P%d · entity %d · round %d · self %s · %d / %d regions remembered · %.0f s retention · source tick %d" % [owner_id, memory.entity_id, memory.round_id, coordinates(memory.position), memory.visits.size(), memory.capacity, memory.retention_ticks / 60.0, memory.tick]
	for index in visits.size():
		var item := root.get_child(index) if index < root.get_child_count() else table.create_item(root)
		_update_visit(item, visits[index])
		if visits[index].key == selected_key: selected_item = item
	table.deselect_all()
	if selected_item != null:
		selected_item.select(0)
		_selected()
	else: selected_key = ""
	_map.set_memory(memory, selected_key)


func _update_visit(item: TreeItem, visit: Dictionary) -> void:
	item.set_metadata(0, visit)
	item.set_text(0, "%d · (%d, %d)" % [visit.number, visit.region[0], visit.region[1]])
	item.set_text(1, "%.1fs" % (visit.age_ticks / 60.0))
	item.set_text(2, "%.0f%%" % (visit.strength * 100))
	item.set_text(3, "Yes, on visit" if visit.opponent_seen else "Not on visit")
	item.set_custom_color(2, MemoryLayer.FADING.lerp(MemoryLayer.FRESH, visit.strength))
	item.set_custom_color(3, MemoryLayer.ENCOUNTER if visit.opponent_seen else Color.WHITE)


func _select_region(key: String) -> void:
	var item := table.get_root().get_first_child()
	while item != null:
		if item.get_metadata(0).key == key:
			item.select(0)
			_selected()
			table.scroll_to_item(item)
			return
		item = item.get_next()


func _selected() -> void:
	var item := table.get_selected()
	if item == null or memory.is_empty(): return
	var visit: Dictionary = item.get_metadata(0)
	selected_key = visit.key
	var remaining: float = (memory.retention_ticks - visit.age_ticks) / 60.0
	details.text = "Visit %d · region (%d, %d)\nLast occupied position %s\nVisited %.1fs ago · decay time left %.1fs\n%s" % [visit.number, visit.region[0], visit.region[1], coordinates(visit.position), visit.age_ticks / 60.0, remaining, "An opponent was seen on this visit." if visit.opponent_seen else "No opponent was seen on this visit. The area may still contain one."]
	_map.set_memory(memory, selected_key)


func _pressed(world: Vector2) -> void:
	var key := _map.region_at(world)
	if not key.is_empty(): _select_region(key)


func _hover(world: Vector2) -> void:
	if memory.is_empty() or not overview.contains_world(world):
		readout.text = READOUT_HINT
		return
	var region: Vector2 = (world / float(memory.region_size)).floor()
	var key := _map.region_at(world)
	var visit := "not remembered: unvisited or forgotten"
	for entry: Dictionary in memory.visits:
		if entry.key == key: visit = "remembered visit #%d · %.1fs ago" % [entry.number, entry.age_ticks / 60.0]
	readout.text = "Pointer · world (%.0f, %.0f) · region (%d, %d) · %s" % [world.x, world.y, int(region.x), int(region.y), visit]


func debug_state() -> Dictionary:
	return {"status": live_status, "memory": memory, "selected_key": selected_key, "read_us_max": read_us_max, "legend_fits": overview.legend_fits()}
