extends Control

const PLAYER_COLORS := [Color("65b8ff"), Color("ffad66")]
const MUTED := Color("9caec4")

var player_mask := 0
var local_player_id := 0


func _ready() -> void:
	resized.connect(queue_redraw)


func set_roster(mask: int, own_player_id: int) -> void:
	player_mask = mask
	local_player_id = own_player_id
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101b2a"))
	for x in range(0, int(size.x), 32):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("1a293c"))
	for y in range(0, int(size.y), 32):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("1a293c"))
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color("354960"), false, 2.0)
	for index in 2:
		var center := Vector2(size.x * (0.28 if index == 0 else 0.72), size.y * 0.47)
		var present := (player_mask & (1 << index)) != 0
		var color: Color = PLAYER_COLORS[index]
		if present:
			draw_circle(center + Vector2(0, 5), 30.0, Color(0, 0, 0, 0.3))
			draw_circle(center, 28.0, color)
			if local_player_id == index + 1:
				draw_arc(center, 35.0, 0.0, TAU, 64, Color.WHITE, 2.0, true)
		else:
			draw_arc(center, 28.0, 0.0, TAU, 64, Color("43556d"), 2.0, true)
		var label := "Player %d" % (index + 1)
		if present and local_player_id == index + 1:
			label += " · YOU"
		if not present:
			label += " · waiting"
		draw_string(ThemeDB.fallback_font, center + Vector2(-130, 65), label, HORIZONTAL_ALIGNMENT_CENTER, 260, 18, color if present else MUTED)
