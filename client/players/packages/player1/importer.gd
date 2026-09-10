extends "res://characters/import/character_importer.gd"

const AnimationSet = preload("res://characters/character_animation_set.gd")


# Player1 alone interprets these uneven pose sheets. No other package is read.
func import_assets(context: Dictionary) -> Variant:
	var path: String = context.module_root.path_join("art.json")
	var config = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not config is Dictionary or config.get("schema_version") != 1 or not _numbers(config.get("source_size"), 2) or not _numbers(config.get("canvas_size"), 2) or config.get("scale") != 0.25 or not config.get("sequences") is Array or not _numbers(config.get("body_rect"), 4) or not _numbers(config.get("feet"), 2):
		context.sources.fail("player1_config", path, "Invalid Player1 sheet calibration")
		return null
	if Vector2(config.source_size[0], config.source_size[1]) != Vector2(2172, 724) or Vector2(config.canvas_size[0], config.canvas_size[1]) != Vector2(192, 192):
		context.sources.fail("player1_config", path, "Player1 expects 2172x724 sources and a 192px canvas")
		return null
	var art := AnimationSet.new()
	art.body_rect_px = Rect2(config.body_rect[0], config.body_rect[1], config.body_rect[2], config.body_rect[3])
	art.reference_span_px = maxf(art.body_rect_px.size.x, art.body_rect_px.size.y)
	art.foot_anchor_px = Vector2(config.feet[0], config.feet[1])
	for sequence: Variant in config.sequences:
		if not sequence is Dictionary or not sequence.get("clip") is String or not sequence.get("file") is String or not sequence.get("frames") is Array or sequence.frames.size() != (8 if sequence.clip == "trainer_walk" else 6) or art.clips.has(sequence.clip):
			context.sources.fail("player1_config", path, "Player1 needs unique clips: eight authored walk frames, six for each other sequence")
			return null
		var source: Image = context.sources.read_image(sequence.file)
		if source == null: return null
		if source.get_size() != Vector2i(2172, 724):
			context.sources.fail("player1_layout", sequence.file, "Player1 source dimensions changed; review the authored crops")
			return null
		var frames: Array[Texture2D] = []
		for index in sequence.frames.size():
			var authored: Variant = sequence.frames[index]
			if not authored is Dictionary or not _numbers(authored.get("rect"), 4) or not authored.rect.all(func(value): return value == floor(value)) or not _numbers(authored.get("ground"), 2):
				context.sources.fail("player1_config", path, "Invalid crop or ground anchor", {"clip": sequence.clip, "frame": index})
				return null
			var rect := Rect2i(authored.rect[0], authored.rect[1], authored.rect[2], authored.rect[3])
			var texture: Texture2D = context.sources.extract_frame(sequence.file, rect, sequence.clip, index)
			if texture == null: return null
			var resized := Vector2i(roundi(rect.size.x * config.scale), roundi(rect.size.y * config.scale))
			var source_ground := Vector2(authored.ground[0], authored.ground[1]) - Vector2(rect.position)
			var ground := source_ground * Vector2(resized) / Vector2(rect.size)
			var offset := Vector2i((art.foot_anchor_px - ground).round())
			if resized.x <= 0 or resized.y <= 0 or not Rect2(Vector2.ZERO, rect.size).has_point(source_ground) or not Rect2i(0, 0, 192, 192).encloses(Rect2i(offset, resized)):
				context.sources.fail("player1_normalize", sequence.file, "Frame or ground anchor cannot fit the Player1 canvas", {"clip": sequence.clip, "frame": index})
				return null
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
	return art


func _numbers(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count and value.all(func(number): return (number is int or number is float) and is_finite(float(number)))
