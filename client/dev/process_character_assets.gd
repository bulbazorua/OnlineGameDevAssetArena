extends SceneTree

const Builder = preload("res://characters/import/character_package_builder.gd")
const Artifact = preload("res://characters/character_artifact.gd")
var request: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	request = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var result := Builder.inspect_module(request.module, request.raw_snapshot, request.trace, request.get("contract_path", Builder.CharacterContract.PATH))
	if not result.error.is_empty():
		_finish(false, "import", result.error)
		return
	var sources = result.sources
	var structurally_valid: bool = result.report.checks.filter(func(check): return check.id in ["exports", "metrics", "clips", "bindings"]).all(func(check): return check.status == "pass")
	if not structurally_valid:
		_finish(false, "validate", "Invalid normalized art export", result.report)
		return
	var written := Artifact.write(result.candidate, sources, request.output, request.input_digest)
	if not written.error.is_empty() or not sources.error.is_empty():
		_finish(false, "serialize", written.get("error", sources.error), result.report)
		return
	sources.note("reload_processed", "started", {"output": written.path})
	var reloaded := Artifact.read(written.path, written.digest)
	if not reloaded.error.is_empty():
		_finish(false, "reload_processed", reloaded.error, result.report)
		return
	if not reloaded.report.art_pass:
		_finish(false, "validate", "Required art contract failed; staged artifact retained", reloaded.report, written.digest)
		return
	sources.note("reload_processed", "pass", {"output": written.path})
	_finish(true, "processed", "", reloaded.report, written.digest)


func _finish(ok: bool, stage: String, message: String, diagnostics: Dictionary = {}, digest := "") -> void:
	var file := FileAccess.open(request.result, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write worker result")
		quit(1)
		return
	file.store_string(JSON.stringify({"ok": ok, "stage": stage, "error": message, "diagnostics": diagnostics, "artifact_digest": digest}, "  "))
	file.close()
	quit(0 if ok else 1)
