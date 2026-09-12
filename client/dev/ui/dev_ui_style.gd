extends RefCounted

# One look for every developer inspector canvas: the palette, the legend strip and
# the few marks that mean the same thing everywhere (numbers, selection, self).
const BACKGROUND := Color("101e2c")
const GROUND := Color("152434")
const GRID := Color("27394b")
const OUTLINE := Color("2b4056")
const RANGE_RING := Color("35506a")
const TEXT := Color("c8d3df")
const MUTED := Color("9dabbc")
const NOTE := Color("a2b3c8")
const PRIVILEGED := Color("ff8793")
const SELECTED := Color.WHITE
const SELF := Color.WHITE
const LIVE := Color("8cddb0")
const NOT_LIVE := Color("ffb454")
const LEGEND_FONT_SIZE := 11
const LEGEND_LINE_HEIGHT := 15.0
const LEGEND_PADDING := 12.0
const MIN_SUPPORTED_WIDTH := 400.0
const NUMBER_FONT_SIZE := 16


static func font() -> Font:
	return ThemeDB.fallback_font


static func background(color := BACKGROUND) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	return style


static func status_color(live: bool) -> Color:
	return LIVE if live else NOT_LIVE


# A hidden page has no layout yet; text then wraps at the supported minimum width.
static func layout_width(control: Control) -> float:
	return control.size.x if control.size.x >= MIN_SUPPORTED_WIDTH else MIN_SUPPORTED_WIDTH


static func text_width(text: String, size := LEGEND_FONT_SIZE) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


# Cuts a line down with an ellipsis so it never runs under the text beside it.
static func trim_to_width(text: String, width: float, size := 12) -> String:
	if text_width(text, size) <= width: return text
	var trimmed := text
	while trimmed.length() > 1 and text_width(trimmed + "…", size) > width: trimmed = trimmed.left(trimmed.length() - 1)
	return trimmed.strip_edges() + "…"


# Greedy wrap on the " · " separators so a legend stays readable at narrow widths.
static func wrap_legend(lines: Array[String], width: float) -> Array[String]:
	var wrapped: Array[String] = []
	var limit := width - 20
	for line in lines:
		var current := ""
		for part in line.split(" · "):
			var candidate := part if current.is_empty() else current + " · " + part
			if not current.is_empty() and text_width(candidate) > limit:
				wrapped.append(current)
				current = part
			else:
				current = candidate
		wrapped.append(current)
	return wrapped


static func legend_fits(lines: Array[String], width: float, max_lines := 0) -> bool:
	var wrapped := wrap_legend(lines, width)
	if max_lines > 0 and wrapped.size() > max_lines: return false
	for line in wrapped:
		if text_width(line) > width - 20: return false
	return true


static func legend_height(line_count: int) -> float:
	return line_count * LEGEND_LINE_HEIGHT + LEGEND_PADDING


static func draw_legend(canvas: CanvasItem, lines: Array[String], first_baseline: float, swatches: Dictionary) -> void:
	var y := first_baseline
	for line in lines:
		var x := 10.0
		for key: String in swatches:
			if line.begins_with(key):
				canvas.draw_rect(Rect2(Vector2(x, y - 9), Vector2(10, 10)), swatches[key])
				canvas.draw_rect(Rect2(Vector2(x, y - 9), Vector2(10, 10)), OUTLINE, false, 1.0)
				x += 14
				break
		canvas.draw_string(font(), Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE, MUTED)
		y += LEGEND_LINE_HEIGHT


static func draw_text(canvas: CanvasItem, point: Vector2, text: String, size := 12, color := TEXT) -> void:
	canvas.draw_string(font(), point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func draw_number(canvas: CanvasItem, point: Vector2, number: int, color: Color, size := NUMBER_FONT_SIZE) -> void:
	canvas.draw_string(font(), point + Vector2(1, 1), str(number), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.BLACK)
	canvas.draw_string(font(), point, str(number), HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func draw_selection_ring(canvas: CanvasItem, point: Vector2, radius: float) -> void:
	canvas.draw_arc(point, radius, 0, TAU, 32, SELECTED, 2, true)


static func draw_self_marker(canvas: CanvasItem, point: Vector2, label: String, facing := Vector2.ZERO) -> void:
	canvas.draw_circle(point, 6, SELF)
	if facing != Vector2.ZERO: canvas.draw_line(point, point + facing.normalized() * 24, SELF, 2, true)
	canvas.draw_string(font(), point + Vector2(10, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SELF)


static func draw_compass(canvas: CanvasItem, north: Vector2, east: Vector2, south: Vector2, west: Vector2) -> void:
	for pair in [[north, "N"], [east, "E"], [south, "S"], [west, "W"]]:
		canvas.draw_string(font(), pair[0], pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)


# Screen angle of one of the eight compass headings, north up: N, NE, E, SE, S, SW, W, NW.
static func heading_angle(index: int) -> float:
	return index * PI / 4.0 - PI / 2.0


# A 45-degree slice between two radii, the shape both the eye cue and a nose zone use.
static func wedge(center: Vector2, inner: float, outer: float, angle: float, half_width := PI / 8.0) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for step in 13: polygon.append(center + Vector2.from_angle(angle - half_width + half_width * 2.0 * step / 12.0) * outer)
	for step in 13: polygon.append(center + Vector2.from_angle(angle + half_width - half_width * 2.0 * step / 12.0) * inner)
	return polygon
