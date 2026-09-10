extends "res://characters/import/character_importer.gd"

const AnimationSet = preload("res://characters/character_animation_set.gd")


func import_assets(context: Dictionary) -> Variant:
	var path: String = context.module_root.path_join("art.json")
	var config = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not config is Dictionary or not _numbers(config.get("cell"), 2) or config.cell[0] != 100 or config.cell[1] != 100 or not config.get("animations") is Dictionary:
		context.sources.fail("orc_config", path, "Orc requires its 100px split-strip configuration")
		return null
	if not _numbers(config.get("body"), 4) or not _numbers(config.get("ground"), 2):
		context.sources.fail("orc_config", path, "Invalid Orc body/feet calibration")
		return null
	var art := AnimationSet.new()
	art.body_rect_px = Rect2(config.body[0], config.body[1], config.body[2], config.body[3])
	art.reference_span_px = maxf(art.body_rect_px.size.x, art.body_rect_px.size.y)
	art.foot_anchor_px = Vector2(config.ground[0], config.ground[1])
	for clip: String in config.animations:
		var animation: Variant = config.animations[clip]
		if not animation is Dictionary or not animation.get("source") is String or not _frame_count(animation.get("frames")):
			context.sources.fail("orc_config", path, "Invalid Orc animation entry: " + clip)
			return null
		var source: Image = context.sources.read_image(animation.source)
		if source == null: return null
		if source.get_size() != Vector2i(int(animation.frames) * 100, 100):
			context.sources.fail("orc_layout", animation.source, "Orc strip dimensions disagree with the authored frame count")
			return null
		var frames: Array[Texture2D] = []
		for index in int(animation.frames):
			var frame: Texture2D = context.sources.extract_frame(animation.source, Rect2i(index * 100, 0, 100, 100), clip, index)
			if frame == null: return null
			frames.append(frame)
		art.clips[clip] = {"frames": frames, "fps": animation.get("rate"), "loop": animation.get("repeat")}
	return art


func _numbers(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count and value.all(func(number): return (number is int or number is float) and is_finite(float(number)))


func _frame_count(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0 and value <= 1024 and value == floor(value)
