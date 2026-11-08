extends Node
## Autoload "Net": the ONE place that owns the multiplayer connection and every RPC.
## The same script runs on clients and on the dedicated server (RPC signatures must match), so:
##  - c_* (client -> server) handlers do nothing unless we are the server.
##  - s_* (server -> client) are authority-only: Godot rejects them from any other peer.
## Server logic lives in GameServer; client code uses the signals + helpers below.

signal connected(server_info: Dictionary)
signal connection_failed(message: String)
signal disconnected(message: String)          ## lost / closed after having been connected
signal room_list_received(rooms: Array)
signal join_succeeded(info: Dictionary)
signal join_failed(code: int, message: String)
signal player_joined(info: Dictionary)
signal player_left(peer_id: int, username: String, reason: String)
signal chat_received(peer_id: int, username: String, text: String)
signal emote_event(peer_id: int, emote_id: int)
signal notice(message: String)
signal host_changed(host_id: int)
signal snapshot_received(entries: Array)
signal seat_result(seat_id: int, ok: bool, message: String)
signal seat_event(peer_id: int, seat_id: int)
signal position_corrected(pos: Vector3, yaw: float)
signal kicked(message: String)

enum State { OFFLINE, CONNECTING, ONLINE }

var state := State.OFFLINE
var my_id := 0
var server_info: Dictionary = {}
var in_room := false
var room_info: Dictionary = {}
var room_players: Dictionary = {}     # peer id -> info dict (kept up to date even between scenes)
var room_seats: Dictionary = {}       # seat id -> peer id
var pending_notice := ""              ## shown once by the next menu screen (e.g. "Connection lost")
var host := NetProtocol.DEFAULT_HOST
var port := NetProtocol.DEFAULT_PORT
var server: GameServer = null         # only set on the dedicated server

var _connect_started := 0.0
var _connect_timeout := NetProtocol.CONNECT_TIMEOUT_SEC
var _ws_server := false               # server side: listening over WebSocket instead of ENet/UDP
var _closing := false


func _ready() -> void:
	var api := multiplayer as SceneMultiplayer
	if api:
		api.server_relay = false      # clients can never message each other through the server
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	host = str(GameSettings.get_value("server_host"))
	port = int(GameSettings.get_value("server_port"))


func _process(_delta: float) -> void:
	if state == State.CONNECTING and Time.get_ticks_msec() / 1000.0 - _connect_started > _connect_timeout:
		_fail_connect("Could not reach the game service (timed out).")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and server == null and is_inside_tree():
		disconnect_from_server()


func _exit_tree() -> void:
	if server == null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()


# =============================================================================== CLIENT API

func connect_to_server(p_host: String, p_port: int) -> void:
	if state != State.OFFLINE:
		disconnect_from_server()
	host = p_host.strip_edges()
	port = p_port
	var is_ws := is_websocket_address(host)
	if host == "" or (not is_ws and (port < 1 or port > 65535)):
		connection_failed.emit("Invalid game service address.")
		return
	var peer: MultiplayerPeer
	var err: Error
	if is_ws:
		# ws:// or wss:// URL (free web hosting). The port comes from the URL, not the port field.
		var ws := WebSocketMultiplayerPeer.new()
		err = ws.create_client(host)
		peer = ws
		_connect_timeout = 75.0       # free hosts sleep when idle and need up to ~1 minute to wake
	else:
		var enet := ENetMultiplayerPeer.new()
		err = enet.create_client(host, port)
		peer = enet
		_connect_timeout = NetProtocol.CONNECT_TIMEOUT_SEC
	if err != OK:
		connection_failed.emit("Could not start the connection (error %d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	state = State.CONNECTING
	_connect_started = Time.get_ticks_msec() / 1000.0


static func is_websocket_address(addr: String) -> bool:
	return addr.begins_with("ws://") or addr.begins_with("wss://")


func disconnect_from_server() -> void:
	if server != null or not is_inside_tree():
		return
	var was_in_room := in_room
	_reset_room()
	if multiplayer.multiplayer_peer != null:
		if was_in_room and state == State.ONLINE:
			c_leave_room.rpc_id(1)
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	state = State.OFFLINE
	my_id = 0


func request_room_list() -> void:
	if state == State.ONLINE:
		c_list_rooms.rpc_id(1)


func create_room(room_name: String, is_private: bool, map_id: String) -> void:
	if state == State.ONLINE:
		c_create_room.rpc_id(1, room_name, is_private, map_id, PlayerProfile.username, PlayerProfile.appearance)


func join_room(room_id: int) -> void:
	if state == State.ONLINE:
		c_join_room.rpc_id(1, room_id, PlayerProfile.username, PlayerProfile.appearance)


func join_with_code(code: String) -> void:
	if state == State.ONLINE:
		c_join_code.rpc_id(1, code, PlayerProfile.username, PlayerProfile.appearance)


func leave_room() -> void:
	if state == State.ONLINE and in_room:
		c_leave_room.rpc_id(1)
	_reset_room()


func send_state(pos: Vector3, yaw: float, speed: float, flags: int) -> void:
	if state == State.ONLINE and in_room:
		c_state.rpc_id(1, NetProtocol.encode_client_state(pos, yaw, speed, flags))


func request_sit(seat_id: int) -> void:
	if state == State.ONLINE and in_room:
		c_sit.rpc_id(1, seat_id)


func send_chat(text: String) -> void:
	if state == State.ONLINE and in_room:
		c_chat.rpc_id(1, text)


## emote_id -1 cancels the current emote.
func send_emote(emote_id: int) -> void:
	if state == State.ONLINE and in_room:
		c_emote.rpc_id(1, emote_id)


func notify_stand() -> void:
	if state == State.ONLINE and in_room:
		c_stand.rpc_id(1)


## Round-trip time to the server in ms (0 if unknown).
func get_rtt_ms() -> int:
	if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and state == State.ONLINE:
		return -1      # WebSocket has no RTT statistic
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or state != State.ONLINE:
		return 0
	var pp := peer.get_peer(1)
	return int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if pp else 0


func _reset_room() -> void:
	in_room = false
	room_info = {}
	room_players = {}
	room_seats = {}


func _fail_connect(message: String) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	state = State.OFFLINE
	connection_failed.emit(message)


func _on_connected_to_server() -> void:
	my_id = multiplayer.get_unique_id()
	c_hello.rpc_id(1, NetProtocol.PROTOCOL_VERSION)


func _on_connection_failed() -> void:
	_fail_connect("Could not connect to the game service.")


func _on_server_disconnected() -> void:
	var msg := pending_notice if pending_notice != "" else "Connection to the server was lost."
	_reset_room()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	state = State.OFFLINE
	my_id = 0
	pending_notice = msg
	disconnected.emit(msg)


# =============================================================================== SERVER HOSTING

## Starts listening. Called by the dedicated server scene only.
func host_dedicated(gs: GameServer, p_port: int, max_clients: int, bind_ip: String = "*", websocket := false) -> Error:
	var peer: MultiplayerPeer
	var err: Error
	_ws_server = websocket
	if websocket:
		# Plain ws:// behind the host's TLS proxy (Render etc. give players a wss:// URL).
		var ws := WebSocketMultiplayerPeer.new()
		err = ws.create_server(p_port, bind_ip if bind_ip != "" else "*")
		peer = ws
	else:
		var enet := ENetMultiplayerPeer.new()
		if bind_ip != "*" and bind_ip != "":
			enet.set_bind_ip(bind_ip)
		err = enet.create_server(p_port, max_clients)
		peer = enet
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	server = gs
	state = State.ONLINE
	my_id = 1
	return OK


func get_peer_address(id: int) -> String:
	if _ws_server:
		return "ws-%d" % id      # behind a proxy every client shares one IP, so limits are per connection
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null:
		return ""
	var pp := peer.get_peer(id)
	return pp.get_remote_address() if pp else ""


func disconnect_peer(id: int) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null and multiplayer.get_peers().has(id):
		peer.disconnect_peer(id)


## Tells every client we are going down, then closes. Await it before quitting.
func shutdown_server() -> void:
	if server == null or _closing:
		return
	_closing = true
	for id in multiplayer.get_peers():
		s_server_shutdown.rpc_id(id)
	await get_tree().create_timer(0.4).timeout
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()


func _on_peer_connected(id: int) -> void:
	if server == null:
		return
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var pp := peer.get_peer(id) if peer else null
	if pp:
		pp.set_timeout(32, 3000, 12000)   # dead peers are detected within ~12 s
	server.on_peer_connected(id)


func _on_peer_disconnected(id: int) -> void:
	if server != null:
		server.on_peer_disconnected(id)


# =============================================================================== RPC: client -> server

@rpc("any_peer", "call_remote", "reliable")
func c_hello(version: int) -> void:
	if server != null:
		server.on_hello(multiplayer.get_remote_sender_id(), version)


@rpc("any_peer", "call_remote", "reliable")
func c_list_rooms() -> void:
	if server != null:
		server.on_list_rooms(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func c_create_room(room_name: String, is_private: bool, map_id: String, username: String, appearance: Dictionary) -> void:
	if server != null:
		server.on_create_room(multiplayer.get_remote_sender_id(), room_name, is_private, map_id, username, appearance)


@rpc("any_peer", "call_remote", "reliable")
func c_join_room(room_id: int, username: String, appearance: Dictionary) -> void:
	if server != null:
		server.on_join_room(multiplayer.get_remote_sender_id(), room_id, username, appearance)


@rpc("any_peer", "call_remote", "reliable")
func c_join_code(code: String, username: String, appearance: Dictionary) -> void:
	if server != null:
		server.on_join_code(multiplayer.get_remote_sender_id(), code, username, appearance)


@rpc("any_peer", "call_remote", "reliable")
func c_leave_room() -> void:
	if server != null:
		server.on_leave_room(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func c_state(packet: PackedByteArray) -> void:
	if server != null:
		server.on_state(multiplayer.get_remote_sender_id(), packet)


@rpc("any_peer", "call_remote", "reliable")
func c_chat(text: String) -> void:
	if server != null:
		server.on_chat(multiplayer.get_remote_sender_id(), text)


@rpc("any_peer", "call_remote", "reliable")
func c_emote(emote_id: int) -> void:
	if server != null:
		server.on_emote(multiplayer.get_remote_sender_id(), emote_id)


@rpc("any_peer", "call_remote", "reliable")
func c_sit(seat_id: int) -> void:
	if server != null:
		server.on_sit(multiplayer.get_remote_sender_id(), seat_id)


@rpc("any_peer", "call_remote", "reliable")
func c_stand() -> void:
	if server != null:
		server.on_stand(multiplayer.get_remote_sender_id())


# =============================================================================== RPC: server -> client

@rpc("authority", "call_remote", "reliable")
func s_hello_result(ok: bool, message: String, info: Dictionary) -> void:
	if ok:
		server_info = info
		state = State.ONLINE
		connected.emit(info)
	else:
		_fail_connect(message)


@rpc("authority", "call_remote", "reliable")
func s_room_list(rooms: Array) -> void:
	room_list_received.emit(rooms)


@rpc("authority", "call_remote", "reliable")
func s_join_result(ok: bool, code: int, message: String, info: Dictionary) -> void:
	if not ok:
		join_failed.emit(code, message)
		return
	room_info = info
	room_players = {}
	room_seats = {}
	for p in info["players"]:
		room_players[int(p["id"])] = p
		if int(p["seat_id"]) >= 0:
			room_seats[int(p["seat_id"])] = int(p["id"])
	in_room = true
	join_succeeded.emit(info)


@rpc("authority", "call_remote", "reliable")
func s_player_joined(info: Dictionary) -> void:
	if not in_room:
		return
	room_players[int(info["id"])] = info
	player_joined.emit(info)


@rpc("authority", "call_remote", "reliable")
func s_player_left(peer_id: int, username: String, reason: String, host_id: int) -> void:
	if not in_room:
		return
	room_players.erase(peer_id)
	if int(room_info.get("host_id", 0)) != host_id:
		room_info["host_id"] = host_id
		host_changed.emit(host_id)
	for sid in room_seats.keys():
		if room_seats[sid] == peer_id:
			room_seats.erase(sid)
	player_left.emit(peer_id, username, reason)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func s_snapshot(packet: PackedByteArray) -> void:
	if not in_room:
		return
	var entries := NetProtocol.decode_snapshot(packet)
	for e in entries:
		var id := int(e["id"])
		if room_players.has(id):
			var rec: Dictionary = room_players[id]
			rec["pos"] = e["pos"]
			rec["yaw"] = e["yaw"]
			rec["flags"] = e["flags"]
	snapshot_received.emit(entries)


@rpc("authority", "call_remote", "reliable")
func s_seat_result(seat_id: int, ok: bool, message: String) -> void:
	if ok:
		room_seats[seat_id] = my_id
	seat_result.emit(seat_id, ok, message)


@rpc("authority", "call_remote", "reliable")
func s_seat_event(peer_id: int, seat_id: int) -> void:
	if not in_room:
		return
	for sid in room_seats.keys():
		if room_seats[sid] == peer_id:
			room_seats.erase(sid)
	if seat_id >= 0:
		room_seats[seat_id] = peer_id
	if room_players.has(peer_id):
		room_players[peer_id]["seat_id"] = seat_id
	seat_event.emit(peer_id, seat_id)


@rpc("authority", "call_remote", "reliable")
func s_chat(peer_id: int, username: String, text: String) -> void:
	if in_room:
		chat_received.emit(peer_id, username, text)


@rpc("authority", "call_remote", "reliable")
func s_emote(peer_id: int, emote_id: int) -> void:
	if not in_room:
		return
	if room_players.has(peer_id):
		room_players[peer_id]["emote"] = emote_id
	emote_event.emit(peer_id, emote_id)


@rpc("authority", "call_remote", "reliable")
func s_notice(message: String) -> void:
	notice.emit(message)


@rpc("authority", "call_remote", "reliable")
func s_correct(pos: Vector3, yaw: float) -> void:
	position_corrected.emit(pos, yaw)


@rpc("authority", "call_remote", "reliable")
func s_kicked(message: String) -> void:
	pending_notice = message
	kicked.emit(message)


@rpc("authority", "call_remote", "reliable")
func s_server_shutdown() -> void:
	pending_notice = "The server is shutting down."
