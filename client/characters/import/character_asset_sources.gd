class_name CharacterAssetSources
extends RefCounted

# Shared file IO and evidence only. Sheet layout belongs to each importer.
var manifest: Dictionary = {}
var root := ""
var error := ""
var trace_path := ""
var images: Dictionary = {}
var origins: Dictionary = {}


func prepare(module_path: String, root_override := "", journal := "") -> String:
	trace_path = journal
	var path := module_path.path_join("source_manifest.json")
	if not FileAccess.file_exists(path): return fail("inventory", path, "Missing source_manifest.json")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("module_key") is String or not parsed.get("raw_root") is String or not parsed.get("files") is Dictionary or parsed.files.is_empty():
		return fail("inventory", path, "Invalid public source inventory")
	if not relative_path(parsed.raw_root): return fail("inventory", path, "raw_root must be repository relative")
	for source: Variant in parsed.files:
		if not source is String or not relative_path(source) or not parsed.files[source] is String or parsed.files[source].length() != 64:
			return fail("inventory", path, "Invalid source path or SHA-256")
	manifest = parsed
	root = root_override if not root_override.is_empty() else ProjectSettings.globalize_path("res://../").path_join(manifest.raw_root)
	note("inventory", "pass", {"source": path})
	return ""


func extract_frame(source: String, rectangle: Rect2i, clip: String, index: int) -> Texture2D:
	var details := {"source": source, "clip": clip, "frame": index, "rect": [rectangle.position.x, rectangle.position.y, rectangle.size.x, rectangle.size.y]}
	note("extract_frame", "started", details)
	var image := read_image(source)
	if image == null: return null
	if rectangle.size.x <= 0 or rectangle.size.y <= 0 or not Rect2i(Vector2i.ZERO, image.get_size()).encloses(rectangle):
		fail("extract_frame", source, "Frame rectangle lies outside source image", details)
		return null
	if not origins.has(clip): origins[clip] = {}
	if origins[clip].has(str(index)):
		fail("extract_frame", source, "Duplicate extracted clip/frame", details)
		return null
	details["source_sha256"] = manifest.files[source]
	origins[clip][str(index)] = details.duplicate(true)
	note("extract_frame", "pass", details)
	return ImageTexture.create_from_image(image.get_region(rectangle))


# Importers own the transform; shared infrastructure only records its lineage.
func record_transform(clip: String, index: int, transform: Dictionary) -> void:
	if not origins.has(clip) or not origins[clip].has(str(index)):
		fail("record_transform", "", "Cannot record a transform before extracting its frame", {"clip": clip, "frame": index})
		return
	var origin: Dictionary = origins[clip][str(index)]
	if not origin.has("transforms"): origin["transforms"] = []
	origin.transforms.append(transform.duplicate(true))
	note("transform_frame", "pass", origin)


func read_image(source: String) -> Image:
	if not error.is_empty(): return null
	if images.has(source): return images[source]
	if not manifest.files.has(source):
		fail("read_source", source, "Source is not declared in the inventory")
		return null
	var path := root.path_join(source)
	note("read_source", "started", {"source": source})
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != manifest.files[source]:
		fail("read_source", source, "Missing original or source SHA-256 mismatch")
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		fail("decode_source", source, "Cannot decode source PNG")
		return null
	images[source] = image
	note("read_source", "pass", {"source": source, "sha256": manifest.files[source], "width": image.get_width(), "height": image.get_height()})
	return image


func fail(stage: String, source: String, message: String, details: Dictionary = {}) -> String:
	if error.is_empty(): error = message
	var entry := details.duplicate(true)
	entry.merge({"source": source, "message": message}, true)
	note(stage, "fail", entry)
	return message


func note(stage: String, status: String, details: Dictionary = {}) -> void:
	if trace_path.is_empty(): return
	var file := FileAccess.open(trace_path, FileAccess.READ_WRITE if FileAccess.file_exists(trace_path) else FileAccess.WRITE)
	if file == null:
		error = "Cannot write processing trace: " + trace_path
		return
	var entry := details.duplicate(true)
	entry.merge({"stage": stage, "status": status, "time_unix": Time.get_unix_time_from_system()}, true)
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.close()


static func relative_path(path: String) -> bool:
	return not path.is_empty() and not path.is_absolute_path() and not ".." in path.split("/") and not "\\" in path and not ":" in path
