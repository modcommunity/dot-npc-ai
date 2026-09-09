@tool
extends EditorPlugin

## Editor entry point for dot-npc-ai.
##
## It registers nothing. Every class here is a [RefCounted] a game builds in code, so
## there is no node to drag into a scene — and an addon that registered a custom type it
## did not have would be an entry in a menu that produces a broken node.
##
## It exists so the addon can be enabled and disabled like the others, which is what
## Godot's plugin list is for.


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass
