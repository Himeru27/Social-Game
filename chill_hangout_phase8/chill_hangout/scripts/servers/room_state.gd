class_name RoomState
extends RefCounted
## Server-side record of one room (a "server instance" in the browser). Each room has its own
## map, player list and seat occupancy.

var id := 0
var name := ""
var is_private := false
var code := ""
var map_id := ""
var host_id := 0
var players: Dictionary = {}   # peer id -> RoomPlayer
var seats: Dictionary = {}     # seat id -> peer id
var created_msec := 0
var empty_since_msec := -1


func count() -> int:
	return players.size()


func is_full() -> bool:
	return players.size() >= NetProtocol.MAX_PLAYERS_PER_ROOM


## Impersonation check: case, spaces/-/_ and look-alike digits (0->o, 1/l->i, 3->e, 4->a, 5->s, 7->t)
## are ignored, so "Bob", "b0b" and "B O B" count as the same name. Other digits stay significant
## ("Player2" and "Player6" are different people).
static func skeleton(n: String) -> String:
	var map := {"0": "o", "1": "i", "l": "i", "3": "e", "4": "a", "5": "s", "7": "t"}
	var out := ""
	for c in n.to_lower():
		if c == " " or c == "-" or c == "_":
			continue
		out += map.get(c, c)
	return out


func name_taken(username: String) -> bool:
	var key := skeleton(username)
	for p: RoomPlayer in players.values():
		if skeleton(p.name) == key:
			return true
	return false


func summary(map_name: String) -> Dictionary:
	return {
		"id": id, "name": name, "map_id": map_id, "map_name": map_name, "players": count(),
		"max": NetProtocol.MAX_PLAYERS_PER_ROOM, "private": is_private,
		"status": "Full" if is_full() else "Open",
	}
