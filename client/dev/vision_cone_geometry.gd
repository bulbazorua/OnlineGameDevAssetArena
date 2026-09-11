extends RefCounted

const Reader = preload("res://dev/ai/trace_reader.gd")


static func build(sample: Dictionary, fan: Array) -> Dictionary:
	var center := Vector2(sample.pose.position[0], sample.pose.position[1])
	var points := PackedVector2Array()
	for point: Array in fan: points.append(Vector2(point[0], point[1]) - center)
	var overall := deg_to_rad(float(sample.profile.overall_fov_degrees))
	var focus := deg_to_rad(float(sample.profile.focused_fov_degrees))
	var axis := Reader.facing_index(sample.pose.facing) * PI / 4.0 - PI / 2.0
	return {"center": center,
		"focus": _sector(points, axis, overall, -focus / 2.0, focus / 2.0),
		"left": _sector(points, axis, overall, -overall / 2.0, -focus / 2.0),
		"right": _sector(points, axis, overall, focus / 2.0, overall / 2.0)}


static func _sector(points: PackedVector2Array, axis: float, overall: float, lower: float, upper: float) -> PackedVector2Array:
	var polygon := PackedVector2Array([Vector2.ZERO])
	if points.size() < 2: return PackedVector2Array()
	polygon.append(_edge(points, axis, overall, lower))
	for index in points.size():
		var angle := -overall / 2.0 + overall * index / (points.size() - 1)
		if angle > lower and angle < upper: polygon.append(points[index])
	polygon.append(_edge(points, axis, overall, upper))
	var area := 0.0
	for index in polygon.size() - 1: area += polygon[index].cross(polygon[index + 1])
	return polygon if absf(area) > 0.001 else PackedVector2Array()


static func _edge(points: PackedVector2Array, axis: float, overall: float, angle: float) -> Vector2:
	var index := clampf((angle + overall / 2.0) / overall * (points.size() - 1), 0, points.size() - 1)
	var first := points[floori(index)]
	var last := points[mini(floori(index) + 1, points.size() - 1)]
	if is_equal_approx(index, roundf(index)): return points[roundi(index)]
	var direction := Vector2.from_angle(axis + angle)
	var edge := last - first
	var denominator := direction.cross(edge)
	if absf(denominator) < 0.000001: return Vector2.ZERO
	return direction * maxf(0, first.cross(edge) / denominator)
