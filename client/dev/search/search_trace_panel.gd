extends VBoxContainer

const Preferences = preload("res://dev/search/search_preferences.gd")
const Details = preload("res://dev/search/search_details.gd")
var preferences := Preferences.new()
var toggle: CheckBox
var details: RichTextLabel
var record: Dictionary = {}
var _elapsed := 0.0


func configure(owner: int) -> void:
	preferences.configure(owner)
	toggle = CheckBox.new()
	toggle.text = "Search diagnostics · remember this setting"
	toggle.button_pressed = preferences.enabled
	toggle.toggled.connect(func(value: bool): preferences.save(value); _render())
	add_child(toggle)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_font_size_override("normal_font_size", 13)
	add_child(details)
	_render()


func present(value: Dictionary) -> void:
	record = value
	_render()


func _render() -> void:
	if details == null: return
	toggle.set_pressed_no_signal(preferences.enabled)
	if not preferences.enabled:
		details.text = "Search diagnostics are off. Enable here or press F6 in this player's arena window."
	elif record.is_empty() or record.after.get("controller") != "Search":
		details.text = "No search controller in this recorded decision."
	else:
		var scroll := details.get_v_scroll_bar().value
		details.text = "[b]RECORDED DECISION[/b] · frozen with the selected trace\n" + Details.text(record.after.search, int(record.input.tick), record.after.intent, record.result)
		details.get_v_scroll_bar().set_deferred("value", scroll)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5: return
	_elapsed = 0
	if preferences.reload(): _render()
