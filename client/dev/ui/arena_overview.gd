extends Control

# North-up frame of the whole arena, shared by every sense page. It owns the fit,
# the world-to-view transform, the reference outline, grid, compass and legend
# strip, and turns pointer positions into world positions. Layers draw meaning.
signal pointer_moved(world: Vector2)
signal pointer_left
signal pointer_pressed(world: Vector2)

const Style = preload("res://dev/ui/dev_ui_style.gd")
const TOP := 30.0
const SIDE := 22.0
const BOTTOM := 18.0
const LEGEND_LINES := 3
const NO_CELL := Vector2i(-1, -1)
var map_id := 0
var arena_name := ""
var cells := Vector2i.ZERO
var tile_size := 0.0
var title := "ARENA OVERVIEW"
var title_color := Style.MUTED
var badge := ""
var badge_live := false
var fit_label := "Fit: whole arena"
var legend_lines: Array[String] = []
var legend_swatches: Dictionary = {}
var _arena_clip: Control
var _chrome: Control


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_arena_clip = Control.new()
	_arena_clip.clip_contents = true
	_arena_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arena_clip)
	_chrome = Chrome.new()
	_chrome.overview = self
	_add_full_rect(_chrome)


# Takes the catalog definition's identity and geometry; returns true when it changed.
func set_arena(definition: Variant) -> bool:
	var next_id := 0 if definition == null else int(definition.id)
	var next_cells := Vector2i.ZERO if definition == null else Vector2i(int(definition.width), int(definition.height))
	var next_tile := 0.0 if definition == null else float(definition.tile_size)
	var changed := next_id != map_id or next_cells != cells or next_tile != tile_size
	map_id = next_id
	cells = next_cells
	tile_size = next_tile
	arena_name = "" if definition == null else str(definition.display_name)
	if changed: redraw_layers()
	return changed


# The status word in the corner belongs to the page's own source clock, never to the frame.
func set_badge(text: String, live: bool) -> void:
	if text == badge and live == badge_live: return
	badge = text
	badge_live = live
	_chrome.queue_redraw()


func has_arena() -> bool:
	return cells.x > 0 and cells.y > 0 and tile_size > 0


func world_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(cells) * tile_size)


# The room left for the arena once the title, compass letters and legend have theirs.
func plot_rect() -> Rect2:
	var legend_height := Style.legend_height(LEGEND_LINES)
	return Rect2(Vector2(SIDE, TOP), Vector2(maxf(size.x - SIDE * 2, 1), maxf(size.y - TOP - BOTTOM - legend_height, 1)))


func scale_factor() -> float:
	if not has_arena(): return 1.0
	var plot := plot_rect()
	var world := world_bounds().size
	return maxf(minf(plot.size.x / world.x, plot.size.y / world.y), 0.000001)


# Where the arena lands: the whole map, aspect kept, centred in the plot.
func arena_rect() -> Rect2:
	var plot := plot_rect()
	var extent := world_bounds().size * scale_factor()
	return Rect2(plot.get_center() - extent / 2.0, extent)


func world_to_view(point: Vector2) -> Vector2:
	return arena_rect().position + point * scale_factor()


func view_to_world(point: Vector2) -> Vector2:
	return (point - arena_rect().position) / scale_factor()


func contains_world(point: Vector2) -> bool:
	return has_arena() and world_bounds().has_point(point)


func cell_of(world: Vector2) -> Vector2i:
	if not contains_world(world): return NO_CELL
	return Vector2i((world / tile_size).floor())


func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(world_to_view(Vector2(cell) * tile_size), Vector2.ONE * tile_size * scale_factor())


func add_layer(layer: Control) -> void:
	layer.set("frame", self)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_arena_clip.add_child(layer)
	_layout_layers()


func _add_full_rect(child: Control) -> void:
	child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	child.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(child)


# Keep layer coordinates aligned with the frame while clipping at the arena edge.
func _layout_layers() -> void:
	var rect := arena_rect()
	_arena_clip.position = rect.position
	_arena_clip.size = rect.size
	for layer in _arena_clip.get_children():
		layer.position = -rect.position
		layer.size = size


func redraw_layers() -> void:
	_layout_layers()
	for layer in _arena_clip.get_children(): layer.queue_redraw()
	_chrome.queue_redraw()
	queue_redraw()


func legend_fits() -> bool:
	return Style.legend_fits(legend_lines, Style.layout_width(self), LEGEND_LINES)


func _gui_input(event: InputEvent) -> void:
	if not has_arena(): return
	if event is InputEventMouseMotion:
		pointer_moved.emit(view_to_world(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pointer_pressed.emit(view_to_world(event.position))
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT: pointer_left.emit()
	elif what == NOTIFICATION_RESIZED and _chrome != null: redraw_layers()


# Grid lines every few cells so a large map does not become a dense mesh.
func grid_step_cells() -> int:
	var longest := maxi(cells.x, cells.y)
	for step in [1, 2, 4, 5, 8, 10, 16]:
		if longest / step <= 32: return step
	return 32


func _draw() -> void:
	draw_style_box(Style.background(), Rect2(Vector2.ZERO, size))
	if not has_arena():
		Style.draw_text(self, Vector2(20, 48), "Waiting for the arena definition", 14, Style.NOTE)
		return
	var rect := arena_rect()
	draw_rect(rect, Style.GROUND)
	var step := grid_step_cells() * tile_size * scale_factor()
	var x := rect.position.x + step
	while x < rect.end.x - 0.5:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Style.GRID)
		x += step
	var y := rect.position.y + step
	while y < rect.end.y - 0.5:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Style.GRID)
		y += step
	draw_rect(rect, Style.OUTLINE, false, 1.0)


# Title, status badge, compass, corner coordinates, fit label and legend, on top of every layer.
class Chrome extends Control:
	var overview: Control

	func _draw() -> void:
		var badge: String = overview.badge
		var badge_width := 0.0 if badge.is_empty() else Style.text_width(badge, 12) + 16
		Style.draw_text(self, Vector2(10, 16), Style.trim_to_width(overview.title, overview.size.x - 20 - badge_width, 12), 12, overview.title_color)
		if not badge.is_empty():
			Style.draw_text(self, Vector2(overview.size.x - badge_width + 6, 16), badge, 12, Style.status_color(overview.badge_live))
		var legend_top: float = overview.size.y - Style.legend_height(overview.LEGEND_LINES)
		if overview.has_arena():
			var rect: Rect2 = overview.arena_rect()
			var center := rect.get_center()
			Style.draw_compass(self, Vector2(center.x - 4, rect.position.y - 6), Vector2(rect.end.x + 6, center.y + 5), Vector2(center.x - 4, rect.end.y + 14), Vector2(rect.position.x - 16, center.y + 5))
			var extent: Vector2 = overview.world_bounds().size
			Style.draw_text(self, rect.position + Vector2(3, 11), "(0, 0)", 10, Style.MUTED)
			var corner := "(%.0f, %.0f)" % [extent.x, extent.y]
			Style.draw_text(self, rect.end - Vector2(Style.text_width(corner, 10) + 3, 4), corner, 10, Style.MUTED)
			var fit := "%s · %s %d×%d cells · %.0f units per cell" % [overview.fit_label, overview.arena_name, overview.cells.x, overview.cells.y, overview.tile_size]
			Style.draw_text(self, Vector2(overview.size.x - Style.text_width(fit, 11) - 10, legend_top - 4), fit, 11, Style.MUTED)
		var wrapped: Array[String] = Style.wrap_legend(overview.legend_lines, Style.layout_width(overview))
		Style.draw_legend(self, wrapped, legend_top + Style.LEGEND_LINE_HEIGHT, overview.legend_swatches)
