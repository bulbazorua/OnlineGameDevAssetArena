extends Control

# Frame for one sensor's local reach, shared by the eye and the nose views: the
# plot circle, guide rings, compass letters, self mark and legend strip. A sense
# draws its own meaning on a layer between this background and this chrome.
const Style = preload("res://dev/ui/dev_ui_style.gd")
const TOP_PADDING := 24.0
var range_units := 1.0
var guide_rings: Array[float] = [1.0, 0.5]
var outer_ring_label := ""
var self_label := "SELF"
var self_facing := Vector2.ZERO
var show_self := true
var empty_text := ""
var legend_lines: Array[String] = []
var legend_swatches: Dictionary = {}
var _chrome: Control


func _init() -> void:
	_chrome = Chrome.new()
	_chrome.radar = self
	_add_full_rect(_chrome)


func add_layer(layer: Control) -> void:
	layer.set("frame", self)
	_add_full_rect(layer)
	move_child(_chrome, get_child_count() - 1)


func _add_full_rect(child: Control) -> void:
	child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	child.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(child)


func redraw_layers() -> void:
	for child in get_children(): child.queue_redraw()
	queue_redraw()


func legend_width() -> float:
	return Style.layout_width(self)


func wrapped_legend() -> Array[String]:
	return Style.wrap_legend(legend_lines, legend_width())


func legend_fits() -> bool:
	return Style.legend_fits(legend_lines, legend_width())


# Where the picture sits: the legend takes the bottom, the compass ring the rest.
func plot_geometry() -> Dictionary:
	var legend := wrapped_legend()
	var legend_height := Style.legend_height(legend.size())
	var plot := Rect2(Vector2(0, TOP_PADDING), Vector2(size.x, size.y - legend_height - TOP_PADDING))
	return {"center": plot.get_center(), "radius": minf(plot.size.x, plot.size.y) * 0.42, "legend": legend, "legend_height": legend_height}


func pixels_per_unit() -> float:
	return plot_geometry().radius / maxf(range_units, 0.001)


# Screen point for a heading (screen angle, north up) at a world distance from the sensor.
func polar_to_view(angle: float, distance_units: float) -> Vector2:
	return plot_geometry().center + Vector2.from_angle(angle) * distance_units * pixels_per_unit()


func _draw() -> void:
	draw_style_box(Style.background(), Rect2(Vector2.ZERO, size))
	if not empty_text.is_empty():
		Style.draw_text(self, Vector2(20, 40), empty_text, 14, Style.NOTE)
		return
	var geometry := plot_geometry()
	var center: Vector2 = geometry.center
	draw_line(Vector2(center.x, 18), Vector2(center.x, size.y - geometry.legend_height - 4), Style.GRID)
	draw_line(Vector2(18, center.y), Vector2(size.x - 18, center.y), Style.GRID)


# Rings, self mark, compass letters and legend, drawn above every sense layer.
class Chrome extends Control:
	var radar: Control

	func _draw() -> void:
		if not radar.empty_text.is_empty(): return
		var geometry: Dictionary = radar.plot_geometry()
		var center: Vector2 = geometry.center
		var radius: float = geometry.radius
		for fraction: float in radar.guide_rings:
			if fraction <= 0 or fraction > 1: continue
			var outer := is_equal_approx(fraction, 1.0)
			draw_arc(center, radius * fraction, 0, TAU, 96 if outer else 64, Style.RANGE_RING if outer else Style.OUTLINE, 1.2 if outer else 1.0, true)
		if not radar.outer_ring_label.is_empty():
			Style.draw_text(self, center + Vector2(-14, -radius - 6), radar.outer_ring_label, 11, Style.MUTED)
		if radar.show_self: Style.draw_self_marker(self, center, radar.self_label, radar.self_facing)
		Style.draw_compass(self, Vector2(center.x - 4, center.y - radius - 18), Vector2(center.x + radius + 8, center.y + 5), Vector2(center.x - 4, center.y + radius + 18), Vector2(center.x - radius - 18, center.y + 5))
		Style.draw_legend(self, geometry.legend, radar.size.y - geometry.legend_height + Style.LEGEND_LINE_HEIGHT, radar.legend_swatches)
