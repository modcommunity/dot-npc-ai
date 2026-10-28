@tool
extends EditorPlugin

## Editor entry point for dot-npc-ai. It registers nothing: everything is a [RefCounted] built in code or a [Resource] ([DotNpcAiCharacter]) Godot already offers by `class_name`, and a custom type for a node that does not exist would be a menu entry that makes a broken node.
## It exists so the addon can be enabled and disabled like the others.


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass
