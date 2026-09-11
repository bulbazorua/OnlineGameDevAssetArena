extends RefCounted

var path := ""
var enabled := false
var error := ""


func configure(owner: int) -> void:
	if not OS.is_debug_build() or "--dev" not in OS.get_cmdline_user_args(): return
	var directory := "user://dev"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dev-preferences-dir="):
			var supplied := argument.trim_prefix("--dev-preferences-dir=")
			if supplied.is_absolute_path(): directory = supplied
	path = directory.path_join("search-p%d.cfg" % owner)
	reload()


func reload() -> bool:
	if path.is_empty(): return false
	var config := ConfigFile.new()
	var loaded := config.load(path)
	var next := false
	if loaded == OK:
		var value = config.get_value("search", "enabled", false)
		if value is bool: next = value
	elif loaded != ERR_FILE_NOT_FOUND:
		error = "Could not read saved search setting."
	var changed := enabled != next
	enabled = next
	return changed


func save(value: bool) -> void:
	if path.is_empty(): return
	error = ""
	var config := ConfigFile.new()
	config.set_value("search", "enabled", value)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var temporary := path + ".%d.tmp" % OS.get_process_id()
	if config.save(temporary) != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) != OK:
		error = "Could not save search setting."
	enabled = value
