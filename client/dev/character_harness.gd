class_name CharacterHarness
extends Control

const Artifact = preload("res://characters/character_artifact.gd")
const Contract = preload("res://content/character_contract.gd")
const CharacterView = preload("res://characters/character_view.gd")
const Stage = preload("res://dev/character_harness_stage.gd")
const FIXTURE_ROOT := "res://dev/fixtures/characters/"
var contract := Contract.new()
var candidate
var report: Dictionary = {}
var role := "idle"
var elapsed := 0.0
var paused := false
var views: Array[CharacterView] = []
var role_buttons: Dictionary = {}
var stage
var viewport: SubViewport
var modules: OptionButton
var facings: OptionButton
var size_input: SpinBox
var missing: CheckButton
var diagnostics: RichTextLabel
var measurements: Label
var phase_label: Label
var module_path := FIXTURE_ROOT + "reference16"
var build_status: Label
var latest_attempt: Dictionary = {}
var generation := ""
var artifact_path := ""
var candidate_mode := false
var preview_source: OptionButton
# Profiles reuse preview controls and normalized rendering, never module parsers.
var contract_path := Contract.PATH
var registry_path := "res://characters/packages/registry.json"
var artifact_family := "characters"
var harness_title := "Character harness · character art"
var harness_description := "Processed art preview. Full combat checks are not implemented."
var unverified_label := "COMBAT NOT VERIFIED"
var missing_roles := ["hurt", "death"]


func _ready() -> void:
	if not OS.is_debug_build():
		get_tree().quit(1)
		return
	var error := contract.load_contract(contract_path)
	if not error.is_empty():
		push_error(error)
		get_tree().quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--module="): module_path = argument.trim_prefix("--module=")
		if argument == "--candidate": candidate_mode = true
	_build_ui()
	load_module()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("101b29")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 10)
	scroll.add_child(layout)
	var title := _label(harness_title, layout)
	title.add_theme_font_size_override("font_size", 26)
	var subtitle := _label(harness_description, layout)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_status = _label("", layout)
	build_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_source = OptionButton.new()
	preview_source.add_item("Last successful generation")
	preview_source.add_item("Latest processed candidate (may be incomplete)")
	preview_source.selected = 1 if candidate_mode else 0
	preview_source.item_selected.connect(func(index): candidate_mode = index == 1; load_module())
	layout.add_child(preview_source)
	var options := HFlowContainer.new()
	layout.add_child(options)
	modules = OptionButton.new()
	var registry = JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	var selected := -1
	if registry is Dictionary and registry.get("schema_version") == 1 and registry.get("modules") is Array:
		for entry: Variant in registry.modules:
			if not entry is Dictionary or not entry.get("label") is String or not entry.get("module") is String: continue
			modules.add_item(entry.label)
			var index := modules.item_count - 1
			modules.set_item_metadata(index, entry.module)
			if entry.module == module_path: selected = index
	if selected < 0:
		modules.add_item("Custom: " + module_path.get_file())
		selected = modules.item_count - 1
		modules.set_item_metadata(selected, module_path)
	modules.selected = selected
	modules.item_selected.connect(func(index):
		module_path = modules.get_item_metadata(index)
		load_module())
	options.add_child(modules)
	_label("Facing", options)
	facings = OptionButton.new()
	for facing: String in contract.data.facings: facings.add_item(facing)
	facings.selected = 2
	facings.item_selected.connect(func(_index): _present())
	options.add_child(facings)
	_label("Gameplay size", options)
	size_input = SpinBox.new()
	size_input.min_value = 0.25
	size_input.max_value = 2
	size_input.step = 0.25
	size_input.value = 1
	size_input.value_changed.connect(func(_value): _configure_views())
	options.add_child(size_input)
	_button("Processing report", options, func():
		if latest_attempt.has("report"): OS.shell_open(latest_attempt.report))
	_button("Processed files", options, func():
		if not artifact_path.is_empty(): OS.shell_open(artifact_path.get_base_dir()))
	var actions := HFlowContainer.new()
	layout.add_child(actions)
	for key: String in contract.data.roles:
		var button := _button(key.capitalize(), actions, select_role.bind(key))
		role_buttons[key] = button
	_button("Reset", actions, func(): select_role("idle"))
	_button("Replay", actions, func(): select_role(role))
	var pause_button := _button("Pause", actions, func(): paused = not paused)
	pause_button.toggle_mode = true
	_button("Step 1/60s", actions, func():
		paused = true
		pause_button.button_pressed = true
		elapsed += 1.0 / 60.0
		_present())
	var toggles := HFlowContainer.new()
	layout.add_child(toggles)
	missing = CheckButton.new()
	missing.text = "Demonstrate missing " + "/".join(missing_roles)
	missing.toggled.connect(func(_enabled): load_module())
	toggles.add_child(missing)
	var geometry := CheckButton.new()
	geometry.text = "Body / feet overlays"
	geometry.button_pressed = true
	geometry.toggled.connect(func(enabled): stage.show_geometry = enabled; stage.refresh())
	toggles.add_child(geometry)
	_button("Save diagnostics", toggles, save_report)
	measurements = _label("", layout)
	measurements.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var container := SubViewportContainer.new()
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.custom_minimum_size = Vector2(0, 290)
	container.stretch = true
	layout.add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(860, 290)
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	stage = Stage.new()
	viewport.add_child(stage)
	var camera := Camera2D.new()
	camera.position = Vector2(120, 22)
	camera.zoom = Vector2(2, 2)
	viewport.add_child(camera)
	for index in 2:
		var view := CharacterView.new()
		view.position = Vector2(62 + index * 112, 54)
		views.append(view)
		stage.add_child(view)
	stage.views.assign(views)
	phase_label = _label("", layout)
	phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diagnostics = RichTextLabel.new()
	diagnostics.custom_minimum_size = Vector2(0, 120)
	diagnostics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diagnostics.add_theme_font_size_override("normal_font_size", 14)
	layout.add_child(diagnostics)


func load_module() -> void:
	var result := Artifact.read_latest_candidate(module_path.get_file(), artifact_family) if candidate_mode else Artifact.read_current(module_path.get_file(), artifact_family)
	latest_attempt = result.get("latest_attempt") if result.get("latest_attempt") is Dictionary else {}
	generation = result.get("generation", "")
	artifact_path = result.get("artifact_path", "")
	build_status.text = "%s: %s | Latest processing: %s" % ["STAGED CANDIDATE" if candidate_mode else "Processed generation", generation.left(10) if not generation.is_empty() else "none", str(latest_attempt.get("status", "not run")).to_upper()]
	if latest_attempt.get("status") == "fail":
		build_status.text += "\n%s: %s." % [latest_attempt.get("stage", ""), latest_attempt.get("error", "")]
		if not candidate_mode: build_status.text += " Showing last successful output if available."
	if not result.error.is_empty():
		candidate = null
		report = contract.inspect(null)
		report["error"] = result.error
		report["module_path"] = module_path
		for view in views: view.hide()
		diagnostics.text = "FAIL: " + result.error
		measurements.text = "Module unavailable: " + module_path
		return
	candidate = result.candidate
	if candidate != null and candidate.art != null and missing.button_pressed:
		candidate.art.bindings.assign(candidate.art.bindings.filter(func(binding): return binding.get("role") not in missing_roles))
	report = contract.inspect(candidate)
	elapsed = 0
	_configure_views()
	var lines := PackedStringArray(["%s@%s  |  %s  |  Export API %s" % [contract.data.id, contract.data.version, unverified_label, contract.data.export_api_version]])
	for status in ["fail", "pass", "not_run"]:
		for check: Dictionary in report.checks:
			if check.status == status: lines.append("%s · %s — %s" % [check.status.to_upper(), check.id, check.message])
	diagnostics.text = "\n".join(lines)


func _configure_views() -> void:
	if candidate == null or report.get("renderable_roles", []).is_empty():
		for view in views: view.hide()
		measurements.text = "No validated art available to preview."
		return
	for index in views.size():
		views[index].show()
		views[index].configure_art(candidate.art, index + 1, float(size_input.value) * (1.5 if index == 1 else 1.0), candidate.gameplay_definition.footprint_radius_units)
	measurements.text = "%s · Body reference %.0fpx · A: %.0f world units · B: %.0f world units · Grid: 32" % [candidate.module_key, candidate.art.reference_span_px, size_input.value * 32, size_input.value * 48]
	_present()


func select_role(value: String) -> void:
	role = value
	elapsed = 0
	_present()


func _process(delta: float) -> void:
	if not paused: elapsed += delta
	_present()


func _present() -> void:
	if not is_instance_valid(phase_label): return
	var available: bool = candidate != null and role in report.get("renderable_roles", [])
	if available:
		views[0].show()
		views[0].present_art(role, facings.get_item_text(facings.selected), contract.data.roles[role].variant, elapsed)
	else:
		views[0].hide()
	# B is independent of A's role, including when A's requested role is missing.
	views[1].visible = candidate != null and "idle" in report.get("renderable_roles", [])
	if views[1].visible:
		views[1].present_art("idle", "east", "default", 0.35)
	phase_label.text = "A: %s · %.2fs · %s | B: independent idle · Yellow: body · Cyan: feet" % [role, elapsed, "preview" if available else "MISSING / INVALID"]
	stage.refresh()


func save_report() -> void:
	var directory := ProjectSettings.globalize_path("res://../build/verification/" + artifact_family + "/harness")
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		print("[harness] Preview diagnostics saved: ", directory, "/report.json (not admission evidence)")


func _label(text: String, parent: Node) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _button(text: String, parent: Node, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
