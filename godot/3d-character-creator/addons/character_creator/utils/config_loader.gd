class_name ConfigLoader

## Utility for loading configuration files with consistent error handling

## Get the Blender export path from ProjectSettings
static func get_export_path() -> String:
	if not ProjectSettings.has_setting("character_creator/blender_export_path"):
		push_error("ConfigLoader: ProjectSettings missing 'character_creator/blender_export_path'. Run editor plugin rescan.")
		return ""

	return ProjectSettings.get_setting("character_creator/blender_export_path")

## Load the global config from the standard location
static func load_global_config() -> CharacterComponent:
	var export_path := get_export_path()
	if export_path == "":
		return null

	var global_path := export_path.path_join("global_config.tres")
	if not FileAccess.file_exists(global_path):
		push_error("ConfigLoader: Global config not found at: " + global_path)
		return null

	var config: CharacterComponent = load(global_path)
	if config == null:
		push_error("ConfigLoader: Failed to load global config from: " + global_path)
		return null

	return config

## Get the characters directory path
static func get_characters_dir() -> String:
	var export_path := get_export_path()
	if export_path == "":
		return ""

	return export_path.path_join("characters")

## Get the save path for a character by name (snake_case)
static func get_character_save_path(character_name: String) -> String:
	var characters_dir := get_characters_dir()
	if characters_dir == "":
		return ""

	return characters_dir.path_join(character_name.to_snake_case() + ".tres")
