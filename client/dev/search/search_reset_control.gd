extends VBoxContainer

const Protocol = preload("res://network/protocol.gd")
const Snapshot = preload("res://session/session_snapshot.gd")
var button := Button.new()
var status := Label.new()
var _network: Node
var _pending := false
var _round := 0
var _requested_ms := 0


func configure(network: Node) -> void:
	_network = network
	button.text = "Reset search [F7]"
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Place both creatures beyond vision range and clear their memories. Trainers move nearby. All six windows stay open."
	button.pressed.connect(request_reset)
	add_child(button)
	status.text = "Spread out and start with fresh memories."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 12)
	add_child(status)
	_network.command_reply_rejected.connect(_rejected)
	_process(0)


func request_reset() -> void:
	_process(0)
	if button.disabled: return
	_pending = true
	_round = _network.session.round_id
	_requested_ms = Time.get_ticks_msec()
	status.text = "Waiting for the host to reset the search…"
	button.disabled = true
	_network.request_search_reset()


func _process(_delta: float) -> void:
	if _network == null: return
	var state = _network.session
	if _pending:
		if state == null:
			_pending = false
			status.text = "Disconnected before reset was confirmed."
		elif state.round_id != _round:
			_pending = false
			status.text = "Search reset · round %d · fresh memories." % state.round_id
		elif Time.get_ticks_msec() - _requested_ms > 5000:
			_pending = false
			status.text = "No reset confirmation. Try again."
	button.disabled = _pending or not OS.is_debug_build() or "--dev" not in OS.get_cmdline_user_args() or _network.player_id not in [1, 2] or state == null or state.phase != Snapshot.Phase.IN_ARENA or state.summon_elapsed_ticks < Protocol.SUMMON_DURATION_TICKS


func _rejected(kind: int, reason: int) -> void:
	if kind != Protocol.MessageKind.DEV_RESET_SEARCH or not _pending: return
	_pending = false
	status.text = Protocol.rejection_text(reason)
