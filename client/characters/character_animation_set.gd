class_name CharacterAnimationSet
extends Resource

# Normalized public output. Private filenames never reach CharacterView.
# This first export API supports one calibrated body reference per art set.
@export var reference_span_px := 0.0
@export var body_rect_px := Rect2()
@export var foot_anchor_px := Vector2.ZERO
@export var clips: Dictionary = {}
@export var bindings: Array[Dictionary] = []


func binding_for(role: String, facing: String, variant: String) -> Dictionary:
	for binding in bindings:
		if binding.get("role") == role and binding.get("facing") == facing and binding.get("variant") == variant:
			return binding
	return {}


func sample(binding: Dictionary, elapsed: float) -> Dictionary:
	if binding.get("kind") != "clip": return {}
	var clip: Dictionary = clips.get(binding.get("clip", ""), {})
	if clip.is_empty(): return {}
	var frames: Array = clip.frames
	var frame := int(floor(maxf(elapsed, 0) * float(clip.fps)))
	frame = frame % frames.size() if clip.loop else mini(frame, frames.size() - 1)
	return {"texture": frames[frame], "frame": frame, "flip_h": binding.get("flip_h", false)}
