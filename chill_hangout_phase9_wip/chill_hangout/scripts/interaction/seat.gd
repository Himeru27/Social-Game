class_name Seat
extends Interactable
## One sit slot (chair, stool, one cushion of a sofa). The node origin is the FLOOR point under
## the sitter's hips; its -Z axis is the direction the sitter faces. One occupant per slot.
## claim()/release() are the hooks the server will call in Phase 5.

const EXIT_OFFSETS: Array[Vector3] = [
	Vector3(0, 0, -0.95), Vector3(0, 0, -1.3), Vector3(1.1, 0, -0.4), Vector3(-1.1, 0, -0.4), Vector3(0, 0, 1.0),
]

@export var seat_height := 0.45

var occupant: Node = null


func can_interact(player: Node) -> bool:
	return occupant == null or occupant == player


func get_prompt(player: Node) -> String:
	var key := GameSettings.key_label("interact")
	return "PRESS %s TO STAND" % key if occupant == player else "PRESS %s TO SIT" % key


func interact(player: Node) -> void:
	if player.has_method("sit"):
		player.sit(self)


func claim(who: Node) -> bool:
	if occupant != null and is_instance_valid(occupant) and occupant != who:
		return false
	occupant = who
	return true


func release(who: Node) -> void:
	if occupant == who:
		occupant = null


func facing_yaw() -> float:
	var f := -global_basis.z
	return atan2(-f.x, -f.z)


## First free standing spot around the seat (front first); falls back to the front.
func find_exit() -> Vector3:
	var space := get_world_3d().direct_space_state
	var probe := CapsuleShape3D.new()
	probe.radius = 0.28
	probe.height = 1.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.collision_mask = 1
	for off in EXIT_OFFSETS:
		var p := global_position + global_basis * off
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.1 + probe.height / 2.0, 0))
		if space.intersect_shape(q, 1).is_empty():
			return p
	return global_position + (-global_basis.z) * 0.95
