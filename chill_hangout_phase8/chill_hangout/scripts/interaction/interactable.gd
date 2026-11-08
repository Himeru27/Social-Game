class_name Interactable
extends Node3D
## Base class for anything the player can use with the interact key (E by default).
## Subclasses override can_interact / get_prompt / interact. Phase 5: the server validates
## interact requests; the client only asks.

@export var max_distance := 2.0


func _ready() -> void:
	add_to_group("interactable")


func interaction_point() -> Vector3:
	return global_position + Vector3(0, 0.5, 0)


func can_interact(_player: Node) -> bool:
	return true


func get_prompt(_player: Node) -> String:
	return "PRESS %s TO INTERACT" % GameSettings.key_label("interact")


func interact(_player: Node) -> void:
	pass
