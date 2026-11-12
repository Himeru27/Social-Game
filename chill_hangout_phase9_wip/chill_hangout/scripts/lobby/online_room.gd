class_name OnlineRoom
extends Node3D
## The networked hangout room (Phase 5). Spawns your player at the server-chosen spawn point,
## builds remote players from the server's roster, streams your state at 20 Hz, interpolates
## everyone else, and routes sitting through the server. Esc frees the mouse (this does NOT pause
## the world); Esc opens the pause menu (resume / settings / join server / leave server / quit).

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

var player: Player
var room: Node3D
var seats: Array[Seat] = []
var remotes: Dictionary = {}          # peer id -> Player
var hud: GameHUD
var info_panel: RoomInfoPanel
var toasts: ToastLayer
var chat: ChatUI
var emote_menu: EmoteMenu
var player_list: PlayerListPanel
var pause_menu: PauseMenu
var intro: IntroPopup

var _seat_ids: Dictionary = {}        # Seat -> id
var _send_acc := 0.0
var _since_send := 0.0
var _last_pos := Vector3.INF
var _last_yaw := 0.0
var _last_flags := -1
var _last_speed := -1.0
var _sit_pending := false
var _leaving := false
var _status_acc := 0.0


func _ready() -> void:
	if not Net.in_room:
		SceneManager.go("server_browser")
		_leaving = true
		return
	var info := Net.room_info
	room = (load(MapRegistry.scene_path(str(info["map_id"]))) as PackedScene).instantiate()
	add_child(room)
	seats = SeatTable.collect(room)
	for i in seats.size():
		_seat_ids[seats[i]] = i

	toasts = ToastLayer.new()
	add_child(toasts)
	if seats.size() != int(info["seat_count"]):
		toasts.push("Map version mismatch with the server - sitting may not work.", Color("#ff6b6b"), 6.0)

	player = PLAYER_SCENE.instantiate()
	player.net_mode = true
	player.net_id = Net.my_id
	player.initial_appearance = PlayerProfile.appearance
	player.display_name = PlayerProfile.username
	player.position = info["spawn_pos"]
	add_child(player)
	player.set_look_yaw(float(info["spawn_yaw"]))
	player.sit_requested.connect(_on_sit_requested)
	player.seated_changed.connect(_on_seated_changed)

	hud = GameHUD.new()
	add_child(hud)
	hud.bind_player(player)
	info_panel = RoomInfoPanel.new()
	add_child(info_panel)
	info_panel.build(info)

	chat = ChatUI.new()
	add_child(chat)
	chat.opened.connect(_on_chat_opened)
	chat.closed.connect(_on_overlay_closed)
	emote_menu = EmoteMenu.new()
	add_child(emote_menu)
	emote_menu.selected.connect(func(id: int) -> void:
		if not player.play_emote(id):
			toasts.push("You can't do that emote right now (stand still, not crouching or seated).", UITheme.MUTED, 2.5))
	emote_menu.closed.connect(_on_overlay_closed)
	player_list = PlayerListPanel.new()
	add_child(player_list)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.resumed.connect(_on_overlay_closed)
	pause_menu.join_requested.connect(join_another_server)
	pause_menu.leave_requested.connect(leave_server)
	pause_menu.quit_requested.connect(quit_game)
	intro = IntroPopup.new()
	add_child(intro)
	intro.closed.connect(_on_overlay_closed)
	player.emote_changed.connect(func(id: int) -> void: Net.send_emote(id))

	for id in Net.room_players:
		_spawn_remote(Net.room_players[id])
	_update_count()
	chat.add_system("Welcome to %s. Press %s to chat, %s for emotes." % [info["room_name"], GameSettings.key_label("chat"), GameSettings.key_label("emote_menu")])

	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Net.snapshot_received.connect(_on_snapshot)
	Net.seat_result.connect(_on_seat_result)
	Net.seat_event.connect(_on_seat_event)
	Net.position_corrected.connect(_on_corrected)
	Net.disconnected.connect(_on_disconnected)
	Net.chat_received.connect(_on_chat_received)
	Net.emote_event.connect(_on_emote_event)
	Net.notice.connect(func(m: String) -> void: toasts.push(m, Color("#ff6b6b"), 3.0))
	Net.host_changed.connect(func(_h: int) -> void: _refresh_list())
	Net.kicked.connect(func(m: String) -> void: toasts.push(m, Color("#ff6b6b"), 6.0))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioManager.play_music("res://assets/audio/music/lobby_theme.ogg", "lobby")
	AudioManager.start_ambient()
	# First time ever in a server: show the controls card (the player closes it when done reading).
	if not GameSettings.has_seen(IntroPopup.FLAG):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.input_enabled = false
		intro.open()
	if str(info["code"]) != "":
		toasts.push("Private server created. Share the code %s with friends (COPY button, top right)." % info["code"], UITheme.TEAL, 7.0)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- outgoing state

func _physics_process(delta: float) -> void:
	if player == null or not Net.in_room:
		return
	_status_acc += delta
	if _status_acc >= 1.0:
		_status_acc = 0.0
		hud.set_connection(Net.get_rtt_ms())
	var step := 1.0 / NetProtocol.SEND_RATE
	_send_acc += delta
	if _send_acc < step:
		return
	_send_acc = fmod(_send_acc, step)
	_since_send += step
	var pos := player.global_position
	var yaw := player.model.rotation.y
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var flags := 0
	if player.crouching:
		flags |= NetProtocol.FLAG_CROUCH
	if player.sprinting:
		flags |= NetProtocol.FLAG_SPRINT
	if player.seated:
		flags |= NetProtocol.FLAG_SEATED
	var changed := pos.distance_squared_to(_last_pos) > 0.00001 or absf(angle_difference(yaw, _last_yaw)) > 0.01 \
		or flags != _last_flags or absf(speed - _last_speed) > 0.05
	if changed or _since_send >= NetProtocol.KEEPALIVE_SEC:
		Net.send_state(pos, yaw, speed, flags)
		_since_send = 0.0
		_last_pos = pos
		_last_yaw = yaw
		_last_flags = flags
		_last_speed = speed


# ---------------------------------------------------------------- remote players

func _spawn_remote(info: Dictionary) -> void:
	var id := int(info["id"])
	if id == Net.my_id or remotes.has(id):
		return
	var p: Player = PLAYER_SCENE.instantiate()
	p.is_local = false
	p.net_id = id
	p.display_name = str(info["name"])
	p.initial_appearance = AppearanceData.sanitize(info["appearance"])
	p.position = info["pos"]
	p.remote_buffer = SnapshotBuffer.new()
	p.remote_buffer.push(Time.get_ticks_msec() / 1000.0 - 1.0, info["pos"], float(info["yaw"]), 0.0, int(info["flags"]))
	add_child(p)
	p.model.rotation.y = float(info["yaw"])
	remotes[id] = p
	var sid := int(info.get("seat_id", -1))
	if sid >= 0 and sid < seats.size():
		p.remote_sit(seats[sid])
	elif int(info.get("emote", -1)) >= 0:
		p.remote_emote(int(info["emote"]))


func _update_count() -> void:
	info_panel.set_count(remotes.size() + 1)
	_refresh_list()


func _refresh_list() -> void:
	if player_list == null:
		return
	var host_id := int(Net.room_info.get("host_id", 0))
	var entries: Array = [{"name": PlayerProfile.username, "you": true, "host": host_id == Net.my_id}]
	for id in remotes:
		entries.append({"name": (remotes[id] as Player).display_name, "you": false, "host": host_id == int(id)})
	player_list.refresh(entries, int(Net.room_info.get("max", NetProtocol.MAX_PLAYERS_PER_ROOM)))


func _on_player_joined(info: Dictionary) -> void:
	_spawn_remote(info)
	chat.add_system("%s joined" % info["name"])
	_update_count()


func _on_player_left(peer_id: int, username: String, _reason: String) -> void:
	if remotes.has(peer_id):
		(remotes[peer_id] as Player).queue_free()
		remotes.erase(peer_id)
	chat.add_system("%s left" % username)
	_update_count()


func _on_snapshot(entries: Array) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for e in entries:
		var p: Player = remotes.get(int(e["id"]))
		if p != null and p.remote_buffer != null:
			p.remote_buffer.push(now, e["pos"], e["yaw"], e["speed"], e["flags"])


# ---------------------------------------------------------------- sitting (server decides)

func _on_sit_requested(seat: Seat) -> void:
	if _sit_pending or not _seat_ids.has(seat):
		return
	_sit_pending = true
	Net.request_sit(_seat_ids[seat])
	await get_tree().create_timer(2.0).timeout
	_sit_pending = false


func _on_seat_result(seat_id: int, ok: bool, message: String) -> void:
	_sit_pending = false
	if not ok:
		toasts.push(message, Color("#ff6b6b"), 2.5)
		return
	if seat_id >= 0 and seat_id < seats.size() and not player.seated:
		seats[seat_id].occupant = null   # the server says it is free - trust it over our mirror
		player.sit(seats[seat_id], true)


func _on_seated_changed(is_seated: bool) -> void:
	if not is_seated:
		Net.notify_stand()


func _on_seat_event(peer_id: int, seat_id: int) -> void:
	var p: Player = remotes.get(peer_id)
	if p == null:
		return
	if seat_id >= 0 and seat_id < seats.size():
		seats[seat_id].occupant = null
		p.remote_sit(seats[seat_id])
	else:
		p.remote_stand()


# ---------------------------------------------------------------- chat / emotes / overlays

func _tag_for(peer_id: int) -> NameTag:
	if peer_id == Net.my_id:
		return player.name_tag
	var p: Player = remotes.get(peer_id)
	return p.name_tag if p != null else null


func _on_chat_received(peer_id: int, username: String, text: String) -> void:
	chat.add_message(username, text, peer_id == Net.my_id)
	var tag := _tag_for(peer_id)
	if tag != null:
		tag.show_message(text)


func _on_emote_event(peer_id: int, emote_id: int) -> void:
	if peer_id == Net.my_id:
		if emote_id == -1:
			player.cancel_emote()      # the server refused or ended our emote
		return
	var p: Player = remotes.get(peer_id)
	if p != null:
		p.remote_emote(emote_id)


func _overlay_open() -> bool:
	return chat.is_open or emote_menu.is_open or pause_menu.is_open or intro.is_open


func _on_chat_opened() -> void:
	emote_menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false


func _on_overlay_closed() -> void:
	if _leaving or _overlay_open():
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.input_enabled = true


func _on_corrected(pos: Vector3, yaw: float) -> void:
	player.server_correct(pos, yaw)


# ---------------------------------------------------------------- leaving / errors

func _on_disconnected(message: String) -> void:
	if _leaving:
		return
	_leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false
	pause_menu.close()
	intro.close()
	toasts.push(message, Color("#ff6b6b"), 5.0)
	await get_tree().create_timer(1.5).timeout
	SceneManager.go("server_browser")


## Pause menu > JOIN SERVER: fully disconnect, then open a fresh browser connection.
func join_another_server() -> void:
	if _leaving:
		return
	_leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.disconnect_from_server()
	SceneManager.go("server_browser")


## Pause menu > QUIT GAME: leave the server cleanly, then close the application.
func quit_game() -> void:
	_leaving = true
	Net.disconnect_from_server()
	get_tree().quit()


## Pause menu > LEAVE SERVER: leave the room, go back to the server selection screen.
func leave_server() -> void:
	if _leaving:
		return
	_leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave_room()
	SceneManager.go("server_browser")


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("chat") and not _overlay_open():
		chat.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("emote_menu") and not _overlay_open():
		emote_menu.open()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.input_enabled = false
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("player_list"):
		player_list.set_shown(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("player_list"):
		player_list.set_shown(false)
		return
	if event.is_action_pressed("pause") and not _overlay_open():
		chat.close()
		emote_menu.close()
		player_list.set_shown(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.input_enabled = false
		pause_menu.open()
		get_viewport().set_input_as_handled()
