@tool
extends EditorPlugin

var editor_panel: Control

func _enter_tree() -> void:
	editor_panel = preload("res://addons/character_creator/editor/dock.tscn").instantiate()
	editor_panel.plugin = self

	add_control_to_bottom_panel(editor_panel, "Character Creator")

func _exit_tree() -> void:
	if editor_panel:
		remove_control_from_bottom_panel(editor_panel)
		editor_panel.queue_free()
