class_name SeatTable
extends RefCounted
## Gives every Seat of a map a stable integer id, identically on the server and on every client.
## Ids are the index after sorting seats by (x, z, y) rounded to 1 cm - NOT node names or tree
## order, which differ between processes. Both sides must run the same map-building code
## (guaranteed by NetProtocol.PROTOCOL_VERSION).


static func collect(root: Node) -> Array[Seat]:
	var found: Array[Seat] = []
	_walk(root, found)
	found.sort_custom(_before)
	return found


static func _walk(n: Node, out: Array[Seat]) -> void:
	for c in n.get_children():
		if c is Seat:
			out.append(c)
		_walk(c, out)


static func _key(s: Seat) -> Vector3i:
	var p := s.global_position
	return Vector3i(roundi(p.x * 100.0), roundi(p.z * 100.0), roundi(p.y * 100.0))


static func _before(a: Seat, b: Seat) -> bool:
	var ka := _key(a)
	var kb := _key(b)
	if ka.x != kb.x:
		return ka.x < kb.x
	if ka.y != kb.y:
		return ka.y < kb.y
	return ka.z < kb.z
