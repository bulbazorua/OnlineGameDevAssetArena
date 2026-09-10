class_name CharacterAnimator
extends RefCounted

# Presentation of observed movement. Authoritative combat actions are a later layer.
var action := "idle"
var facing := "east"
var elapsed := 0.0


func observe_motion(displacement: Vector2) -> void:
	var moving := displacement.length_squared() > 0.000001
	var next := "walk" if moving else "idle"
	if next != action:
		action = next
		elapsed = 0.0
	if moving:
		var horizontal := "east" if displacement.x > 0.001 else ("west" if displacement.x < -0.001 else "")
		var vertical := "south" if displacement.y > 0.001 else ("north" if displacement.y < -0.001 else "")
		facing = vertical + "_" + horizontal if not vertical.is_empty() and not horizontal.is_empty() else vertical + horizontal


func advance(delta: float) -> void:
	elapsed += delta
