class_name SummonEffect
extends Node2D

const Protocol = preload("res://network/protocol.gd")
const COLORS := [Color.WHITE, Color("58a6ff"), Color("ffac62")]
var origin := Vector2.ZERO
var effect_owner :=  1
var tick := 0.0


func present(from: Vector2, target: Vector2, owner_id: int, elapsed_ticks: float) -> void:
	position = target
	origin = from - target
	effect_owner = owner_id
	tick = elapsed_ticks
	visible = tick < Protocol.SUMMON_DURATION_TICKS
	queue_redraw()


func _draw() -> void:
	var color: Color = COLORS[effect_owner]
	if tick < Protocol.SUMMON_REVEAL_TICKS:
		var travel := clampf((tick - 6.0) / 30.0, 0.0, 1.0)
		var orb := (origin + Vector2(0, -20)).lerp(Vector2.ZERO, travel)
		orb.y -= sin(travel * PI) * 28.0
		draw_circle(orb, 5, color)
		draw_circle(orb, 2, Color.WHITE)
		draw_arc(Vector2.ZERO, 10 + 5 * travel, 0, TAU, 48, Color(color, 0.6), 1.5, true)
	else:
		var progress := clampf((tick - Protocol.SUMMON_REVEAL_TICKS) / float(Protocol.SUMMON_DURATION_TICKS - Protocol.SUMMON_REVEAL_TICKS), 0, 1)
		var fade := 1.0 - progress
		draw_set_transform(Vector2.ZERO, 0, Vector2(1, 0.55))
		draw_arc(Vector2.ZERO, 12 + 28 * progress, 0, TAU, 64, Color(color, fade), 2, true)
		draw_set_transform(Vector2.ZERO)
		for index in 8:
			var angle := TAU * index / 8.0 + progress
			var particle := Vector2(cos(angle), sin(angle) * 0.6) * (12 + 24 * progress)
			particle.y -= progress * 18
			draw_circle(particle, 2.0 * fade + 0.5, Color(color.lightened(0.5), fade))
		if progress < 0.3:
			draw_line(Vector2.ZERO, Vector2(0, -42), Color(color.lightened(0.7), (1 - progress / 0.3) * 0.8), 7, true)
