extends Control

signal node_selected(node: Dictionary)
const Palette = preload("res://dev/ai/trace_palette.gd")
const CARD := Vector2(218, 106)
const GAP := Vector2(22, 52)
var nodes: Array = []
var event_count := 0
var selected_id := 0
var positions: Dictionary = {}
var chosen_path: Dictionary = {}
var zoom := 0.8
var offset := Vector2.ZERO
var bounds := Vector2.ONE
var _identity := ""
var _children: Dictionary = {}
var _widths: Dictionary = {}
var _lines: Dictionary = {}
var _boxes: Dictionary = {}
var _dragging := false

func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)
	for status: String in Palette.COLORS:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("18283b")
		box.border_color = Palette.color(status)
		box.set_border_width_all(2)
		box.set_corner_radius_all(8)
		_boxes[status] = box

func present(record: Dictionary, count: int) -> void:
	var identity := "%s/%s/%s" % [record.run_id, record.owner_id, record.sequence]
	nodes = record.nodes
	event_count = count
	selected_id = count
	if identity != _identity:
		_identity = identity
		_layout()
		center_root()
	chosen_path.clear()
	for index in event_count:
		if nodes[index].status not in ["Selected", "Resolved"]: continue
		var id := int(nodes[index].id)
		while id > 0:
			chosen_path[id] = true
			id = int(nodes[id - 1].parent)
	queue_redraw()

func _layout() -> void:
	positions.clear()
	_children.clear()
	_widths.clear()
	_lines.clear()
	for node: Dictionary in nodes:
		_children[int(node.id)] = []
		if int(node.parent) > 0: _children[int(node.parent)].append(int(node.id))
		var lines: Array[String] = []
		var line := ""
		for word in str(node.label).split(" "):
			if line.length() + word.length() > 29 and not line.is_empty():
				lines.append(line)
				line = ""
			line += (" " if not line.is_empty() else "") + word
		if not line.is_empty(): lines.append(line)
		if lines.size() > 3: lines = [lines[0], lines[1], lines[2].left(25) + "…"]
		_lines[int(node.id)] = lines
	for i in range(nodes.size() - 1, -1, -1):
		var width := 0.0
		for child: int in _children[i + 1]: width += float(_widths[child]) + GAP.x
		_widths[i + 1] = maxf(CARD.x, width - GAP.x)
	bounds = Vector2(float(_widths.get(1, CARD.x)), CARD.y)
	if not nodes.is_empty(): _place(1, 0, 0)

func _place(id: int, left: float, depth: int) -> void:
	positions[id] = Vector2(left + (float(_widths[id]) - CARD.x) / 2.0, depth * (CARD.y + GAP.y))
	bounds.y = maxf(bounds.y, positions[id].y + CARD.y)
	var x := left
	for child: int in _children[id]:
		_place(child, x, depth + 1)
		x += float(_widths[child]) + GAP.x

func center_root() -> void:
	zoom = clampf((size.x - 40) / bounds.x, 0.65, 1.0)
	offset = Vector2((size.x - bounds.x * zoom) / 2.0, 24)
	queue_redraw()

func fit_all() -> void:
	zoom = clampf(minf((size.x - 36) / bounds.x, (size.y - 36) / bounds.y), 0.2, 1.5)
	offset = (size - bounds * zoom) / 2.0
	queue_redraw()

func zoom_by(factor: float, point := Vector2(-1, -1)) -> void:
	if point.x < 0: point = size / 2.0
	var local := (point - offset) / zoom
	zoom = clampf(zoom * factor, 0.2, 2.0)
	offset = point - local * zoom
	queue_redraw()

func focus_node(id: int) -> void:
	if not positions.has(id): return
	selected_id = id
	offset = size / 2.0 - (positions[id] + CARD / 2.0) * zoom
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0e1928"))
	if event_count == 0:
		draw_string(ThemeDB.fallback_font, Vector2(22, 36), "Press Event ▶ to reveal the recorded input.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("aabdd3"))
		return
	draw_set_transform(offset, 0, Vector2.ONE * zoom)
	for index in event_count:
		var node: Dictionary = nodes[index]
		var id := int(node.id)
		var parent := int(node.parent)
		if parent == 0: continue
		var a: Vector2 = positions[parent] + Vector2(CARD.x / 2.0, CARD.y)
		var b: Vector2 = positions[id] + Vector2(CARD.x / 2.0, 0)
		var color := Palette.color("Selected") if chosen_path.has(id) else Color("486079")
		var middle := (a.y + b.y) / 2.0
		draw_polyline(PackedVector2Array([a, Vector2(a.x, middle), Vector2(b.x, middle), b]), color, 3 if chosen_path.has(id) else 1.5, true)
		draw_colored_polygon(PackedVector2Array([b, b + Vector2(-5, -8), b + Vector2(5, -8)]), color)
	var font := ThemeDB.fallback_font
	for index in event_count:
		var node: Dictionary = nodes[index]
		var id := int(node.id)
		var p: Vector2 = positions[id]
		var color := Palette.color(node.status)
		draw_style_box(_boxes[node.status], Rect2(p, CARD))
		if id == selected_id: draw_rect(Rect2(p - Vector2(3, 3), CARD + Vector2(6, 6)), Color("edf5ff"), false, 2)
		draw_string(font, p + Vector2(12, 18), "%02d  ·  %s" % [id, str(node.stage).to_upper()], HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 24, 11, Color("9ab2cf"))
		var y := 37.0
		for line: String in _lines[id]:
			draw_string(font, p + Vector2(12, y), line, HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 24, 13, Color("edf3fb"))
			y += 15
		draw_string(font, p + Vector2(12, 94), Palette.LABELS[node.status], HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 24, 11, color)
	draw_set_transform(Vector2.ZERO)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			if event.ctrl_pressed: zoom_by(1.15 if direction > 0 else 1.0 / 1.15, event.position)
			else: offset.y += direction * 64; queue_redraw()
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local: Vector2 = (event.position - offset) / zoom
			for index in event_count:
				if Rect2(positions[index + 1], CARD).has_point(local):
					selected_id = index + 1
					node_selected.emit(nodes[index])
					queue_redraw()
					accept_event()
					return
	elif event is InputEventMouseMotion and _dragging:
		offset += event.relative
		queue_redraw()
		accept_event()
