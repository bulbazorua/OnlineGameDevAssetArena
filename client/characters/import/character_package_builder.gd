class_name CharacterPackageBuilder
extends RefCounted

const CharacterModuleExporter = preload("res://characters/import/character_module_exporter.gd")
const CharacterImporter = preload("res://characters/import/character_importer.gd")
const CharacterContract = preload("res://content/character_contract.gd")
const AssetSources = preload("res://characters/import/character_asset_sources.gd")


# Development workbench dispatch only. No roster writes or filename inference.
static func inspect_module(module_path: String, source_root := "", trace_path := "") -> Dictionary:
	var contract := CharacterContract.new()
	var error := contract.load_contract()
	if not error.is_empty(): return {"error": error}
	if not module_path.begins_with("res://") or ".." in module_path:
		return {"error": "Module must be a local res:// directory."}
	for filename in ["importer.gd", "exporter.gd"]:
		if not ResourceLoader.exists(module_path.path_join(filename)):
			return {"error": "Module requires its own " + filename}
	var importer_script = load(module_path.path_join("importer.gd"))
	var exporter_script = load(module_path.path_join("exporter.gd"))
	if not importer_script is GDScript or not exporter_script is GDScript or not importer_script.can_instantiate() or not exporter_script.can_instantiate():
		return {"error": "Invalid module entry-point script."}
	var importer = importer_script.new()
	var exporter = exporter_script.new()
	if not importer is CharacterImporter or not exporter is CharacterModuleExporter:
		return {"error": "Module must implement the shared importer/exporter interfaces."}
	var sources := AssetSources.new()
	error = sources.prepare(module_path, source_root, trace_path)
	if not error.is_empty(): return {"error": error}
	sources.note("custom_export", "started", {"module": module_path})
	var candidate = exporter.export_character({"module_root": module_path, "contract": contract.data.duplicate(true), "sources": sources})
	if not sources.error.is_empty(): return {"error": sources.error}
	if candidate != null and candidate.module_key != sources.manifest.module_key:
		return {"error": sources.fail("custom_export", module_path, "Export key disagrees with source inventory")}
	sources.note("custom_export", "pass", {"module": module_path})
	return {"error": "", "candidate": candidate, "report": contract.inspect(candidate), "contract": contract, "sources": sources}
