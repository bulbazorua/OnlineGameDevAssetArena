extends RefCounted

# Saved on/off flags for one player window's development displays. Godot user
# storage, outside the repository and outside launcher generations; a test may
# supply its own directory so the owner's settings stay untouched.
var path := ""
var flags: Dictionary = {}
var defaults: Dictionary = {}
var section := ""
var error := ""


func configure(owner: int, name: String, initial: Dictionary) -> void:
	section = name
	defaults = initial.duplicate()
	flags = initial.duplicate()
	if not OS.is_debug_build() or "--dev" not in OS.get_cmdline_user_args(): return
	var directory := "user://dev"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dev-preferences-dir="):
			var supplied := argument.trim_prefix("--dev-preferences-dir=")
			if supplied.is_absolute_path(): directory = supplied
	path = directory.path_join("%s-p%d.cfg" % [name, owner])
	reload()


# Reads the saved flags again; returns true when any value differs from before.
func reload() -> bool:
	if path.is_empty(): return false
	var config := ConfigFile.new()
	var loaded := config.load(path)
	var next := defaults.duplicate()
	if loaded == OK:
		for key: String in defaults:
			var value = config.get_value(section, key, defaults[key])
			if value is bool: next[key] = value
	elif loaded != ERR_FILE_NOT_FOUND:
		error = "Could not read saved %s settings." % section
	var changed := next != flags
	flags = next
	return changed


func get_flag(key: String) -> bool:
	return bool(flags.get(key, defaults.get(key, false)))


func save(key: String, value: bool) -> void:
	flags[key] = value
	if path.is_empty(): return
	error = ""
	var config := ConfigFile.new()
	config.load(path)
	for flag: String in flags: config.set_value(section, flag, flags[flag])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var temporary := path + ".%d.tmp" % OS.get_process_id()
	if config.save(temporary) != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) != OK:
		error = "Could not save %s settings." % section
