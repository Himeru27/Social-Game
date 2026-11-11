class_name GameServer
extends Node
## Dedicated-server logic: sessions, rooms (public + private), invitation codes, spawning,
## validation, snapshots, cleanup. It never trusts a client: every request is rate limited and
## validated here. The RPC endpoints live in the Net autoload and forward to the on_* methods.
##
## Rooms are logical: one ENet endpoint hosts many rooms, and the server only relays data between
## members of the same room. A private room is reachable ONLY through its code, and membership is
## checked on the server for every request.

class Session:
	extends RefCounted
	var id := 0
	var address := ""
	var hello := false
	var room_id := -1
	var connected_msec := 0
	var req_tokens := 16.0
	var state_tokens := 60.0
	var last_refill_msec := 0
	var strikes := 0

const CODE_ALPHABET := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const REQ_RATE := 8.0
const REQ_CAP := 16.0
const STATE_RATE := 40.0
const STATE_CAP := 60.0
const CODE_FAILS_MAX := 6
const CODE_WINDOW_MSEC := 60000
const CODE_LOCK_MSEC := 60000

var net: Node                          # the Net autoload (RPC senders)
var maps: Dictionary = {}              # map id -> {seats: Array[{pos,yaw,height}], spawns: Array[Vector3]}
var server_name := "Chill Hangout Server"
var max_rooms := 20
var empty_timeout_sec := 30.0

var _sessions: Dictionary = {}         # peer id -> Session
var _rooms: Dictionary = {}            # room id -> RoomState
var _codes: Dictionary = {}            # code -> room id
var _next_room_id := 1
var _code_fails: Dictionary = {}       # address -> {count, window_start, locked_until}
var _snap_acc := 0.0
var _slow_acc := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_net: Node, p_maps: Dictionary, opts: Dictionary) -> void:
	net = p_net
	maps = p_maps
	server_name = str(opts.get("name", server_name))
	max_rooms = int(opts.get("max_rooms", max_rooms))
	empty_timeout_sec = float(opts.get("empty_timeout", empty_timeout_sec))
	_rng.randomize()


func log_line(msg: String) -> void:
	print("[server %s] %s" % [Time.get_time_string_from_system(), msg])


# ------------------------------------------------------------------ connection events

func on_peer_connected(id: int) -> void:
	var s := Session.new()
	s.id = id
	s.address = net.get_peer_address(id)
	s.connected_msec = Time.get_ticks_msec()
	s.last_refill_msec = s.connected_msec
	_sessions[id] = s
	log_line("peer %d connected (%s), sessions: %d" % [id, s.address, _sessions.size()])


func on_peer_disconnected(id: int) -> void:
	_remove_from_room(id, "disconnected")
	_sessions.erase(id)
	log_line("peer %d disconnected, sessions: %d" % [id, _sessions.size()])


# ------------------------------------------------------------------ request handlers

func on_hello(id: int, version: int) -> void:
	var s := _session(id)
	if s == null or not _allow_request(s):
		return
	if version != NetProtocol.PROTOCOL_VERSION:
		net.s_hello_result.rpc_id(id, false, NetProtocol.err_text(NetProtocol.Err.BAD_VERSION), {})
		_kick_later(id)
		return
	s.hello = true
	net.s_hello_result.rpc_id(id, true, "", {
		"server_name": server_name, "maps": MapRegistry.list(), "max_players": NetProtocol.MAX_PLAYERS_PER_ROOM,
		"version": NetProtocol.PROTOCOL_VERSION,
	})


func on_list_rooms(id: int) -> void:
	var s := _session(id)
	if s == null or not s.hello or not _allow_request(s):
		return
	var out: Array = []
	for r: RoomState in _rooms.values():
		if not r.is_private:
			out.append(r.summary(MapRegistry.map_name(r.map_id)))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["players"]) > int(b["players"]))
	net.s_room_list.rpc_id(id, out)


func on_create_room(id: int, room_name: String, is_private: bool, map_id: String, username: String, appearance: Dictionary) -> void:
	var s := _session(id)
	if s == null or not s.hello or not _allow_request(s):
		return
	if s.room_id != -1:
		return _join_fail(id, NetProtocol.Err.ALREADY_IN_ROOM)
	room_name = room_name.strip_edges()
	if NetProtocol.validate_room_name(room_name) != "":
		return _join_fail(id, NetProtocol.Err.BAD_ROOM_NAME)
	if not MapRegistry.has_map(map_id) or not maps.has(map_id):
		return _join_fail(id, NetProtocol.Err.BAD_MAP)
	if AppearanceData.validate_username(username) != "":
		return _join_fail(id, NetProtocol.Err.BAD_NAME)
	if _rooms.size() >= max_rooms:
		return _join_fail(id, NetProtocol.Err.SERVER_FULL)
	var room := RoomState.new()
	room.id = _next_room_id
	_next_room_id += 1
	room.name = room_name
	room.is_private = is_private
	room.map_id = map_id
	room.host_id = id
	room.created_msec = Time.get_ticks_msec()
	if is_private:
		room.code = _make_code(room_name)
		if room.code == "":
			return _join_fail(id, NetProtocol.Err.SERVER_FULL)
		_codes[room.code] = room.id
	_rooms[room.id] = room
	log_line("room %d \"%s\" created by %d (%s, map %s)%s" % [room.id, room.name, id, "private" if is_private else "public", map_id, " code " + room.code if is_private else ""])
	_enter_room(s, room, username, appearance)


func on_join_room(id: int, room_id: int, username: String, appearance: Dictionary) -> void:
	var s := _session(id)
	if s == null or not s.hello or not _allow_request(s):
		return
	if s.room_id != -1:
		return _join_fail(id, NetProtocol.Err.ALREADY_IN_ROOM)
	var room: RoomState = _rooms.get(room_id)
	# A private room can never be joined by id - treat it exactly like a missing room.
	if room == null or room.is_private:
		return _join_fail(id, NetProtocol.Err.ROOM_UNAVAILABLE)
	_try_join(s, room, username, appearance)


func on_join_code(id: int, code: String, username: String, appearance: Dictionary) -> void:
	var s := _session(id)
	if s == null or not s.hello or not _allow_request(s):
		return
	if s.room_id != -1:
		return _join_fail(id, NetProtocol.Err.ALREADY_IN_ROOM)
	if _code_locked(s.address):
		return _join_fail(id, NetProtocol.Err.RATE_LIMITED)
	code = code.strip_edges().to_upper()
	var rx := RegEx.new()
	rx.compile("^[A-Z]{3,5}-[A-Z0-9]{5}$")
	if code.length() > 12 or rx.search(code) == null or not _codes.has(code):
		_note_code_fail(s.address)
		return _join_fail(id, NetProtocol.Err.INVALID_CODE)
	var room: RoomState = _rooms.get(int(_codes[code]))
	if room == null:
		_codes.erase(code)
		return _join_fail(id, NetProtocol.Err.ROOM_UNAVAILABLE)
	# Do NOT reset the failure counter on success: a player who knows one valid code could
	# otherwise interleave joins to keep brute-forcing other codes.
	_try_join(s, room, username, appearance)


func on_leave_room(id: int) -> void:
	var s := _session(id)
	if s == null or not _allow_request(s):
		return
	_remove_from_room(id, "left")


func on_state(id: int, packet: PackedByteArray) -> void:
	var s := _session(id)
	if s == null or s.room_id == -1 or not _allow_state(s):
		return
	var room: RoomState = _rooms.get(s.room_id)
	if room == null:
		return
	var p: RoomPlayer = room.players.get(id)
	var d := NetProtocol.decode_client_state(packet)
	if p == null or d.is_empty():
		return
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - p.last_state_msec) / 1000.0, 0.0, 1.0)
	p.last_state_msec = now
	p.last_heard_msec = now
	p.budget = minf(p.budget + NetProtocol.MAX_SPEED * dt, NetProtocol.MOVE_BURST_M)
	p.violations = maxf(0.0, p.violations - dt * 2.0)

	var flags: int = int(d["flags"]) & (NetProtocol.FLAG_CROUCH | NetProtocol.FLAG_SPRINT)
	if p.seat_id != -1:
		# Seated: position/yaw are owned by the seat. Only keep-alive matters.
		return
	var np: Vector3 = d["pos"]
	var lim := NetProtocol.BOUNDS_XZ
	var dist := Vector2(np.x - p.pos.x, np.z - p.pos.z).length()
	var ok := absf(np.x) <= lim and absf(np.z) <= lim and np.y >= NetProtocol.BOUNDS_Y_MIN and np.y <= NetProtocol.BOUNDS_Y_MAX \
		and dist <= p.budget and absf(np.y - p.pos.y) <= 3.0
	if not ok:
		p.violations += 1.0
		if now - p.last_correct_msec > 250:
			p.last_correct_msec = now
			net.s_correct.rpc_id(id, p.pos, p.yaw)
		if p.violations > 40.0:
			log_line("kicking %d (%s): movement validation" % [id, p.name])
			_kick(id, "You were removed for sending invalid movement.")
		return
	p.budget -= dist
	if p.emote != -1 and (int(d["speed_q"]) > NetProtocol.EMOTE_CANCEL_SPEED_Q or (flags & NetProtocol.FLAG_CROUCH) != 0):
		_set_emote(room, p, -1, true)
	var speed_q := mini(int(d["speed_q"]), int(NetProtocol.MAX_SPEED * 20.0))
	if np != p.pos or d["yaw"] != p.yaw or flags != (p.flags & ~NetProtocol.FLAG_SEATED) or speed_q != p.speed_q:
		p.pos = np
		p.yaw = d["yaw"]
		p.speed_q = speed_q
		p.flags = flags
		p.dirty = true


func on_sit(id: int, seat_id: int) -> void:
	var s := _session(id)
	if s == null or s.room_id == -1 or not _allow_request(s):
		return
	var room: RoomState = _rooms.get(s.room_id)
	var p: RoomPlayer = room.players.get(id) if room != null else null
	if p == null:
		return
	var table: Array = maps[room.map_id]["seats"]
	var now := Time.get_ticks_msec()
	var reason := ""
	if seat_id < 0 or seat_id >= table.size():
		reason = "That seat does not exist."
	elif p.seat_id != -1:
		reason = "You are already seated."
	elif room.seats.has(seat_id):
		reason = "That seat is taken."
	elif now - p.last_seat_msec < 300:
		reason = "Slow down."
	else:
		var sp: Vector3 = table[seat_id]["pos"]
		if Vector2(sp.x - p.pos.x, sp.z - p.pos.z).length() > NetProtocol.SIT_RANGE or absf(sp.y - p.pos.y) > 2.0:
			reason = "You are too far from that seat."
	p.last_seat_msec = now
	if reason != "":
		net.s_seat_result.rpc_id(id, seat_id, false, reason)
		return
	if p.emote != -1:
		_set_emote(room, p, -1, false)
	room.seats[seat_id] = id
	p.seat_id = seat_id
	p.pos = table[seat_id]["pos"]
	p.yaw = table[seat_id]["yaw"]
	p.speed_q = 0
	p.flags = NetProtocol.FLAG_SEATED
	p.dirty = true
	net.s_seat_result.rpc_id(id, seat_id, true, "")
	_broadcast_seat(room, id, seat_id)


func on_stand(id: int) -> void:
	var s := _session(id)
	if s == null or s.room_id == -1 or not _allow_request(s):
		return
	var room: RoomState = _rooms.get(s.room_id)
	var p: RoomPlayer = room.players.get(id) if room != null else null
	if p == null or p.seat_id == -1:
		return
	_release_seat(room, p)
	_broadcast_seat(room, id, -1)


func on_chat(id: int, text: String) -> void:
	var s := _session(id)
	if s == null or s.room_id == -1 or not _allow_request(s):
		return
	var room: RoomState = _rooms.get(s.room_id)
	var p: RoomPlayer = room.players.get(id) if room != null else null
	if p == null:
		return
	var clean := sanitize_chat(text)
	if clean == "":
		return
	var now := Time.get_ticks_msec()
	p.chat_tokens = minf(NetProtocol.CHAT_BURST, p.chat_tokens + float(now - p.last_chat_msec) / 1000.0 / NetProtocol.CHAT_REFILL_SEC)
	p.last_chat_msec = now
	if p.chat_tokens < 1.0:
		net.s_notice.rpc_id(id, "You are sending messages too fast.")
		return
	if clean == p.last_chat_text and now - p.last_chat_text_msec < NetProtocol.CHAT_REPEAT_MSEC:
		net.s_notice.rpc_id(id, "Please don't repeat the same message.")
		return
	var key := AppearanceData.name_key(clean)
	for w in AppearanceData.BLOCKED_WORDS:
		if w in key:
			net.s_notice.rpc_id(id, "Message blocked.")
			return
	p.chat_tokens -= 1.0
	p.last_chat_text = clean
	p.last_chat_text_msec = now
	for q: RoomPlayer in room.players.values():
		net.s_chat.rpc_id(q.id, id, p.name, clean)


## Strips control characters, collapses whitespace, limits length. "" = nothing to send.
static func sanitize_chat(text: String) -> String:
	var out := ""
	for c in text:
		var code := c.unicode_at(0)
		if code < 32 or code == 127:
			continue
		out += c
	var parts := out.strip_edges().split(" ", false)
	out = " ".join(parts)
	return out.substr(0, NetProtocol.CHAT_MAX)


func on_emote(id: int, emote_id: int) -> void:
	var s := _session(id)
	if s == null or s.room_id == -1 or not _allow_request(s):
		return
	var room: RoomState = _rooms.get(s.room_id)
	var p: RoomPlayer = room.players.get(id) if room != null else null
	if p == null:
		return
	if emote_id == -1:
		if p.emote != -1:
			_set_emote(room, p, -1, false)
		return
	var now := Time.get_ticks_msec()
	var ok := emote_id >= 0 and emote_id < NetProtocol.EMOTES.size() and p.seat_id == -1 \
		and (p.flags & NetProtocol.FLAG_CROUCH) == 0 and now - p.last_emote_msec >= NetProtocol.EMOTE_COOLDOWN_MSEC
	p.last_emote_msec = now
	if not ok:
		net.s_emote.rpc_id(id, id, -1)     # tell the requester to cancel
		return
	_set_emote(room, p, emote_id, false)


func _set_emote(room: RoomState, p: RoomPlayer, emote_id: int, tell_owner: bool) -> void:
	p.emote = emote_id
	p.emote_until_msec = 0
	if emote_id >= 0 and not NetProtocol.EMOTES[emote_id]["loop"]:
		p.emote_until_msec = Time.get_ticks_msec() + int(float(NetProtocol.EMOTES[emote_id]["dur"]) * 1000.0) + 300
	for q: RoomPlayer in room.players.values():
		if q.id != p.id or tell_owner:
			net.s_emote.rpc_id(q.id, p.id, emote_id)


# ------------------------------------------------------------------ joining / leaving

func _try_join(s: Session, room: RoomState, username: String, appearance: Dictionary) -> void:
	if room.is_full():
		return _join_fail(s.id, NetProtocol.Err.ROOM_FULL)
	if AppearanceData.validate_username(username) != "":
		return _join_fail(s.id, NetProtocol.Err.BAD_NAME)
	if room.name_taken(username):
		return _join_fail(s.id, NetProtocol.Err.NAME_TAKEN)
	_enter_room(s, room, username, appearance)


func _enter_room(s: Session, room: RoomState, username: String, appearance: Dictionary) -> void:
	var p := RoomPlayer.new()
	p.id = s.id
	p.name = username
	p.appearance = AppearanceData.sanitize(appearance)   # never trust client appearance
	var spawn := _pick_spawn(room)
	p.pos = spawn
	p.yaw = 0.0
	var now := Time.get_ticks_msec()
	p.last_state_msec = now
	p.last_heard_msec = now
	p.last_sent_msec = now
	room.players[s.id] = p
	room.empty_since_msec = -1
	s.room_id = room.id
	var others: Array = []
	for q: RoomPlayer in room.players.values():
		if q.id != s.id:
			others.append(q.to_info())
	var info := {
		"room_id": room.id, "room_name": room.name, "map_id": room.map_id, "map_name": MapRegistry.map_name(room.map_id),
		"private": room.is_private, "code": room.code, "max": NetProtocol.MAX_PLAYERS_PER_ROOM,
		"your_id": s.id, "spawn_pos": p.pos, "spawn_yaw": p.yaw, "host_id": room.host_id,
		"seat_count": (maps[room.map_id]["seats"] as Array).size(), "players": others,
	}
	net.s_join_result.rpc_id(s.id, true, NetProtocol.Err.OK, "", info)
	for q: RoomPlayer in room.players.values():
		if q.id != s.id:
			net.s_player_joined.rpc_id(q.id, p.to_info())
	log_line("%d \"%s\" joined room %d \"%s\" (%d/%d)" % [s.id, p.name, room.id, room.name, room.count(), NetProtocol.MAX_PLAYERS_PER_ROOM])


func _remove_from_room(id: int, reason: String) -> void:
	var s := _session(id)
	if s == null or s.room_id == -1:
		return
	var room: RoomState = _rooms.get(s.room_id)
	s.room_id = -1
	if room == null:
		return
	var p: RoomPlayer = room.players.get(id)
	if p == null:
		return
	if p.seat_id != -1:
		_release_seat(room, p)
	room.players.erase(id)
	if room.host_id == id and not room.players.is_empty():
		room.host_id = (room.players.values()[0] as RoomPlayer).id
	for q: RoomPlayer in room.players.values():
		net.s_player_left.rpc_id(q.id, id, p.name, reason, room.host_id)
	if room.players.is_empty():
		room.empty_since_msec = Time.get_ticks_msec()
	log_line("%d \"%s\" %s room %d \"%s\" (%d/%d)" % [id, p.name, reason, room.id, room.name, room.count(), NetProtocol.MAX_PLAYERS_PER_ROOM])


func _release_seat(room: RoomState, p: RoomPlayer) -> void:
	room.seats.erase(p.seat_id)
	p.seat_id = -1
	p.flags &= ~NetProtocol.FLAG_SEATED
	p.dirty = true


func _broadcast_seat(room: RoomState, who: int, seat_id: int) -> void:
	for q: RoomPlayer in room.players.values():
		if q.id != who:
			net.s_seat_event.rpc_id(q.id, who, seat_id)


func _pick_spawn(room: RoomState) -> Vector3:
	var spawns: Array = maps[room.map_id]["spawns"]
	if spawns.is_empty():
		return Vector3(0, 0.1, 0)
	var best: Vector3 = spawns[0]
	var best_d := -1.0
	for sp: Vector3 in spawns:
		var nearest := INF
		for q: RoomPlayer in room.players.values():
			nearest = minf(nearest, q.pos.distance_to(sp))
		if nearest > best_d:
			best_d = nearest
			best = sp
	return best


func _join_fail(id: int, code: int) -> void:
	net.s_join_result.rpc_id(id, false, code, NetProtocol.err_text(code), {})


# ------------------------------------------------------------------ invitation codes

func _make_code(room_name: String) -> String:
	var prefix := ""
	for c in room_name.to_upper():
		if c >= "A" and c <= "Z":
			prefix += c
		elif prefix != "":
			break
		if prefix.length() >= 5:
			break
	if prefix.length() < 3:
		prefix = "ROOM"
	var crypto := Crypto.new()
	for attempt in 20:
		var bytes := crypto.generate_random_bytes(5)
		var suffix := ""
		for b in bytes:
			suffix += CODE_ALPHABET[b % CODE_ALPHABET.length()]
		var code := "%s-%s" % [prefix, suffix]
		if not _codes.has(code):
			return code
	return ""


func _code_locked(address: String) -> bool:
	var f: Dictionary = _code_fails.get(address, {})
	return not f.is_empty() and Time.get_ticks_msec() < int(f.get("locked_until", 0))


func _note_code_fail(address: String) -> void:
	var now := Time.get_ticks_msec()
	var f: Dictionary = _code_fails.get(address, {"count": 0, "window_start": now, "locked_until": 0})
	if now - int(f["window_start"]) > CODE_WINDOW_MSEC:
		f["count"] = 0
		f["window_start"] = now
	f["count"] = int(f["count"]) + 1
	if int(f["count"]) >= CODE_FAILS_MAX:
		f["locked_until"] = now + CODE_LOCK_MSEC
		f["count"] = 0
		log_line("code guessing lock-out for %s" % address)
	_code_fails[address] = f


# ------------------------------------------------------------------ rate limiting / sessions

func _session(id: int) -> Session:
	return _sessions.get(id)


func _refill(s: Session) -> void:
	var now := Time.get_ticks_msec()
	var dt := float(now - s.last_refill_msec) / 1000.0
	s.last_refill_msec = now
	s.req_tokens = minf(REQ_CAP, s.req_tokens + REQ_RATE * dt)
	s.state_tokens = minf(STATE_CAP, s.state_tokens + STATE_RATE * dt)


func _allow_request(s: Session) -> bool:
	_refill(s)
	if s.req_tokens < 1.0:
		_strike(s)
		return false
	s.req_tokens -= 1.0
	return true


func _allow_state(s: Session) -> bool:
	_refill(s)
	if s.state_tokens < 1.0:
		_strike(s)
		return false
	s.state_tokens -= 1.0
	return true


func _strike(s: Session) -> void:
	s.strikes += 1
	if s.strikes == 300:
		log_line("kicking %d for flooding" % s.id)
		_kick(s.id, "Disconnected for sending too many requests.")


func _kick(id: int, message: String) -> void:
	net.s_kicked.rpc_id(id, message)
	_kick_later(id)


func _kick_later(id: int) -> void:
	await get_tree().create_timer(0.25).timeout
	net.disconnect_peer(id)


# ------------------------------------------------------------------ tick

func _process(delta: float) -> void:
	_snap_acc += delta
	var step := 1.0 / NetProtocol.SNAPSHOT_RATE
	if _snap_acc >= step:
		_snap_acc = fmod(_snap_acc, step)
		_send_snapshots()
	_slow_acc += delta
	if _slow_acc >= 1.0:
		_slow_acc = 0.0
		_housekeeping()


func _send_snapshots() -> void:
	var now := Time.get_ticks_msec()
	for room: RoomState in _rooms.values():
		if room.players.is_empty():
			continue
		var changed: Array = []
		for p: RoomPlayer in room.players.values():
			if p.dirty or now - p.last_sent_msec > 1000:
				changed.append(p)
		if changed.is_empty():
			continue
		for rcpt: RoomPlayer in room.players.values():
			var list: Array = []
			for p: RoomPlayer in changed:
				if p.id != rcpt.id:
					list.append(p)
			if not list.is_empty():
				net.s_snapshot.rpc_id(rcpt.id, NetProtocol.encode_snapshot(list))
		for p: RoomPlayer in changed:
			p.dirty = false
			p.last_sent_msec = now


func _housekeeping() -> void:
	var now := Time.get_ticks_msec()
	# Peers that connected but never said hello.
	for s: Session in _sessions.values():
		if not s.hello and now - s.connected_msec > 10000:
			log_line("dropping %d: no hello" % s.id)
			net.disconnect_peer(s.id)
	for room: RoomState in _rooms.values().duplicate():
		for p: RoomPlayer in room.players.values():
			if p.emote != -1 and p.emote_until_msec > 0 and now > p.emote_until_msec:
				p.emote = -1
				p.emote_until_msec = 0
		# Players that went silent (frozen client, dead NAT mapping...).
		for p: RoomPlayer in room.players.values().duplicate():
			if float(now - p.last_heard_msec) / 1000.0 > NetProtocol.IDLE_KICK_SEC:
				log_line("%d \"%s\" timed out" % [p.id, p.name])
				_kick(p.id, "Timed out.")
		# Empty rooms close after a configurable delay (their code stops working too).
		if room.players.is_empty() and room.empty_since_msec >= 0 \
				and float(now - room.empty_since_msec) / 1000.0 >= empty_timeout_sec:
			_rooms.erase(room.id)
			if room.code != "":
				_codes.erase(room.code)
			log_line("room %d \"%s\" closed (empty)" % [room.id, room.name])
	# Forget old code-guess records.
	for a in _code_fails.keys():
		var f: Dictionary = _code_fails[a]
		if now > int(f["locked_until"]) and now - int(f["window_start"]) > CODE_WINDOW_MSEC:
			_code_fails.erase(a)


func stats() -> String:
	var players := 0
	for r: RoomState in _rooms.values():
		players += r.count()
	return "%d sessions, %d rooms, %d players" % [_sessions.size(), _rooms.size(), players]
