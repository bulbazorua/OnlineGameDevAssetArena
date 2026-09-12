extends Control

# Draws the published scent field over the arena frame: one texture pixel per cell,
# the hovered and pinned cells, and this nose's sampled reach. Nothing here infers a
# position from the field; the nose ring comes from the delivered sample only.
const Style = preload("res://dev/ui/dev_ui_style.gd")
const NO_CELL := Vector2i(-1, -1)
var texture: ImageTexture
var cells := Vector2i.ZERO
var tile_size := 0.0
var field_alpha := 1.0
var selected_cell := NO_CELL
var hover_cell := NO_CELL
var nose: Dictionary = {}
var nose_live := true
var frame: Control


func set_field(image_texture: ImageTexture, width: int, height: int, cell_size: float) -> void:
	texture = image_texture
	cells = Vector2i(width, height)
	tile_size = cell_size
	queue_redraw()


func clear_field() -> void:
	texture = null
	cells = Vector2i.ZERO
	queue_redraw()


func set_nose(position: Vector2, reach_units: float, label: String) -> void:
	nose = {"position": position, "reach": reach_units, "label": label}
	queue_redraw()


func clear_nose() -> void:
	nose = {}
	queue_redraw()


func _draw() -> void:
	if frame == null or not frame.has_arena(): return
	if texture != null and cells.x > 0:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var rect := Rect2(frame.world_to_view(Vector2.ZERO), Vector2(cells) * tile_size * frame.scale_factor())
		draw_texture_rect(texture, rect, false, Color(1, 1, 1, field_alpha))
	if hover_cell != NO_CELL: draw_rect(frame.cell_rect(hover_cell), Color(Style.MUTED, field_alpha), false, 1.0)
	if selected_cell != NO_CELL: draw_rect(frame.cell_rect(selected_cell).grow(1), Color(Style.SELECTED, field_alpha), false, 2.0)
	if nose.is_empty(): return
	var alpha := 1.0 if nose_live else 0.35
	var center: Vector2 = frame.world_to_view(nose.position)
	draw_arc(center, float(nose.reach) * frame.scale_factor(), 0, TAU, 96, Color(Style.RANGE_RING, alpha), 1.2, true)
	draw_circle(center, 5, Color(Style.SELF, alpha))
	Style.draw_text(self, center + Vector2(8, 14), nose.label, 11, Color(Style.TEXT, alpha))
