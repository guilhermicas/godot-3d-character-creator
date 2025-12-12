class_name TreeUtils

## Utility functions for traversing CharacterComponent trees

## Find a component by its cc_id in the tree
static func find_by_id(root: CharacterComponent, cc_id: String) -> CharacterComponent:
	if root == null or cc_id == "":
		return null

	if root.cc_id == cc_id:
		return root

	for child in root.children:
		var found := find_by_id(child, cc_id)
		if found:
			return found

	return null

## Check if a component or any of its descendants has the given cc_id
static func has_descendant_with_id(root: CharacterComponent, cc_id: String) -> bool:
	if root == null or cc_id == "":
		return false

	if root.cc_id == cc_id:
		return true

	for child in root.children:
		if has_descendant_with_id(child, cc_id):
			return true

	return false

## Check if a component exists in a flat array by cc_id
static func is_in_flat_array(cc_id: String, flat_array: Array[CharacterComponent]) -> bool:
	return flat_array.any(func(comp): return comp.cc_id == cc_id)
