extends SceneTree

const Artifact = preload("res://characters/character_artifact.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var result := Artifact.read(args[0], args[1])
	if args.size() > 2 and args[2] == "expect_failure":
		if result.error.is_empty():
			push_error("Corrupt processed artifact was accepted")
			quit(1)
			return
		print("PASS: corrupted processed artifact rejected: ", result.error)
		quit()
		return
	var incomplete := args.size() > 2 and args[2] == "expect_incomplete"
	if not result.error.is_empty() or result.report.selection_eligible or (not incomplete and not result.report.art_pass):
		push_error("Processed-only read failed: " + str(result))
		quit(1)
		return
	if incomplete and (result.report.art_pass or result.report.renderable_roles != ["idle", "walk", "attack"]):
		push_error("Incomplete character lost its exact missing-role diagnostics")
		quit(1)
		return
	for argument: String in args:
		if not argument.begins_with("--source-root="): continue
		var source_root := argument.trim_prefix("--source-root=")
		for clip: String in result.document.clips:
			var frames: Array = result.document.clips[clip].frames
			for index in frames.size():
				var origin: Dictionary = frames[index].origin
				var source := Image.load_from_file(source_root.path_join(origin.source))
				var rectangle: Array = origin.rect
				var expected := source.get_region(Rect2i(rectangle[0], rectangle[1], rectangle[2], rectangle[3]))
				expected.convert(Image.FORMAT_RGBA8)
				for transform: Dictionary in origin.get("transforms", []):
					if transform.get("kind") != "resize_canvas" or transform.get("version") != 1 or transform.get("interpolation") != "nearest":
						push_error("Unknown source transform in pixel verification")
						quit(1)
						return
					expected.resize(transform.resize_to[0], transform.resize_to[1], Image.INTERPOLATE_NEAREST)
					var canvas := Image.create(transform.canvas_size[0], transform.canvas_size[1], false, Image.FORMAT_RGBA8)
					canvas.fill(Color.TRANSPARENT)
					canvas.blit_rect(expected, Rect2i(Vector2i.ZERO, expected.get_size()), Vector2i(transform.offset[0], transform.offset[1]))
					expected = canvas
				var actual: Image = result.candidate.art.clips[clip].frames[index].get_image()
				expected.convert(Image.FORMAT_RGBA8)
				actual.convert(Image.FORMAT_RGBA8)
				if actual.get_size() != expected.get_size() or actual.get_data() != expected.get_data():
					push_error("Processed pixels differ from original crop: %s frame %d" % [clip, index])
					quit(1)
					return
		print("PASS: every processed frame matches its original crop and recorded transforms")
	print("PASS: processed art loaded without raw assets or character module code")
	quit()
