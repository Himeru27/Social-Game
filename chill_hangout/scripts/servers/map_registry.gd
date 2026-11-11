class_name MapRegistry
extends RefCounted
## The list of maps a server can host. Only one exists for now; add an entry (and a scene that
## contains Seat nodes + "spawn_points" markers) to add more. Each ROOM picks its own map.

const DEFAULT_MAP := "chill_hangout"
const MAPS := {
	"chill_hangout": {"name": "Chill Hangout Room", "scene": "res://scenes/lobby/hangout_room.tscn"},
}


static func has_map(id: String) -> bool:
	return MAPS.has(id)


static func map_name(id: String) -> String:
	return str(MAPS[id]["name"]) if MAPS.has(id) else "?"


static func scene_path(id: String) -> String:
	return str(MAPS[id]["scene"])


## [{id, name}] for UI drop-downs and the hello reply.
static func list() -> Array:
	var out: Array = []
	for id in MAPS:
		out.append({"id": id, "name": MAPS[id]["name"]})
	return out
