class_name RoomPlayer
extends RefCounted
## Server-side record of one player inside one room.

var id := 0
var name := ""
var appearance: Dictionary = {}
var pos := Vector3.ZERO
var yaw := 0.0
var speed_q := 0
var flags := 0
var seat_id := -1
var dirty := true
var budget := NetProtocol.MOVE_BURST_M
var last_state_msec := 0
var last_sent_msec := 0
var last_heard_msec := 0
var last_correct_msec := 0
var violations := 0.0
var last_seat_msec := 0
var emote := -1
var emote_until_msec := 0
var last_emote_msec := 0
var chat_tokens := NetProtocol.CHAT_BURST
var last_chat_msec := 0
var last_chat_text := ""
var last_chat_text_msec := 0


func to_info() -> Dictionary:
	return {"id": id, "name": name, "appearance": appearance, "pos": pos, "yaw": yaw, "flags": flags, "seat_id": seat_id, "emote": emote}
