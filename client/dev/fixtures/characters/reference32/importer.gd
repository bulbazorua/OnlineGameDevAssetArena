extends "res://characters/import/character_importer.gd"

const CharacterAnimationSet = preload("res://characters/character_animation_set.gd")


func import_assets(context: Dictionary) -> Variant:
	# This character owns its single horizontal ten-frame source strip.
	var art := CharacterAnimationSet.new()
	art.reference_span_px = 32
	art.body_rect_px = Rect2(16, 16, 32, 32)
	art.foot_anchor_px = Vector2(26, 48)
	for clip_index in 5:
		var frames: Array[Texture2D] = []
		for index in 2:
			var frame: Texture2D = context.sources.extract_frame("sheet.png", Rect2i((clip_index * 2 + index) * 64, 0, 64, 64), "sheet_%d" % clip_index, index)
			if frame == null: return null
			frames.append(frame)
		art.clips["sheet_%d" % clip_index] = {"frames": frames, "fps": 4.0, "loop": clip_index < 2}
	return art
