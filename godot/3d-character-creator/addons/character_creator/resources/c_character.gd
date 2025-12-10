@tool
extends Node3D
class_name CCharacter

## Character node that manages loading, saving, and building character meshes.
## Attach this to your player to enable character customization.
##
## Usage:
##   1. Add CCharacter node as child of your player
##   2. Call get_character_config() to retrieve current character
##   3. Pass to character creator scene for editing
##   4. Call apply_character_config() with new config when done
##
## The character automatically saves to disk in the Blender export path.

signal character_loaded
signal character_saved
signal meshes_rebuilt

var _global_config: CharacterComponent
var _character_save_path: String
var _flat_config: Array[CharacterComponent] = []
var _mesh_instances: Array[Node3D] = []

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_load_paths()
	_load_character()
	_rebuild_mesh()

func _load_paths() -> void:
	# Load paths from ProjectSettings
	if not ProjectSettings.has_setting("character_creator/blender_export_path"):
		push_error("CCharacter: ProjectSettings missing 'character_creator/blender_export_path'. Run editor plugin rescan.")
		return

	var export_path: String = ProjectSettings.get_setting("character_creator/blender_export_path")

	# Load global config (always at {blender_export_path}/global_config.tres)
	var global_path := export_path.path_join("global_config.tres")
	if not FileAccess.file_exists(global_path):
		push_error("CCharacter: Global config not found at: " + global_path)
		return

	_global_config = load(global_path)

	# Generate character save path from parent name
	var char_name := get_parent().name.to_snake_case()
	_character_save_path = export_path.path_join("characters/{0}.tres".format([char_name]))

func get_character_config() -> Array[CharacterComponent]:
	return _flat_config

func apply_character_config(config: Array[CharacterComponent]) -> void:
	_flat_config = config
	_save_to_disk()
	_rebuild_mesh()

func _load_character() -> void:
	if not FileAccess.file_exists(_character_save_path):
		print("CCharacter: No saved character at " + _character_save_path + ", starting fresh")
		_flat_config = []
		character_loaded.emit()
		return
	
	var local_res: LocalConfig = load(_character_save_path)
	if local_res == null:
		push_error("CCharacter: Failed to load character from: " + _character_save_path)
		_flat_config = []
		character_loaded.emit()
		return
	
	_flat_config = local_res.items
	print("CCharacter: Loaded character from " + _character_save_path)
	character_loaded.emit()

func _save_to_disk() -> void:
	# Ensure characters directory exists
	var char_dir := _character_save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(char_dir):
		DirAccess.make_dir_recursive_absolute(char_dir)
	
	var local_res := LocalConfig.new()
	local_res.items = _flat_config
	
	var result := ResourceSaver.save(local_res, _character_save_path)
	if result == OK:
		print("CCharacter: Saved character to " + _character_save_path)
		character_saved.emit()
	else:
		push_error("CCharacter: Failed to save character to " + _character_save_path)

func _rebuild_mesh() -> void:
	# Clear existing meshes
	for instance in _mesh_instances:
		instance.queue_free()
	_mesh_instances.clear()
	
	if _flat_config.is_empty() or _global_config == null:
		meshes_rebuilt.emit()
		return
	
	# Assemble hierarchy from flat array using global config authority
	var assembled := CharacterComponent.assemble_from_global(_flat_config, _global_config)
	
	# Instantiate meshes with proper hierarchy
	_instantiate_recursive(assembled, self)
	
	# Free unused GLBs from cache
	_free_unused_glbs()
	
	meshes_rebuilt.emit()

func _instantiate_recursive(component: CharacterComponent, parent: Node3D) -> void:
	var current_node: Node3D = parent
	
	# If this component has a model, instantiate it
	if component.glb_path != "":
		var cached := GLBCache.get_cached(component.cc_id)
		if not cached:
			# Load and cache
			cached = load(component.glb_path)
			if cached:
				GLBCache.cache(component.cc_id, cached)
			else:
				push_error("CCharacter: Failed to load GLB: " + component.glb_path)
				return
		
		if cached:
			var instance := cached.instantiate() as Node3D
			parent.add_child(instance)
			_mesh_instances.append(instance)
			current_node = instance
	
	# Recursively instantiate children
	for child in component.children:
		if child:  # Skip null children (defensive programming)
			_instantiate_recursive(child, current_node)

func _free_unused_glbs() -> void:
	# Build set of cc_ids currently in use
	var used_ids := {}
	for comp in _flat_config:
		used_ids[comp.cc_id] = true
	
	# Evict from cache if not in use
	GLBCache.evict_except(used_ids)
