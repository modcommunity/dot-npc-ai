@tool
extends EditorPlugin

## Editor entry point for dot-npc-ai.
##
## It registers nothing. Everything here is either a [RefCounted] a game builds in code
## or a [Resource] — [DotNpcAiCharacter] — which Godot already offers by its
## [code]class_name[/code] in the New Resource dialog. There is no node to drag into a
## scene, and an addon that registered a custom type it did not have would be an entry
## in a menu that produces a broken node.
##
## It exists so the addon can be enabled and disabled like the others, which is what
## Godot's plugin list is for.


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass
