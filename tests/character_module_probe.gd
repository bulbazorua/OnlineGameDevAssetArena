extends SceneTree

const Builder = preload("res://characters/import/character_package_builder.gd")


func _initialize() -> void:
	var key := OS.get_cmdline_user_args()[0]
	var path := "res://dev/fixtures/characters/" + key
	var first := Builder.inspect_module(path)
	var second := Builder.inspect_module(path)
	if not first.error.is_empty() or not second.error.is_empty() or not first.report.art_pass or first.report.selection_eligible:
		push_error("Isolated module did not produce a valid preview.")
		quit(1)
		return
	if first.candidate.art.bindings != second.candidate.art.bindings:
		quit(1)
		return
	for clip: String in first.candidate.art.clips:
		var a: Array = first.candidate.art.clips[clip].frames
		var b: Array = second.candidate.art.clips[clip].frames
		for index in a.size():
			if a[index].get_image().get_data() != b[index].get_image().get_data():
				push_error("Importer output was nondeterministic.")
				quit(1)
				return
	first.candidate.art.bindings.clear()
	if second.candidate.art.bindings.is_empty():
		push_error("Separate exports shared mutable bindings.")
		quit(1)
		return
	print("PASS: ", key, " builds alone with deterministic art and independent exports.")
	quit(0)
