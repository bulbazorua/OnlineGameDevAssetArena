extends RefCounted

# One image of the published scent field, one pixel per cell, shared by the F8
# arena heatmap and the inspector minimap. Level 0-255 follows a fixed alpha ramp,
# so a faint field stays faint: nothing is scaled to the current maximum.
const Feed = preload("res://dev/scent_feed.gd")
const Readings = preload("res://dev/senses/olfaction_readings.gd")
const FLOOR_ALPHA := 0.06
const MAX_ALPHA := 0.42
var texture: ImageTexture
var image: Image
var painted_cells := 0
var rebuilds := 0
var floor_alpha := FLOOR_ALPHA
var max_alpha := MAX_ALPHA
var painted_key := ""


# The field content changes only with its tick; a republished or stale copy of the
# same tick keeps the old image, and so does an unchanged filter.
static func content_key(feed: RefCounted, show: Dictionary) -> String:
	var field: Dictionary = feed.field
	if not field.get("valid", false): return ""
	var shown := []
	for scent_class: String in Feed.CLASSES: shown.append(bool(show.get(scent_class, true)))
	return "%d/%d/%d/%dx%d/%s" % [int(field.round_id), int(field.map_id), int(field.tick), int(field.width), int(field.height), shown]


func repaint(feed: RefCounted, show: Dictionary) -> bool:
	var key := content_key(feed, show)
	if key.is_empty():
		clear()
		return false
	if key == painted_key: return false
	painted_key = key
	rebuilds += 1
	var width := int(feed.field.width)
	var height := int(feed.field.height)
	image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	painted_cells = 0
	for y in height:
		for x in width:
			var levels: Array[int] = []
			for index in Feed.CLASSES.size():
				levels.append(feed.level(index, Vector2i(x, y)) if show.get(Feed.CLASSES[index], true) else 0)
			var color := cell_color(levels)
			if color.a > 0: painted_cells += 1
			image.set_pixel(x, y, color)
	if texture == null: texture = ImageTexture.create_from_image(image)
	else: texture.set_image(image)
	return true


# Mixes the shown class colours by level; alpha follows the summed level on the ramp.
func cell_color(levels: Array[int]) -> Color:
	var color := Color(0, 0, 0, 0)
	var total := 0.0
	for index in levels.size():
		var level := levels[index] / 255.0
		if level <= 0: continue
		color += Readings.color_of(Feed.CLASSES[index]) * level
		total += level
	if total <= 0: return Color(0, 0, 0, 0)
	return Color(color.r / total, color.g / total, color.b / total, floor_alpha + max_alpha * minf(total, 1.0))


func clear() -> void:
	texture = null
	image = null
	painted_cells = 0
	painted_key = ""
