class_name CharacterView
extends Node2D

const CharacterVisual = preload("res://characters/character_visual.gd")
const CharacterAnimationSet = preload("res://characters/character_animation_set.gd")
const AssetScale = preload("res://presentation/asset_scale.gd")
const Animator = preload("res://characters/character_animator.gd")
const PLAYER_COLORS := [Color("e0e7f2"), Color("58a6ff"), Color("ffac62")]
var visual: CharacterVisual
var player_id := 0
var radius := 24.0
var is_local := false
var animation_set: CharacterAnimationSet
var body_sprite: Sprite2D
var preview_size := 1.0
var presented_frame := -1
var character_id := -1
var animator := Animator.new()
var animate := false
var action_label: Label


func configure(character_visual: CharacterVisual, owner_id := 0, display_radius := 24.0) -> void:
	animate = false
	animation_set = null
	if body_sprite != null: body_sprite.hide()
	visual = character_visual
	player_id = owner_id
	radius = display_radius
	queue_redraw()


# Validated art consumer shared with the isolated harness. No importer or FSM.
func configure_art(art: CharacterAnimationSet, owner_id: int, gameplay_size: float, footprint_units: float) -> void:
	animate = false
	animation_set = art
	visual = null
	player_id = owner_id
	preview_size = gameplay_size
	radius = footprint_units * gameplay_size * AssetScale.WORLD_UNITS_PER_GAMEPLAY_UNIT
	if body_sprite == null:
		body_sprite = Sprite2D.new()
		body_sprite.centered = false
		body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(body_sprite)
	body_sprite.hide()
	presented_frame = -1
	queue_redraw()


func present_art(role: String, facing: String, variant: String, elapsed: float) -> bool:
	if animation_set == null: return false
	var binding := animation_set.binding_for(role, facing, variant)
	var sample := animation_set.sample(binding, elapsed)
	if sample.is_empty():
		body_sprite.hide()
		presented_frame = -1
		return false
	body_sprite.texture = sample.texture
	body_sprite.offset = -animation_set.foot_anchor_px
	var factor := AssetScale.factor(animation_set.reference_span_px, preview_size)
	body_sprite.scale = Vector2(-factor if sample.flip_h else factor, factor)
	presented_frame = sample.frame
	body_sprite.show()
	return true


func start_animation() -> void:
	animator = Animator.new()
	animate = true
	_update_animation()


func observe_motion(displacement: Vector2) -> void:
	animator.observe_motion(displacement)
	_update_animation()


func set_debug_actions(enabled: bool) -> void:
	if action_label == null:
		action_label = Label.new()
		action_label.size = Vector2(100, 18)
		action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		action_label.add_theme_font_size_override("font_size", 10)
		action_label.add_theme_constant_override("outline_size", 3)
		action_label.add_theme_color_override("font_outline_color", Color.BLACK)
		action_label.z_index = 10
		add_child(action_label)
	action_label.visible = enabled and OS.is_debug_build()
	_update_animation()


func _process(delta: float) -> void:
	if not animate or not is_visible_in_tree(): return
	animator.advance(delta)
	_update_animation()


func _update_animation() -> void:
	if animate and animation_set != null:
		present_art(animator.action, animator.facing, "default", animator.elapsed)
	if action_label != null:
		action_label.text = animator.action
		var top := body_bounds().position.y if animation_set != null else -radius
		action_label.position = Vector2(-50, top - 28)


func body_bounds() -> Rect2:
	if animation_set == null or body_sprite == null: return Rect2()
	return body_sprite.transform * Rect2(animation_set.body_rect_px.position - animation_set.foot_anchor_px, animation_set.body_rect_px.size)


func _draw() -> void:
	if animation_set != null:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, PLAYER_COLORS[player_id], 1.0, true)
		return
	if visual == null:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color("52617a"), 2.0, true)
		return
	var color: Color = PLAYER_COLORS[player_id] * visual.tint
	var points := PackedVector2Array()
	match visual.placeholder_kind:
		CharacterVisual.PlaceholderKind.CIRCLE:
			draw_circle(Vector2.ZERO, radius, color, true, -1.0, true)
		CharacterVisual.PlaceholderKind.SQUARE:
			points = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
		CharacterVisual.PlaceholderKind.TRIANGLE:
			points = PackedVector2Array([Vector2(0, -1.2), Vector2(1.1, 0.9), Vector2(-1.1, 0.9)])
		CharacterVisual.PlaceholderKind.DIAMOND:
			points = PackedVector2Array([Vector2(0, -1.3), Vector2(1, 0), Vector2(0, 1.3), Vector2(-1, 0)])
	if not points.is_empty():
		for index in points.size():
			points[index] *= radius * 0.85
		draw_colored_polygon(points, color)
		points.append(points[0])
		draw_polyline(points, color.lightened(0.25), 1.0, true)

	if is_local:
		draw_arc(Vector2.ZERO, radius + 4, 0, TAU, 48, Color(1, 1, 1, 0.8), 1.2, true)


# Runtime locomotion samples the host or predicted action clock. Position
# corrections do not invent animation transitions; harness playback stays separate.
func present_locomotion(role: String, facing: String, seconds: float) -> void:
	animate = false
	animator.action = role
	animator.facing = facing
	animator.elapsed = seconds
	if animation_set != null: present_art(role, facing, "default", seconds)
	_update_animation()
