extends "res://characters/import/character_importer.gd"

const CharacterAnimationSet = preload("res://characters/character_animation_set.gd")


func import_assets(context: Dictionary) -> Variant:
	# This character owns its two-column, five-row source layout.
	var art := CharacterAnimationSet.new()
	art.reference_span_px = 16
	art.body_rect_px = Rect2(8, 8, 16, 16)
	art.foot_anchor_px = Vector2(13, 24) # Deliberately off-center: test mirrored feet.
	var clips := ["rest", "stride", "flinch", "swing", "fallen"]
	for row in clips.size():
		var key: String = clips[row]
		var frames: Array[Texture2D] = []
		for index in 2:
			var frame: Texture2D = context.sources.extract_frame("sheet.png", Rect2i(index * 32, row * 32, 32, 32), key, index)
			if frame == null: return null
			frames.append(frame)
		art.clips[key] = {"frames": frames, "fps": 4.0, "loop": key in ["rest", "stride"]}
	return art
