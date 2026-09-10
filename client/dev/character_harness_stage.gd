extends Node2D

var views: Array[Node2D] = []
var show_geometry := true
var overlay: Node2D


func _ready() -> void:
	overlay = Node2D.new()
	overlay.z_index = 1
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)


func refresh() -> void:
	queue_redraw()
	if overlay != null: overlay.queue_redraw()


func _draw() -> void:
	for x in range(-128, 385, 32):
		draw_line(Vector2(x, -96), Vector2(x, 160), Color("273b4c"), 1.0)
	for y in range(-96, 161, 32):
		draw_line(Vector2(-128, y), Vector2(384, y), Color("273b4c"), 1.0)


func _draw_overlay() -> void:
	for index in views.size():
		var view = views[index]
		if not view.visible: continue
		var anchor: Vector2 = view.position
		if show_geometry:
			var bounds: Rect2 = view.body_bounds()
			bounds.position += anchor
			overlay.draw_rect(bounds, Color("f2d36c"), false, 1.0)
			overlay.draw_line(anchor - Vector2(4, 0), anchor + Vector2(4, 0), Color("70ffff"), 1.0)
			overlay.draw_line(anchor - Vector2(0, 4), anchor + Vector2(0, 4), Color("70ffff"), 1.0)
		var text := "%s: size %.2f" % ["A" if index == 0 else "B", view.preview_size]
		overlay.draw_string(ThemeDB.fallback_font, anchor + Vector2(-24, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("d6e4ef"))
