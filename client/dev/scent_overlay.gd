extends Node2D

# Host diagnostic heatmap of the shared scent field: privileged world data drawn
# under the actors, never anything a creature received. Filters change only the
# drawing; the field itself is read as published.
const Feed = preload("res://dev/scent_feed.gd")
const FieldImage = preload("res://dev/scent_field_image.gd")
const SenseFeed = preload("res://dev/sense_feed.gd")
const HUMAN := Color("ffb454")
const ORC := Color("7de2b2")
const CATEGORIES := [
	{"key": "human", "label": "Human scent (host field)", "color": HUMAN},
	{"key": "orc", "label": "Orc scent (host field)", "color": ORC},
	{"key": "range_p1", "label": "Smell range P1", "color": Color("58a6ff")},
	{"key": "range_p2", "label": "Smell range P2", "color": Color("ffac62")},
]
var enabled := false
var categories := {"human": true, "orc": true, "range_p1": true, "range_p2": true}
var feed := Feed.new()
var status := "Scent field: waiting for arena"
var painter := FieldImage.new()
var _arena: Node2D
var _sense_feed: RefCounted
var _path := ""
var _run_id := ""
var _elapsed := 0.0
var _stale := true


func configure(arena: Node2D, sense_feed: RefCounted) -> void:
	_arena = arena
	_sense_feed = sense_feed
	name = "ScentOverlay"
	z_index = 89
	process_priority = 100
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dev-ai-dir="): _path = argument.trim_prefix("--dev-ai-dir=").path_join("scent.json")
		elif argument.begins_with("--dev-ai-run="): _run_id = argument.trim_prefix("--dev-ai-run=")
	arena.add_child(self)
	visible = false


func set_enabled(value: bool) -> void:
	enabled = value and OS.is_debug_build() and "--dev" in OS.get_cmdline_user_args()
	_process(0)


func set_category(key: String, value: bool) -> void:
	if categories.has(key): categories[key] = value
	_process(0)


func _process(delta: float) -> void:
	visible = false
	if not enabled:
		status = "Scent field hidden [F8]"
		return
	if not _arena.visible or _arena.snapshot == null:
		status = "Scent field: waiting for arena"
		return
	if _arena.network.player_id == 0:
		status = "Scent field: unavailable in audience view"
		return
	if not _path.is_absolute_path() or _run_id.is_empty():
		status = "Scent field: needs AI_DEBUG=1"
		return
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0
		feed.read_snapshot(_path, _run_id, _arena.content.fingerprint.hex_encode())
	_stale = feed.is_stale() or not feed.error.is_empty() or Time.get_ticks_msec() - _arena._last_world_ms > _arena.STALE_WORLD_MS
	if not _matches_world():
		status = "Scent field: " + (feed.error if not feed.error.is_empty() else "waiting for this round's field")
		return
	_repaint()
	status = "Scent field: STALE" if _stale else "Scent field: host diagnostic, %d cells with scent" % painter.painted_cells
	visible = categories.human or categories.orc or categories.range_p1 or categories.range_p2
	modulate.a = 0.4 if _stale else 1.0
	if visible: queue_redraw()


func _matches_world() -> bool:
	var state = _arena.snapshot
	var field: Dictionary = feed.field
	return field.get("valid", false) and int(field.round_id) == state.round_id and int(field.map_id) == state.map_id and int(field.width) == _arena.world.definition.width and int(field.height) == _arena.world.definition.height


# The shared painter rebuilds the one-pixel-per-cell image only when the field content or filters changed.
func _repaint() -> void:
	painter.repaint(feed, {"Human": categories.human, "Orc": categories.orc})


func _draw() -> void:
	if painter.texture == null or not feed.field.get("valid", false): return
	var tile := float(feed.field.tile_size)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	draw_texture_rect(painter.texture, Rect2(Vector2.ZERO, Vector2(int(feed.field.width), int(feed.field.height)) * tile), false)
	_draw_ranges()
	var age := (int(_arena.snapshot.server_tick) - int(feed.field.tick)) & 0xffffffff
	var label := "HOST SCENT FIELD · privileged world data · field tick %d (%d ms old)%s" % [int(feed.field.tick), roundi(age * 1000.0 / 60.0), " · STALE" if _stale else ""]
	draw_string(ThemeDB.fallback_font, Vector2(9, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
	draw_string(ThemeDB.fallback_font, Vector2(8, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ff8793"))


# Each observer's nose reach at its sampled position, from the same live feed the
# senses windows use. Not a creature reading, only where a reading could come from.
func _draw_ranges() -> void:
	if _sense_feed == null: return
	for record: Dictionary in _sense_feed.records:
		var owner := int(record.owner_id)
		if not categories["range_p%d" % owner]: continue
		if int(record.round_id) != _arena.snapshot.round_id or int(record.map_id) != _arena.snapshot.map_id: continue
		var nose: Dictionary = record.olfaction
		if nose.status != "Sampled": continue
		var color: Color = CATEGORIES[1 + owner].color
		var center := Vector2(nose.position[0], nose.position[1])
		draw_arc(center, float(nose.profile.range), 0, TAU, 96, Color(color, 0.45), 1.2, true)
		draw_string(ThemeDB.fallback_font, center + Vector2(-30, float(nose.profile.range) + 14), "P%d smell range %.0f" % [owner, float(nose.profile.range)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(color, 0.8))


func diagnostics() -> Dictionary:
	return {"enabled": enabled, "visible": visible, "status": status, "stale": _stale, "painted_cells": painter.painted_cells, "rebuilds": painter.rebuilds,
		"published_us": feed.published_us, "read_us": feed.read_us, "error": feed.error, "categories": categories,
		"field": {"valid": feed.field.get("valid", false), "round_id": feed.field.get("round_id", 0), "tick": feed.field.get("tick", 0), "width": feed.field.get("width", 0), "height": feed.field.get("height", 0)}}


# The drawn colour of one field cell, for automated checks against the published data.
func cell_level(class_index: int, cell: Vector2i) -> int:
	return feed.level(class_index, cell)
