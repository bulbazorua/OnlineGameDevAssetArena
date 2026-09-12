extends Control

# Draws one creature's remembered visits on the arena frame: a square per region,
# a dot at the last occupied position, the self position and the selection.
# Blank is unvisited or forgotten. A region is the memory's own unit, not a tile.
const Style = preload("res://dev/ui/dev_ui_style.gd")
const FRESH := Color("7de2b2")
const FADING := Color("edb96f")
const ENCOUNTER := Color("d8a0f0")
var memory: Dictionary = {}
var selected_key := ""
var frame: Control


func set_memory(value: Dictionary, selection: String) -> void:
	memory = value
	selected_key = selection
	queue_redraw()


# The remembered region under a world point, or "" when nothing is remembered there.
func region_at(world: Vector2) -> String:
	if memory.is_empty(): return ""
	var cell: Vector2 = (world / float(memory.region_size)).floor()
	var key := "%d,%d" % [int(cell.x), int(cell.y)]
	for visit: Dictionary in memory.visits:
		if visit.key == key: return key
	return ""


func _draw() -> void:
	if frame == null or not frame.has_arena() or memory.is_empty(): return
	for visit: Dictionary in memory.visits: _draw_visit(visit)
	Style.draw_self_marker(self, frame.world_to_view(Vector2(memory.position[0], memory.position[1])), "SELF")


func _draw_visit(visit: Dictionary) -> void:
	var region_size: float = memory.region_size
	var region := Rect2(frame.world_to_view(Vector2(visit.region[0], visit.region[1]) * region_size), Vector2.ONE * region_size * frame.scale_factor())
	var tint := FADING.lerp(FRESH, float(visit.strength))
	var selected: bool = visit.key == selected_key
	draw_rect(region, Color(tint, 0.08 + 0.28 * visit.strength))
	draw_rect(region, Style.SELECTED if selected else Color(tint, 0.35 + 0.65 * visit.strength), false, 2 if selected else 1)
	draw_circle(frame.world_to_view(Vector2(visit.position[0], visit.position[1])), 4, ENCOUNTER if visit.opponent_seen else tint)
	Style.draw_number(self, region.position + Vector2(4, 13), int(visit.number), tint, 12)
