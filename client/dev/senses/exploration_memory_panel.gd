extends VBoxContainer

const Feed = preload("res://dev/search/search_feed.gd")
const Memory = preload("res://dev/senses/exploration_memory.gd")
const MemoryMap = preload("res://dev/senses/exploration_memory_map.gd")
var feed := Feed.new()
var owner_id := 0
var memory: Dictionary = {}
var live_status := "WAITING"
var selected_key := ""
var read_us_max := 0
var _next_read_ms := 0
var _record_received_ms := 0
var _record_key := ""
var _world: Dictionary = {}
var _summary: Label
var _status: Label
var _details: Label
var _map: Control
var _table: Tree


func configure(owner: int) -> void:
	owner_id = owner
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary = _label("Waiting for this creature's remembered visits", self, 16)
	_status = _label("", self, 13)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_map = MemoryMap.new()
	_map.custom_minimum_size = Vector2(400, 350)
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.region_selected.connect(_select_region)
	split.add_child(_map)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 480
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(column)
	_label("REMEMBERED VISITS", column, 16)
	_table = Tree.new()
	_table.columns = 4
	_table.hide_root = true
	_table.hide_folding = true
	_table.column_titles_visible = true
	_table.select_mode = Tree.SELECT_ROW
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for index in 4:
		_table.set_column_title(index, ["Visit / region", "Age", "Strength", "Opponent seen"][index])
		_table.set_column_custom_minimum_width(index, [135, 75, 90, 130][index])
	_table.item_selected.connect(_selected)
	column.add_child(_table)
	_details = _label("Select a remembered region on the map or in the list.", column, 14)
	_details.custom_minimum_size.y = 110
	var legend := _label("Green = fresh · amber = fading · purple dot = opponent seen on that visit\nSquares mark visited regions; dots mark the last occupied positions.", self, 13)
	legend.modulate = Color("a2b3c8")


func _label(text: String, parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


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
	_status.text = "%s · private exploration memory" % live_status
	if live_status in ["STALE", "DISCONNECTED"]: _status.text += " · last received data; ages are frozen"
	elif memory.is_empty(): _status.text += " · no matching search memory yet"
	if not feed.error.is_empty(): _status.text += " · " + feed.error
	_status.modulate = Color("8cddb0") if live_status == "LIVE" else Color("ffb454")
	_map.modulate.a = 1.0 if live_status == "LIVE" else 0.35


func _set_memory(value: Dictionary) -> void:
	memory = value
	var root := _table.get_root()
	if root == null: root = _table.create_item()
	var visits: Array = memory.get("visits", [])
	while root.get_child_count() > visits.size(): root.get_child(root.get_child_count() - 1).free()
	_details.text = "Select a remembered region on the map or in the list."
	_summary.text = "No remembered visits available for this creature."
	var selected_item: TreeItem
	if not memory.is_empty():
		_summary.text = "P%d · entity %d · round %d · self %s\n%d / %d regions remembered · %.0fs retention · source tick %d" % [owner_id, memory.entity_id, memory.round_id, Memory.coordinates(memory.position), memory.visits.size(), memory.capacity, memory.retention_ticks / 60.0, memory.tick]
	for index in visits.size():
		var item := root.get_child(index) if index < root.get_child_count() else _table.create_item(root)
		_update_visit(item, visits[index])
		if visits[index].key == selected_key: selected_item = item
	_table.deselect_all()
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
	item.set_custom_color(2, MemoryMap.FADING.lerp(MemoryMap.FRESH, visit.strength))
	item.set_custom_color(3, MemoryMap.ENCOUNTER if visit.opponent_seen else Color.WHITE)


func _select_region(key: String) -> void:
	var item := _table.get_root().get_first_child()
	while item != null:
		if item.get_metadata(0).key == key:
			item.select(0)
			_selected()
			_table.scroll_to_item(item)
			return
		item = item.get_next()


func _selected() -> void:
	var item := _table.get_selected()
	if item == null or memory.is_empty(): return
	var visit: Dictionary = item.get_metadata(0)
	selected_key = visit.key
	var remaining: float = (memory.retention_ticks - visit.age_ticks) / 60.0
	_details.text = "Visit %d · region (%d, %d)\nLast occupied position %s\nVisited %.1fs ago · decay time left %.1fs\n%s" % [visit.number, visit.region[0], visit.region[1], Memory.coordinates(visit.position), visit.age_ticks / 60.0, remaining, "An opponent was seen on this visit." if visit.opponent_seen else "No opponent was seen on this visit. The area may still contain one."]
	_map.set_memory(memory, selected_key)


func debug_state() -> Dictionary:
	return {"status": live_status, "memory": memory, "selected_key": selected_key, "read_us_max": read_us_max}
