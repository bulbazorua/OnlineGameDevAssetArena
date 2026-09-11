extends HBoxContainer

const Protocol = preload("res://network/protocol.gd")
const Snapshot = preload("res://session/session_snapshot.gd")
var meter := ProgressBar.new()
var status := Label.new()
var _fill := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	meter.custom_minimum_size = Vector2(180, 22)
	meter.max_value = Protocol.TRAINER_ENERGY_MAX
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("20332c")
	track.border_color = Color("60796c")
	track.set_border_width_all(1)
	_fill.bg_color = Color("7de2b2")
	meter.add_theme_stylebox_override("background", track)
	meter.add_theme_stylebox_override("fill", _fill)
	add_child(meter)
	status.add_theme_font_size_override("font_size", 14)
	add_child(status)
	hide()


func present(trainer: Snapshot.TrainerState, owner: int, summoning: bool) -> void:
	visible = trainer != null and owner > 0
	if not visible: return
	meter.value = trainer.energy
	var percent := roundi(100.0 * trainer.energy / Protocol.TRAINER_ENERGY_MAX)
	var hint := "Hold Space + move to run"
	if summoning: hint = "Ready after summoning"
	elif trainer.run_exhausted:
		hint = "Exhausted · recovering to 20%" if trainer.energy < Protocol.TRAINER_RECOVERY_THRESHOLD else "Release Space to run again"
	elif trainer.locomotion == 2: hint = "Running"
	elif trainer.energy_recovery_ticks > 0: hint = "Catching breath"
	elif trainer.energy < Protocol.TRAINER_ENERGY_MAX: hint = "Recovering"
	status.text = "Energy %d%% · %s" % [percent, hint]
	_fill.bg_color = Color("ffb454") if trainer.run_exhausted else Color("7de2b2")
