@tool
extends Resource
class_name CharacterComponent

## Represents a character component (either a container or an actual model).
##
## FIELD USAGE BY NODE TYPE:
##
## CC_ (Actual Component - has GLB model):
##   - name: Folder name (e.g., "CC_male")
##   - glb_path: Path to 3D model file
##   - cc_id: Unique identifier
##   - display_name: User-facing label (editable)
##   - metadata: Custom data (e.g., albedo overrides)
##   - children: EMPTY (leaf nodes)
##   - instanced_model: Cached GLB PackedScene
##
## CCC_ (Container - organizes components):
##   - name: Folder name (e.g., "CCC_genders")
##   - glb_path: EMPTY (containers don't have models)
##   - cc_id: Unique identifier
##   - display_name: User-facing label (editable)
##   - metadata: EMPTY (not used for containers)
##   - children: Array of child components
##   - instanced_model: EMPTY (containers don't have models)
##
## BOTH types use:
##   - name, cc_id, display_name, metadata
##
## ONLY CC_ uses:
##   - glb_path, instanced_model
##
## ONLY CCC_ uses:
##   - children (non-empty array)

# Read-only model data (from folder/file scan)
@export_group("Model Data")
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var name: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var glb_path: String = ""
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY) var cc_id: String = ""

# Editable configuration (saved to global_config.tres or local_config.tres)
@export_group("Configuration")
@export var display_name: String = ""
@export var metadata: Dictionary = {}

# Defaults & Mandatory (CCC_ only)
@export_group("Defaults & Mandatory (CCC_ only)")
@export var default_child_id: String = ""  ## Which CC_ child to auto-select
@export var is_child_mandatory: bool = false  ## Must have ≥1 child selected

# Hierarchy
@export var children: Array[CharacterComponent] = []

var instanced_model: PackedScene = null  # Not exported, transient runtime data

## Validates and auto-fixes defaults & mandatory flags
func validate_defaults() -> Array[String]:
	var warnings: Array[String] = []

	# Auto-fix: No children = reset mandatory and default
	if children.is_empty():
		if is_child_mandatory or default_child_id != "":
			is_child_mandatory = false
			default_child_id = ""
		return warnings

	# Auto-fix: Mandatory requires default (pick first child)
	if is_child_mandatory and default_child_id == "":
		default_child_id = children[0].cc_id
		warnings.append("Auto-fixed: Set default_child_id to first child '%s'" % children[0].name)

	# Validate default exists in children
	if default_child_id != "":
		var found := false
		for child in children:
			if child.cc_id == default_child_id:
				found = true
				break
		if not found:
			warnings.append("Invalid default_child_id '%s' - not found in children" % default_child_id)
			default_child_id = ""  # Clear invalid default
			is_child_mandatory = false  # Can't be mandatory without valid default

	# Recursively validate children
	for child in children:
		var child_warnings := child.validate_defaults()
		warnings.append_array(child_warnings)

	return warnings

# Assemble hierarchical tree from flat array using global_config as authority
static func assemble_from_global(
	flat_items: Array[CharacterComponent],
	global_config: CharacterComponent
) -> CharacterComponent:
	var override_map := {}
	for item in flat_items:
		if item.cc_id != "":
			override_map[item.cc_id] = item
	
	return _assemble_recursive(global_config, override_map)

static func _assemble_recursive(
	source: CharacterComponent,
	override_map: Dictionary
) -> CharacterComponent:
	# Filter out CC_ nodes (actual components) not in local config
	# But keep CCC_ nodes (containers) - they define structure
	var is_component := source.glb_path != ""  # CC_ nodes have GLB paths
	if is_component and not override_map.has(source.cc_id):
		return null
	
	# Create copy with overrides
	var result := CharacterComponent.new()
	result.name = source.name
	result.glb_path = source.glb_path
	result.cc_id = source.cc_id
	result.display_name = source.display_name
	result.metadata = source.metadata.duplicate()
	result.default_child_id = source.default_child_id
	result.is_child_mandatory = source.is_child_mandatory

	# Apply local overrides
	if source.cc_id != "" and override_map.has(source.cc_id):
		var override: CharacterComponent = override_map[source.cc_id]
		if override.display_name != "":
			result.display_name = override.display_name
		if not override.metadata.is_empty():
			result.metadata = override.metadata.duplicate()
		# Override defaults/mandatory if set in local config
		if override.default_child_id != "":
			result.default_child_id = override.default_child_id
		result.is_child_mandatory = override.is_child_mandatory
	
	# Recursively process children
	for child in source.children:
		var assembled := _assemble_recursive(child, override_map)
		if assembled:
			result.children.append(assembled)
	
	return result
