class_name PlayerView
extends "res://characters/character_view.gd"

const WALK_START_POSES := 2
const WALK_START_POSE_SECONDS := 2.0 / 60.0


# Player1's canonical walk starts with passing, lift, then plant. Speed up
# those first two poses once per action; subsequent loops retain the clip FPS.
# Keep animator.elapsed on the action clock so corrections/late joins do not
# restart this acceleration or change the host's movement timing.
func present_art(role: String, facing: String, variant: String, elapsed: float) -> bool:
	var clip_time := elapsed
	if role == "walk" and animation_set != null:
		var binding := animation_set.binding_for(role, facing, variant)
		var clip: Dictionary = animation_set.clips.get(binding.get("clip", ""), {})
		if not clip.is_empty():
			var source_start_seconds := WALK_START_POSES / float(clip.fps)
			var fast_start_seconds := WALK_START_POSES * WALK_START_POSE_SECONDS
			if elapsed < fast_start_seconds:
				clip_time = elapsed * source_start_seconds / fast_start_seconds
			else:
				clip_time = source_start_seconds + elapsed - fast_start_seconds
	return super.present_art(role, facing, variant, clip_time)


func _ready() -> void:
	var name_label := Label.new()
	name_label.text = "P%d Trainer" % player_id
	name_label.position = Vector2(-40, 12)
	name_label.size = Vector2(80, 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", PLAYER_COLORS[player_id])
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 3)
	add_child(name_label)


func present_summon(seconds: float, facing: String) -> void:
	animate = false
	animator.action = "advise"
	animator.facing = facing
	animator.elapsed = seconds
	present_art("advise", facing, "default", seconds)
	_update_animation()
