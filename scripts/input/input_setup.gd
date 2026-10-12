extends Node
## Installs the pinned section 11 control map before anything reads input, so
## the map lives in code and cannot drift through a hand-edited project.godot
## [input] block.


func _enter_tree() -> void:
	InputMapSetup.install()
