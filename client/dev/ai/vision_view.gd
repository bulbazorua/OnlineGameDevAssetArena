extends Control

# Creature knowledge by default: the delivered eye sample, coarse cues and old
# memory at their sampled pose. Host diagnostics is a separately labelled
# developer view; it can never feed back into a worker.
const Palette = preload("res://dev/ai/trace_palette.gd")
const Reader = preload("res://dev/ai/trace_reader.gd")
const FOCUS := Color("62d9ff")
const PERIPHERAL := Color("ffb454")
const REMEMBERED := Color("b8a6ff")
const SELF := Color("f2f6fb")
const HOST := Color("ff8793")
const FACING_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
var record: Dictionary = {}
var event_count := 0
var host_view := false
var content: RefCounted


func present(value: Dictionary, count: int, host := false) -> void:
	record = value
	event_count = count
	host_view = host
	queue_redraw()


func _node_id(label: String, stage := "") -> int:
	if record.is_empty(): return 0
	for node: Dictionary in record.nodes:
		if str(node.label).begins_with(label) and (stage.is_empty() or node.stage == stage): return int(node.id)
	return 0


func _revealed(label: String, stage := "") -> bool:
	var id := _node_id(label, stage)
	return id > 0 and event_count >= id


static func bearing_angle(facing: int) -> float:
	# Clockwise from north in the Y-down world, expressed as a Godot draw angle.
	return facing * PI / 4.0 - PI / 2.0


static func direction_of(facing: int) -> Vector2:
	var angle := facing * PI / 4.0
	return Vector2(sin(angle), -cos(angle))


class Frame:
	extends RefCounted
	var sample: Dictionary
	var pose_position: Vector2
	var pose_facing: int
	var range_units: float
	var center: Vector2
	var scale_factor: float
	var radius: float
	var axis: float
	var decision_tick: int
	var font: Font

	func to_view(world: Vector2) -> Vector2:
		return center + (world - pose_position) * scale_factor


func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("141e2a")
	box.set_corner_radius_all(8)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	if record.is_empty():
		draw_string(font, Vector2(16, 28), "Select a schema-2 decision to inspect its delivered evidence.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a6b8cb"))
		return
	if int(record.get("schema_version", 1)) < 2:
		draw_string(font, Vector2(16, 28), "Schema-1 wander record: no eyes or memory were recorded. Nothing is invented here.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e8c578"))
		return
	var frame := Frame.new()
	frame.font = font
	frame.sample = record.input.senses.vision
	frame.pose_position = Vector2(frame.sample.pose.position[0], frame.sample.pose.position[1])
	frame.pose_facing = Reader.facing_index(frame.sample.pose.facing)
	frame.range_units = maxf(float(frame.sample.profile.range), 32.0)
	frame.center = Vector2(size.x * 0.5, size.y * 0.5 + 18)
	frame.scale_factor = minf(size.x - 60, size.y - 150) / (frame.range_units * 2.2)
	frame.radius = frame.range_units * frame.scale_factor
	frame.axis = bearing_angle(frame.pose_facing)
	frame.decision_tick = int(record.input.tick)
	_draw_header(frame)
	if host_view and content != null:
		_draw_reference_map(frame)
	_draw_fields(frame)
	var evidence_visible := _revealed("Read own focused sightings")
	var memory_after := _revealed("Age private memory", "State")
	_draw_memory(frame, record.after.memory if memory_after else record.before.memory)
	if evidence_visible and frame.sample.status == "Sampled":
		_draw_evidence(frame)
	if host_view:
		_draw_host_candidates(frame)
	_draw_self_and_decision(frame)
	draw_string(font, Vector2(16, size.y - 38), "Cyan: focused field and delivered sightings · Amber: peripheral field and coarse cues (no exact dots) · Violet dashed: remembered, aged, fixed", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a6b8cb"))
	draw_string(font, Vector2(16, size.y - 20), "Blank space is unknown, not empty. Evidence and geometry share the sample tick; stepping reveals memory only after its update node." if not host_view else "Host view adds the reference map and rejected candidates. This is developer evidence the creature never receives.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HOST if host_view else Color("8ea1b7"))


func _draw_header(frame: Frame) -> void:
	var sample := frame.sample
	var age := (frame.decision_tick - int(sample.sample_tick)) & 0xffffffff
	var title := "HOST DIAGNOSTICS · developer knowledge, not the creature's" if host_view else "CREATURE KNOWLEDGE · only evidence delivered to this brain"
	draw_string(frame.font, Vector2(16, 24), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, HOST if host_view else Color("e4eaf2"))
	var status_text := "decision tick %d · eye sample #%d at tick %d (age %d) · %s%s" % [frame.decision_tick, int(sample.sample_id), int(sample.sample_tick), age, sample.status, " · NEW" if record.input.senses.vision_is_new else " · retained"]
	draw_string(frame.font, Vector2(16, 44), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("a6b8cb"))
	draw_string(frame.font, Vector2(16, 62), "profile: focus %.0f° in %.0f° · range %.0f units · every %d ticks · sampled facing %s" % [float(sample.profile.focused_fov_degrees), float(sample.profile.overall_fov_degrees), float(sample.profile.range), int(sample.profile.sample_interval), FACING_NAMES[frame.pose_facing]], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("8ea1b7"))


# Grid, nominal field outlines and the clipped fan, all at the sampled pose.
func _draw_fields(frame: Frame) -> void:
	var center := frame.center
	var radius := frame.radius
	for x in range(-4, 5):
		var offset := x * radius / 4.0
		draw_line(center + Vector2(offset, -radius), center + Vector2(offset, radius), Color("233041"))
		draw_line(center + Vector2(-radius, offset), center + Vector2(radius, offset), Color("233041"))
	if frame.sample.status != "Sampled":
		draw_arc(center, radius, 0, TAU, 64, Color("4a5a70"), 1.0, true)
		draw_string(frame.font, center + Vector2(-90, -radius - 8), "NO ACTIVE EYE SAMPLE · " + str(frame.sample.status), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e8c578"))
		return
	var half_overall := deg_to_rad(float(frame.sample.profile.overall_fov_degrees)) * 0.5
	var half_focus := deg_to_rad(float(frame.sample.profile.focused_fov_degrees)) * 0.5
	var fan: Array = record.get("sight_fan", [])
	if fan.size() > 2:
		var outer := PackedVector2Array([center])
		var inner := PackedVector2Array([center])
		for point in fan:
			var world := Vector2(point[0], point[1])
			outer.append(frame.to_view(world))
			var relative := absf(angle_difference(frame.axis, (world - frame.pose_position).angle()))
			if (world - frame.pose_position).length() < 0.001 or relative <= half_focus + 0.001: inner.append(frame.to_view(world))
		draw_colored_polygon(outer, Color(PERIPHERAL, 0.10))
		if inner.size() > 2: draw_colored_polygon(inner, Color(FOCUS, 0.14))
	draw_arc(center, radius, frame.axis - half_overall, frame.axis + half_overall, 48, Color(PERIPHERAL, 0.8), 1.5, true)
	draw_arc(center, radius, frame.axis - half_focus, frame.axis + half_focus, 24, FOCUS, 2.0, true)
	for edge in [-half_overall, half_overall]:
		draw_line(center, center + Vector2.from_angle(frame.axis + edge) * radius, Color(PERIPHERAL, 0.8), 1.5, true)
	for edge in [-half_focus, half_focus]:
		draw_line(center, center + Vector2.from_angle(frame.axis + edge) * radius, FOCUS, 2.0, true)


# Remembered evidence: dashed, aged and fixed at its original position or bearing.
func _draw_memory(frame: Frame, memory: Dictionary) -> void:
	for index in int(memory.focused_count):
		var entry: Dictionary = memory.focused[index]
		var world := Vector2(entry.position[0], entry.position[1])
		var point := frame.to_view(world)
		var entry_age := (frame.decision_tick - int(entry.observed_tick)) & 0xffffffff
		var remaining := (int(entry.expires_tick) - frame.decision_tick) & 0xffffffff
		var alpha := clampf(0.35 + 0.65 * float(remaining) / maxf(float(entry_age + remaining), 1.0), 0.35, 1.0)
		_dashed_circle(point, 11, Color(REMEMBERED, alpha))
		draw_string(frame.font, point + Vector2(14, 4), "REMEMBERED %s #%d · seen tick %d · age %d · expires in %d" % [entry.kind, int(entry.subject), int(entry.observed_tick), entry_age, remaining], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(REMEMBERED, alpha))
	for index in int(memory.cue_count):
		var entry: Dictionary = memory.cues[index]
		var absolute := (Reader.facing_index(entry.reference_facing) + int(entry.sector)) % 8
		var entry_age := (frame.decision_tick - int(entry.observed_tick)) & 0xffffffff
		_wedge(frame.center, frame.radius, bearing_angle(absolute), entry.band == "Near", Color(REMEMBERED, 0.9), true)
		var label_point := frame.center + Vector2.from_angle(bearing_angle(absolute)) * frame.radius * (0.35 if entry.band == "Near" else 0.85)
		draw_string(frame.font, label_point + Vector2(6, 18), "REMEMBERED CUE %s · age %d" % [FACING_NAMES[absolute], entry_age], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, REMEMBERED)


# The delivered sample: coarse wedges for cues, solid markers for focused sightings.
func _draw_evidence(frame: Frame) -> void:
	var sample := frame.sample
	for index in int(sample.cue_count):
		var cue: Dictionary = sample.cues[index]
		var absolute := (frame.pose_facing + int(cue.sector)) % 8
		_wedge(frame.center, frame.radius, bearing_angle(absolute), cue.band == "Near", PERIPHERAL, false)
		var label_point := frame.center + Vector2.from_angle(bearing_angle(absolute)) * frame.radius * (0.3 if cue.band == "Near" else 0.8)
		draw_string(frame.font, label_point + Vector2(6, -4), "PERIPHERAL #%d · sector %d (%s) · %s band" % [int(cue.observation_id), int(cue.sector), FACING_NAMES[absolute], cue.band], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, PERIPHERAL)
	for index in int(sample.focused_count):
		var sighting: Dictionary = sample.focused[index]
		var world := Vector2(sighting.position[0], sighting.position[1])
		var point := frame.to_view(world)
		var facing_index := Reader.facing_index(sighting.facing)
		draw_circle(point, 8, FOCUS)
		_arrow(point, point + direction_of(facing_index) * 16, FOCUS, 2)
		draw_string(frame.font, point + Vector2(12, -6), "FOCUS #%d · %s %s · handle %d" % [int(sighting.observation_id), sighting.kind, _appearance_name(int(sighting.appearance_id), sighting.kind), int(sighting.subject)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FOCUS)
		draw_string(frame.font, point + Vector2(12, 8), "at (%.0f, %.0f) · facing %s · %s · tick %d" % [world.x, world.y, FACING_NAMES[facing_index], sighting.locomotion, int(sample.sample_tick)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(FOCUS, 0.85))
	if int(sample.focused_count) + int(sample.cue_count) == 0:
		draw_string(frame.font, frame.center + Vector2(-70, frame.radius + 18), "sampled: nothing in view", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("8ea1b7"))


# Self at the sampled pose, the decision-time pose when it differs, then the
# requested and confirmed facings once their nodes are revealed.
func _draw_self_and_decision(frame: Frame) -> void:
	var center := frame.center
	draw_circle(center, 9, Color("58a6ff") if int(record.owner_id) == 1 else Color("ffac62"))
	_arrow(center, center + direction_of(frame.pose_facing) * 24, SELF, 2)
	var current_position := Vector2(record.input.position[0], record.input.position[1])
	var current_facing := Reader.facing_index(record.input.facing)
	if current_position != frame.pose_position or current_facing != frame.pose_facing:
		var now_point := frame.to_view(current_position)
		draw_arc(now_point, 12, 0, TAU, 24, SELF, 1.5, true)
		_arrow(now_point, now_point + direction_of(current_facing) * 20, Color(SELF, 0.7), 1.5)
		draw_string(frame.font, now_point + Vector2(14, 16), "self at decision tick (facing %s)" % FACING_NAMES[current_facing], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(SELF, 0.8))
	if _revealed("Submit", "Decision"):
		var requested: Dictionary = record.after.last.requested
		if requested.kind == "Face":
			var desired := Reader.facing_index(requested.facing)
			_arrow(center, center + direction_of(desired) * 44, Palette.color("Selected"), 3)
			draw_string(frame.font, center + direction_of(desired) * 52 + Vector2(-20, 4), "requested %s" % FACING_NAMES[desired], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.color("Selected"))
	if _revealed("Host resolved", "Outcome"):
		_arrow(center, center + direction_of(int(record.facing_after)) * 34, Palette.color("Resolved"), 2)
		draw_string(frame.font, Vector2(16, size.y - 58), "host result: %s · confirmed facing %s" % [record.result.kind, FACING_NAMES[int(record.facing_after)]], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.color("Resolved"))


func _appearance_name(appearance_id: int, kind: String) -> String:
	if content == null: return "appearance %d" % appearance_id
	if kind == "Trainer": return "trainer"
	var definition = content.by_id.get(appearance_id)
	return "appearance %d" % appearance_id if definition == null else str(definition.display_name).to_lower()


func _draw_reference_map(frame: Frame) -> void:
	var catalog = content.arena_catalog
	var arena = catalog.arenas_by_id.get(int(record.map_id))
	if arena == null: return
	var tile: float = arena.tile_size
	# Only real cells are drawn, so the work is bounded by the map, not the range.
	var last_cell := Vector2i(arena.width - 1, arena.height - 1)
	var minimum: Vector2i = arena.world_to_cell(frame.pose_position - Vector2.ONE * frame.range_units * 1.1).clamp(Vector2i.ZERO, last_cell)
	var maximum: Vector2i = arena.world_to_cell(frame.pose_position + Vector2.ONE * frame.range_units * 1.1).clamp(Vector2i.ZERO, last_cell)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			var cell := Vector2i(x, y)
			var opaque: bool = catalog.blocks_sight(arena, cell)
			var walkable: bool = not catalog.is_blocked(arena, cell)
			var origin := frame.to_view(Vector2(cell) * tile)
			var rect := Rect2(origin, Vector2.ONE * tile * frame.scale_factor)
			if opaque: draw_rect(rect, Color(HOST, 0.22))
			elif not walkable: draw_rect(rect, Color("3d5c7a", 0.35))
			draw_rect(rect, Color("2b3a4d", 0.6), false, 1.0)
	# Outside the map blocks sight; the map edge is drawn as one red boundary.
	draw_rect(Rect2(frame.to_view(Vector2.ZERO), Vector2(arena.width, arena.height) * tile * frame.scale_factor), HOST, false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(16, 80), "reference map: red cells block sight, red border is the map edge; blue cells block walking only (developer knowledge)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HOST)


func _draw_host_candidates(frame: Frame) -> void:
	var audit: Dictionary = record.get("host_audit", {})
	for candidate: Dictionary in audit.get("candidates", []):
		if candidate.verdict in ["Focused", "Self"]: continue
		var point := frame.to_view(Vector2(candidate.position[0], candidate.position[1]))
		draw_line(point - Vector2(6, 6), point + Vector2(6, 6), HOST, 1.5)
		draw_line(point - Vector2(6, -6), point + Vector2(6, -6), HOST, 1.5)
		draw_string(frame.font, point + Vector2(10, 32), "host: entity %d %s (%.0f units)" % [int(candidate.entity_id), candidate.verdict, float(candidate.distance)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HOST)
	draw_string(frame.font, Vector2(16, 96), "host audit for sample #%d: %d sight tests, %d merged cues%s" % [int(audit.get("sample_id", 0)), int(audit.get("sight_tests", 0)), int(audit.get("merged_cues", 0)), " · origin cell opaque" if audit.get("origin_opaque", false) else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HOST)


func _wedge(center: Vector2, radius: float, angle: float, near: bool, color: Color, dashed: bool) -> void:
	var inner := 0.0 if near else radius * 0.5
	var outer := radius * 0.5 if near else radius
	var points := PackedVector2Array()
	for step in 9:
		points.append(center + Vector2.from_angle(angle - PI / 8.0 + PI / 4.0 * step / 8.0) * outer)
	var back := PackedVector2Array()
	for step in 9:
		back.append(center + Vector2.from_angle(angle + PI / 8.0 - PI / 4.0 * step / 8.0) * inner)
	if not dashed:
		draw_colored_polygon(points + back, Color(color, 0.22))
		draw_polyline(points + back + PackedVector2Array([points[0]]), color, 1.5, true)
	else:
		var outline := points + back + PackedVector2Array([points[0]])
		for index in outline.size() - 1:
			if index % 2 == 0: draw_line(outline[index], outline[index + 1], color, 1.5, true)


func _dashed_circle(center: Vector2, radius: float, color: Color) -> void:
	for step in 12:
		if step % 2 == 0: draw_arc(center, radius, TAU * step / 12.0, TAU * (step + 1) / 12.0, 4, color, 1.5, true)


func _arrow(start: Vector2, end: Vector2, color: Color, width: float) -> void:
	if start.is_equal_approx(end): return
	var delta := (end - start).normalized()
	draw_line(start, end, color, width, true)
	draw_line(end, end - delta.rotated(0.5) * 8, color, width, true)
	draw_line(end, end - delta.rotated(-0.5) * 8, color, width, true)
