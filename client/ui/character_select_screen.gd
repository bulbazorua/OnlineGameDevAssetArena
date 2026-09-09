class_name CharacterSelectScreen
extends Control

const GameContent = preload("res://content/game_content.gd")
const GameProtocol = preload("res://network/protocol.gd")
const SessionSnapshot = preload("res://session/session_snapshot.gd")
const CharacterView = preload("res://characters/character_view.gd")
const CHARACTER_VIEW_SCENE = preload("res://characters/character_view.tscn")

signal arena_view_requested
signal character_requested(character_id: int)
signal ready_requested(character_id: int, ready: bool)
signal disconnect_requested

@onready var ready_button: Button = %ReadyButton
@onready var phase_label: Label = %PhaseStatusLabel
@onready var message_label: Label = %ActionMessageLabel
@onready var audience_label: Label = %AudienceLabel
@onready var role_label: Label = %RoleLabel
var cards: Dictionary = {}
var _badges: Dictionary = {}
var _previews: Array[CharacterView] = []
var _names: Array[Label] = []
var _ready_labels: Array[Label] = []
var _content: GameContent
var _snapshot: SessionSnapshot
var _local_player_id := 0


func _ready() -> void:
	ready_button.pressed.connect(_on_ready_pressed)
	%ArenaButton.pressed.connect(func(): arena_view_requested.emit())
	%DisconnectButton.pressed.connect(func(): disconnect_requested.emit())


func configure(content: GameContent) -> void:
	_content = content
	for index in 2:
		var panel: Control = %PlayerOnePreview if index == 0 else %PlayerTwoPreview
		var preview: CharacterView = CHARACTER_VIEW_SCENE.instantiate()
		preview.position = Vector2(52, 66)
		panel.add_child(preview)
		_previews.append(preview)
		var title := _label("PLAYER %d" % (index + 1), Vector2(104, 18), 15)
		title.add_theme_color_override("font_color", CharacterView.PLAYER_COLORS[index + 1])
		panel.add_child(title)
		var name_label := _label("Choose a character", Vector2(104, 45), 20)
		panel.add_child(name_label)
		_names.append(name_label)
		var ready_label := _label("Choosing…", Vector2(104, 81), 16)
		panel.add_child(ready_label)
		_ready_labels.append(ready_label)
	for definition in content.characters:
		var card := Button.new()
		card.name = "Character%d" % definition.id
		card.custom_minimum_size = Vector2(0, 108)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.tooltip_text = "Select %s" % definition.display_name
		card.pressed.connect(_on_character_pressed.bind(definition.id))
		%CharacterGrid.add_child(card)
		cards[definition.id] = card
		var view: CharacterView = CHARACTER_VIEW_SCENE.instantiate()
		view.position = Vector2(43, 53)
		view.configure(content.visuals[definition.id])
		card.add_child(view)
		card.add_child(_label(definition.display_name, Vector2(84, 20), 23))
		var badge_row := HBoxContainer.new()
		badge_row.position = Vector2(84, 63)
		badge_row.add_theme_constant_override("separation", 16)
		badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(badge_row)
		var badges: Array[Label] = []
		for index in 2:
			var badge := _label("P%d selected" % (index + 1), Vector2.ZERO, 14)
			badge.add_theme_color_override("font_color", CharacterView.PLAYER_COLORS[index + 1])
			badge_row.add_child(badge)
			badge.visible = false
			badges.append(badge)
		_badges[definition.id] = badges


func display_session(snapshot: SessionSnapshot, local_player_id: int) -> void:
	_snapshot = snapshot
	_local_player_id = local_player_id
	message_label.text = ""
	if snapshot == null or _content == null:
		return
	if snapshot.map_id != 0:
		%ArenaButton.text = "Arena: %s  →" % _content.arena_catalog.arenas_by_id[snapshot.map_id].display_name
	var audience := local_player_id == 0
	role_label.text = "AUDIENCE · Watching both players" if audience else "YOU ARE PLAYER %d" % local_player_id
	role_label.add_theme_color_override("font_color", CharacterView.PLAYER_COLORS[local_player_id])
	audience_label.text = "%d watching" % snapshot.audience_count
	for index in 2:
		var slot := snapshot.players[index]
		_previews[index].configure(_content.visuals.get(slot.character_id), index + 1, 31.0)
		_names[index].text = _content.by_id[slot.character_id].display_name if slot.character_id != 0 else "No selection"
		_ready_labels[index].text = "READY" if slot.ready else "Choosing…"
		_ready_labels[index].add_theme_color_override("font_color", Color("89e4b1") if slot.ready else Color("a7b7ce"))
	for id: int in cards:
		cards[id].disabled = audience
		for index in 2:
			_badges[id][index].visible = snapshot.players[index].character_id == id
	ready_button.visible = not audience
	if not audience:
		var own := snapshot.players[local_player_id - 1]
		ready_button.disabled = own.character_id == 0
		ready_button.text = "Unready" if own.ready else "Ready"
	if snapshot.both_ready():
		phase_label.text = "Both players ready"
		phase_label.add_theme_color_override("font_color", Color("89e4b1"))
	elif audience:
		phase_label.text = "Players are choosing their characters"
		phase_label.add_theme_color_override("font_color", Color("dce5f2"))
	else:
		phase_label.text = "Choose a character, then press Ready"
		phase_label.add_theme_color_override("font_color", Color("dce5f2"))


func show_rejection(reason: int) -> void:
	message_label.text = GameProtocol.rejection_text(reason)


func _on_character_pressed(character_id: int) -> void:
	if _local_player_id == 0:
		return
	message_label.text = ""
	character_requested.emit(character_id)


func _on_ready_pressed() -> void:
	if _snapshot == null or _local_player_id == 0:
		return
	var own := _snapshot.players[_local_player_id - 1]
	if own.character_id != 0:
		message_label.text = ""
		ready_requested.emit(own.character_id, not own.ready)


static func _label(text_value: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label
