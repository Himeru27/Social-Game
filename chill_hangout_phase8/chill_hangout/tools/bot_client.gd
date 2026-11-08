extends Node
## Headless test client that uses the REAL Net autoload (same code path as the game).
## godot --headless --path . res://tools/bot_client.tscn -- --name=Bot1 --mode=create|join|code|badcode
##   [--room=Name] [--private] [--code=ABC-12345] [--seconds=8] [--host=127.0.0.1] [--port=7777]
##   [--sit] (walk to the nearest seat and sit) [--appearance=female]
## Prints "BOT <name>: ..." lines that tools/test_network.sh greps.

var a: Dictionary = {}
var _name := "Bot"
var _t := 0.0
var _pos := Vector3.ZERO
var _joined := false
var _seen: Dictionary = {}
var _snap_count := 0
var _done := false
var _seat_try := false
var _seat_targets: Array = []
var _sit_id := -1
var _sit_sent := false
var _acc := 0.0


func _ready() -> void:
	a = _args()
	_name = str(a.get("name", "Bot"))
	PlayerProfile.username = _name
	PlayerProfile.appearance = AppearanceData.default_for(str(a.get("appearance", "male")))
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(func(m: String) -> void: _say("CONNECT_FAILED " + m); _finish(2))
	Net.disconnected.connect(func(m: String) -> void: _say("DISCONNECTED " + m); _finish(0))
	Net.join_succeeded.connect(_on_join)
	Net.join_failed.connect(func(c: int, m: String) -> void: _say("JOIN_FAILED %d %s" % [c, m]); _finish(0))
	Net.player_joined.connect(func(i: Dictionary) -> void: _say("PLAYER_JOINED %s" % i["name"]))
	Net.player_left.connect(func(_id: int, n: String, r: String) -> void: _say("PLAYER_LEFT %s %s" % [n, r]))
	Net.snapshot_received.connect(_on_snap)
	Net.seat_result.connect(func(s: int, ok: bool, m: String) -> void:
		_say("SEAT_RESULT %d %s %s" % [s, ok, m])
		if ok and a.has("stand"):
			await get_tree().create_timer(2.0).timeout
			_say("STANDING")
			Net.notify_stand())
	Net.seat_event.connect(func(p: int, s: int) -> void: _say("SEAT_EVENT %d %d" % [p, s]))
	Net.position_corrected.connect(func(p: Vector3, _y: float) -> void: _say("CORRECTED %s" % p); _pos = p)
	Net.chat_received.connect(func(_p: int, n: String, t: String) -> void: _say("CHAT %s|%s" % [n, t]))
	Net.emote_event.connect(func(p: int, e: int) -> void: _say("EMOTE_EVENT peer=%d emote=%d" % [p, e]))
	Net.notice.connect(func(m: String) -> void: _say("NOTICE " + m))
	Net.kicked.connect(func(m: String) -> void: _say("KICKED " + m))
	Net.connect_to_server(str(a.get("host", "127.0.0.1")), int(a.get("port", 7777)))


func _on_connected(_info: Dictionary) -> void:
	_say("CONNECTED")
	match str(a.get("mode", "join")):
		"create": Net.create_room(str(a.get("room", "Bot Room")), a.has("private"), "chill_hangout")
		"code": Net.join_with_code(str(a.get("code", "")))
		"badcode": Net.join_with_code("NOPE-00000")
		"list":
			Net.room_list_received.connect(func(r: Array) -> void:
				_say("ROOMS %d %s" % [r.size(), JSON.stringify(r)])
				_finish(0))
			Net.request_room_list()
		_:
			Net.room_list_received.connect(func(r: Array) -> void:
				if r.is_empty():
					_say("NO_ROOMS")
					_finish(0)
				else:
					Net.join_room(int(r[0]["id"])))
			Net.request_room_list()


func _on_join(info: Dictionary) -> void:
	_joined = true
	_pos = info["spawn_pos"]
	if a.has("sitwalk"):
		var room: Node3D = (load(MapRegistry.scene_path(str(info["map_id"]))) as PackedScene).instantiate()
		add_child(room)
		var seats := SeatTable.collect(room)
		_sit_id = int(a["sitwalk"]) if str(a["sitwalk"]).is_valid_int() else 12
		_seat_targets = [seats[_sit_id].global_position]
		_say("SEAT_TARGET id=%d at %s" % [_sit_id, _seat_targets[0]])
		room.queue_free()
	for p in info["players"]:
		if int(p["emote"]) >= 0:
			_say("EXISTING_EMOTE %s=%d" % [p["name"], p["emote"]])
	_say("JOINED room=%d code=%s players=%d seats=%d spawn=%s" % [info["room_id"], info["code"], (info["players"] as Array).size() + 1, info["seat_count"], _pos])


func _on_snap(entries: Array) -> void:
	_snap_count += 1
	for e in entries:
		_seen[e["id"]] = e["pos"]


func _physics_process(delta: float) -> void:
	if not _joined or _done:
		return
	_t += delta
	_acc += delta
	var send := _acc >= 0.05
	if send:
		_acc = 0.0
	if _t > 1.0 and not a.has("did_social"):
		a["did_social"] = true
		if a.has("say"):
			Net.send_chat(str(a["say"]))
		if a.has("long"):
			Net.send_chat("x".repeat(400))
		if a.has("empty"):
			Net.send_chat("   ")
			Net.send_chat("\n\t")
		if a.has("bad"):
			Net.send_chat("you are a sh1t")
		if a.has("spam"):
			for i in 10:
				Net.send_chat("spam %d" % i)
		if a.has("emote"):
			Net.send_emote(int(a["emote"]))
	if a.has("say_late") and _t > 6.0 and not a.has("did_late"):
		a["did_late"] = true
		Net.send_chat(str(a["say_late"]))
	if a.has("emote_cancel") and _t > 3.0 and not a.has("did_cancel"):
		a["did_cancel"] = true
		Net.send_emote(-1)
	if a.has("teleport") and _t > 1.0 and not a.has("did_tp"):
		a["did_tp"] = true
		_pos += Vector3(40, 0, 0)       # cheat: impossible jump -> server must reject
		_say("TELEPORTING")
	if a.has("sit") and _t > 1.0 and not _seat_try:
		_seat_try = true
		# Seat 0 is far from the spawn -> the server must refuse ("too far").
		Net.request_sit(0)
	if a.has("sitwalk") and not _seat_targets.is_empty():
		var tgt: Vector3 = _seat_targets[0]
		var d := Vector3(tgt.x - _pos.x, 0, tgt.z - _pos.z)
		if d.length() > 1.2:
			_pos += d.normalized() * 5.0 * delta
		elif not _sit_sent:
			_sit_sent = true
			Net.request_sit(_sit_id)
		if send:
			Net.send_state(_pos, 0.0, 5.0, 0)
		if _t >= float(a.get("seconds", 8.0)):
			_report()
			_finish(0)
		return
	# walk in a circle at ~3 m/s
	var ang := _t * 0.6 + float(_name.hash() % 100)
	if not a.has("still") and not a.has("teleport"):
		_pos += Vector3(cos(ang), 0, sin(ang)) * 3.0 * delta * 0.5
	if send:
		Net.send_state(_pos, ang, 0.0 if a.has("still") else 3.0, 0)
	if _t >= float(a.get("seconds", 8.0)):
		_report()
		_finish(0)


func _report() -> void:
	_say("REPORT snapshots=%d others_seen=%d" % [_snap_count, _seen.size()])


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	Net.disconnect_from_server()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(code)


func _say(m: String) -> void:
	print("BOT %s: %s" % [_name, m])


func _args() -> Dictionary:
	var o := {}
	for s in OS.get_cmdline_user_args():
		if s.begins_with("--"):
			var kv := s.substr(2).split("=", true, 1)
			o[kv[0]] = kv[1] if kv.size() > 1 else true
	return o
