class_name UIUtils

## Utility functions for UI operations

## Clear all children from a node
static func clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
