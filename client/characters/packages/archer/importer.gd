extends "res://characters/import/character_importer.gd"

const AnimationSet = preload("res://characters/character_animation_set.gd")


func import_assets(context: Dictionary) -> Variant:
	var path: String = context.module_root.path_join("art.json")
	var config = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not config is Dictionary or config.get("frame_side") != 192 or not config.get("strips") is Array:
		context.sources.fail("archer_config", path, "Archer requires its 192px strip configuration")
		return null
	if not _numbers(config.get("body_rect"), 4) or not _numbers(config.get("feet"), 2):
		context.sources.fail("archer_config", path, "Invalid Archer body/feet calibration")
		return null
	var art := AnimationSet.new()
	art.body_rect_px = Rect2(config.body_rect[0], config.body_rect[1], config.body_rect[2], config.body_rect[3])
	art.reference_span_px = maxf(art.body_rect_px.size.x, art.body_rect_px.size.y)
	art.foot_anchor_px = Vector2(config.feet[0], config.feet[1])
	for strip: Variant in config.strips:
		if not strip is Dictionary or not strip.get("clip") is String or not strip.get("file") is String or not _positive_integer(strip.get("count")):
			context.sources.fail("archer_config", path, "Invalid Archer strip entry")
			return null
		var source: Image = context.sources.read_image(strip.file)
		if source == null: return null
		if source.get_size() != Vector2i(int(strip.count) * 192, 192):
			context.sources.fail("archer_layout", strip.file, "Archer strip dimensions disagree with the authored frame count")
			return null
		var frames: Array[Texture2D] = []
		for index in int(strip.count):
			var frame: Texture2D = context.sources.extract_frame(strip.file, Rect2i(index * 192, 0, 192, 192), strip.clip, index)
			if frame == null: return null
			frames.append(frame)
		art.clips[strip.clip] = {"frames": frames, "fps": strip.get("fps"), "loop": strip.get("loop")}
	if not config.get("authored_sequences") is Array:
		context.sources.fail("archer_config", path, "Missing Archer authored sequences")
		return null
	for sequence: Variant in config.authored_sequences:
		if not _import_sequence(context, art, sequence, path): return null
	return art


func _import_sequence(context: Dictionary, art: CharacterAnimationSet, sequence: Variant, config_path: String) -> bool:
	if not sequence is Dictionary or not sequence.get("clip") is String or not sequence.get("file") is String or not _numbers(sequence.get("source_size"), 2) or not sequence.get("frames") is Array or sequence.frames.is_empty() or not _numbers([sequence.get("scale")], 1) or sequence.scale <= 0 or sequence.scale > 1:
		context.sources.fail("archer_config", config_path, "Invalid Archer authored sequence")
		return false
	var source: Image = context.sources.read_image(sequence.file)
	if source == null: return false
	if source.get_width() != sequence.source_size[0] or source.get_height() != sequence.source_size[1]:
		context.sources.fail("archer_layout", sequence.file, "Archer authored sheet dimensions changed; review its frame rectangles")
		return false
	var frames: Array[Texture2D] = []
	for index in sequence.frames.size():
		var authored: Variant = sequence.frames[index]
		if not authored is Dictionary or not _numbers(authored.get("rect"), 4) or not authored.rect.all(func(value): return value == floor(value)) or not _numbers(authored.get("ground"), 2):
			context.sources.fail("archer_config", config_path, "Invalid Archer crop or ground anchor", {"clip": sequence.clip, "frame": index})
			return false
		var rect := Rect2i(authored.rect[0], authored.rect[1], authored.rect[2], authored.rect[3])
		var texture: Texture2D = context.sources.extract_frame(sequence.file, rect, sequence.clip, index)
		if texture == null: return false
		var resized := Vector2i(roundi(rect.size.x * sequence.scale), roundi(rect.size.y * sequence.scale))
		var source_ground := Vector2(authored.ground[0], authored.ground[1]) - Vector2(rect.position)
		var ground := source_ground * Vector2(resized) / Vector2(rect.size)
		var offset := Vector2i((art.foot_anchor_px - ground).round())
		if resized.x <= 0 or resized.y <= 0 or not Rect2(Vector2.ZERO, rect.size).has_point(source_ground) or not Rect2i(0, 0, 192, 192).encloses(Rect2i(offset, resized)):
			context.sources.fail("archer_normalize", sequence.file, "Archer frame or ground anchor cannot fit the normalized canvas", {"clip": sequence.clip, "frame": index})
			return false
		var crop := texture.get_image()
		crop.convert(Image.FORMAT_RGBA8)
		crop.resize(resized.x, resized.y, Image.INTERPOLATE_NEAREST)
		var canvas := Image.create(192, 192, false, Image.FORMAT_RGBA8)
		canvas.fill(Color.TRANSPARENT)
		canvas.blit_rect(crop, Rect2i(Vector2i.ZERO, resized), offset)
		context.sources.record_transform(sequence.clip, index, {"kind": "resize_canvas", "version": 1,
			"resize_to": [resized.x, resized.y], "interpolation": "nearest", "canvas_size": [192, 192],
			"offset": [offset.x, offset.y], "source_ground_px": authored.ground,
			"target_ground_px": [art.foot_anchor_px.x, art.foot_anchor_px.y]})
		frames.append(ImageTexture.create_from_image(canvas))
	art.clips[sequence.clip] = {"frames": frames, "fps": sequence.get("fps"), "loop": sequence.get("loop")}
	return true


func _numbers(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count and value.all(func(number): return (number is int or number is float) and is_finite(float(number)))


func _positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0 and value <= 1024 and value == floor(value)
