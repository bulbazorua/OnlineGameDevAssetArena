class_name ArenaSelectScreen
extends Control

const GameContent = preload("res://content/game_content.gd")
const GameProtocol = preload("res://network/protocol.gd")
const SessionSnapshot = preload("res://session/session_snapshot.gd")
const ArenaCatalog = preload("res://content/arena_catalog.gd")
const ArenaPreview = preload("res://ui/arena_preview.gd")
const CharacterView = preload("res://characters/character_view.gd")

signal arena_requested(map_id: int)
signal characters_requested
signal ready_requested(character_id: int, ready: bool)
signal disconnect_requested

@onready var preview: ArenaPreview = %ArenaPreview
@onready var ready_button: Button = %ReadyButton
@onready var status_label: Label = %StatusLabel
@onready var terrain_label: Label = %TerrainLabel
var cards: Dictionary = {}
var _content: GameContent
var _snapshot: SessionSnapshot
var _player_id := 0
var _shown_map_id := 0
var _players: Array[Label] = []


func _ready() -> void:
	%CharactersButton.pressed.connect(func(): characters_requested.emit())
	%DisconnectButton.pressed.connect(func(): disconnect_requested.emit())
	ready_button.pressed.connect(_ready_requested)
	preview.terrain_inspected.connect(_show_terrain)
	_players = [%PlayerOneLabel, %PlayerTwoLabel]
	for index in 2:
		_players[index].add_theme_color_override("font_color", CharacterView.PLAYER_COLORS[index + 1])


func configure(content: GameContent) -> void:
	_content = content
	for arena in content.arena_catalog.arenas:
		var button := Button.new()
		button.text = arena.display_name
		button.custom_minimum_size = Vector2(0, 42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(_choose_arena.bind(arena.id))
		%ArenaChoices.add_child(button)
		cards[arena.id] = button
	for terrain in content.arena_catalog.terrains:
		var label := Label.new()
		label.text = terrain.display_name
		label.tooltip_text = "%s · %s" % [terrain.key, "walkable" if terrain.walkable else "blocked"]
		label.add_theme_color_override("font_color", {"grass": Color("96ca69"), "ground": Color("dfaa70"), "sand": Color("f8dba9"), "water": Color("68d7e8"), "stone": Color("aab9d4")}.get(terrain.key, Color.WHITE))
		%TerrainLegend.add_child(label)


func display_session(snapshot: SessionSnapshot, player_id: int) -> void:
	_snapshot = snapshot
	_player_id = player_id
	%ActionMessageLabel.text = ""
	if snapshot == null or _content == null or snapshot.map_id == 0:
		_shown_map_id = 0
		return
	var audience := player_id == 0
	%RoleLabel.text = "AUDIENCE · Watching the shared arena" if audience else "PLAYER %d · Either player can choose the arena" % player_id
	%AudienceLabel.text = "%d watching" % snapshot.audience_count
	for index in 2:
		var slot := snapshot.players[index]
		var name_text: String = _content.by_id[slot.character_id].display_name if slot.character_id else "No character"
		_players[index].text = "P%d · %s · %s" % [index + 1, name_text, "READY" if slot.ready else "Choosing"]
	for id: int in cards:
		cards[id].disabled = audience
		cards[id].set_pressed_no_signal(id == snapshot.map_id)
	var arena: ArenaCatalog.ArenaDefinition = _content.arena_catalog.arenas_by_id[snapshot.map_id]
	%ArenaName.text = arena.display_name
	preview.display_map(_content, snapshot.map_id)
	if _shown_map_id != snapshot.map_id:
		terrain_label.text = "Hover or click a tile to inspect its terrain.  ① P1 spawn  ② P2 spawn"
	_shown_map_id = snapshot.map_id
	status_label.text = "Both players ready" if snapshot.both_ready() else "Arena changes clear both Ready flags"
	status_label.add_theme_color_override("font_color", Color("89e4b1") if snapshot.both_ready() else Color("a7b7ce"))
	ready_button.visible = not audience
	if not audience:
		var own := snapshot.players[player_id - 1]
		ready_button.disabled = own.character_id == 0
		ready_button.text = "Unready" if own.ready else "Ready"


func show_rejection(reason: int) -> void:
	%ActionMessageLabel.text = GameProtocol.rejection_text(reason)


func _choose_arena(map_id: int) -> void:
	# Buttons reflect accepted host state, even before the reply arrives.
	if _snapshot != null:
		for id: int in cards:
			cards[id].set_pressed_no_signal(id == _snapshot.map_id)
	if _player_id > 0:
		arena_requested.emit(map_id)


func _ready_requested() -> void:
	if _snapshot == null or _player_id == 0:
		return
	var own := _snapshot.players[_player_id - 1]
	if own.character_id != 0:
		ready_requested.emit(own.character_id, not own.ready)


func _show_terrain(cell: Vector2i, terrain: ArenaCatalog.TerrainDefinition) -> void:
	terrain_label.text = "Tile (%d, %d) · %s · %s" % [cell.x, cell.y, terrain.display_name, "Walkable" if terrain.walkable else "Blocked"]
