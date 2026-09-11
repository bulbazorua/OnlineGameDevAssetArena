extends Sprite2D

@export var marker_texture: Texture2D = preload("res://presentation/target_acquired.tres")
@export var marker_scale := 1.5
@export var head_gap := 26.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 20
	visible = false


func present(active: bool, age_seconds: float, body_top: float) -> void:
	texture = marker_texture
	scale = Vector2.ONE * marker_scale
	visible = active and marker_texture != null and age_seconds >= 0 and age_seconds < 1
	position = Vector2(0, body_top - head_gap)
