extends Control
## Server browser: lists public servers, creates public/private servers, joins by code.
## All rules (capacity, codes, names) are enforced by the dedicated server - this screen only asks.
## "Game service" is the dedicated server's address; invitation codes never involve IPs.

var _status: Label
var _list: VBoxContainer
var _count_label: Label
var _host_edit: LineEdit
var _port_edit: LineEdit
var _code_edit: LineEdit
var _toasts: ToastLayer
var _quick_pending := false
var _quick_connect := false      # QUICK PLAY pressed while offline: connect first, then quick-play
var _quick_timer := 0.0
var _quick_btn: Button
var _action_buttons: Array[Button] = []
var _create_overlay: Control
var _name_edit: LineEdit
var _vis_opt: OptionButton
var _map_opt: OptionButton
var _create_err: Label
var _busy := false
var _refresh_t := 0.0


func _ready() -> void:
	theme = UITheme.get_theme()
	AudioManager.stop_ambient()
	AudioManager.play_music("res://assets/audio/music/menu_theme.ogg", "menu")
	_build()
	_toasts = ToastLayer.new()
	add_child(_toasts)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.room_list_received.connect(_on_room_list)
	Net.join_succeeded.connect(_on_join_succeeded)
	Net.join_failed.connect(_on_join_failed)
	if Net.pending_notice != "":
		_toasts.push(Net.pending_notice, Color("#ff6b6b"), 5.0)
		Net.pending_notice = ""
	match Net.state:
		Net.State.ONLINE:
			_on_connected(Net.server_info)
		Net.State.OFFLINE:
			_connect()
		_:
			_set_status("Connecting...", UITheme.MUTED)


func _process(delta: float) -> void:
	if _quick_pending:
		_quick_timer += delta
		if _quick_timer > 8.0:
			_quick_pending = false
			_set_busy(false)
			_toasts.push("Quick Play: the server did not answer. Try again.", Color("#ff6b6b"), 4.0)
	if Net.state != Net.State.ONLINE or _busy:
		return
	_refresh_t += delta
	if _refresh_t >= 5.0:
		_refresh_t = 0.0
		Net.request_room_list()


# ---------------------------------------------------------------- layout

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 600)
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "SERVER BROWSER"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_status = Label.new()
	head.add_child(_status)

	var conn := HBoxContainer.new()
	conn.add_theme_constant_override("separation", 8)
	v.add_child(conn)
	var cl := Label.new()
	cl.text = "Game service"
	cl.add_theme_color_override("font_color", UITheme.MUTED)
	conn.add_child(cl)
	_host_edit = LineEdit.new()
	_host_edit.text = Net.host
	_host_edit.custom_minimum_size.x = 260
	conn.add_child(_host_edit)
	_port_edit = LineEdit.new()
	_port_edit.text = str(Net.port)
	_port_edit.custom_minimum_size.x = 90
	conn.add_child(_port_edit)
	var reconnect := _button(conn, "RECONNECT", _on_reconnect_pressed, false)
	reconnect.custom_minimum_size.x = 150
	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", UITheme.MUTED)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	conn.add_child(_count_label)

	v.add_child(_row(["SERVER", "MAP", "PLAYERS", "TYPE", "STATUS", ""], true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	v.add_child(bottom)
	_quick_btn = _button(bottom, "QUICK PLAY", _on_quick_play_pressed, false)
	_button(bottom, "REFRESH", _on_refresh_pressed, true)
	_button(bottom, "CREATE SERVER", _open_create, true)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Invitation code (e.g. CHILL-K7QM2)"
	_code_edit.custom_minimum_size.x = 300
	_code_edit.max_length = 12
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join_code_pressed())
	bottom.add_child(_code_edit)
	_button(bottom, "JOIN PRIVATE", _on_join_code_pressed, true)
	_button(bottom, "BACK", _on_back_pressed, false)

	_build_create_overlay()
	_show_message_row("Connecting to the game service...")


func _button(parent: Control, text: String, cb: Callable, needs_online: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 46)
	b.pressed.connect(func() -> void:
		AudioManager.play_click()
		cb.call())
	b.mouse_entered.connect(AudioManager.play_hover)
	parent.add_child(b)
	if needs_online:
		_action_buttons.append(b)
		b.disabled = true
	return b


func _row(cols: Array, header: bool) -> HBoxContainer:
	var r := HBoxContainer.new()
	var widths := [0, 190, 100, 90, 90, 120]
	for i in cols.size():
		var l := Label.new()
		l.text = str(cols[i])
		if widths[i] == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
		else:
			l.custom_minimum_size.x = widths[i]
		if header:
			l.add_theme_color_override("font_color", UITheme.MUTED)
			l.add_theme_font_size_override("font_size", 15)
		r.add_child(l)
	return r


func _build_create_overlay() -> void:
	_create_overlay = Control.new()
	_create_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_overlay.visible = false
	add_child(_create_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var t := Label.new()
	t.text = "CREATE SERVER"
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(t)
	var nl := Label.new()
	nl.text = "Server name"
	v.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.max_length = NetProtocol.ROOM_NAME_MAX
	v.add_child(_name_edit)
	var vl := Label.new()
	vl.text = "Visibility"
	v.add_child(vl)
	_vis_opt = OptionButton.new()
	_vis_opt.add_item("Public - listed in the browser")
	_vis_opt.add_item("Private - join with an invitation code")
	v.add_child(_vis_opt)
	var ml := Label.new()
	ml.text = "Map"
	v.add_child(ml)
	_map_opt = OptionButton.new()
	v.add_child(_map_opt)
	_create_err = Label.new()
	_create_err.add_theme_color_override("font_color", Color("#ff6b6b"))
	_create_err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_create_err)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var create := _button(row, "CREATE", _on_create_confirmed, false)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cancel := _button(row, "CANCEL", func() -> void: _create_overlay.visible = false, false)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# ---------------------------------------------------------------- state / helpers

func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _set_online_ui(online: bool) -> void:
	for b in _action_buttons:
		b.disabled = not online or _busy


func _set_busy(b: bool) -> void:
	_busy = b
	if _quick_btn:
		_quick_btn.disabled = b
	_set_online_ui(Net.state == Net.State.ONLINE)


func _show_message_row(text: String) -> void:
	for c in _list.get_children():
		c.queue_free()
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UITheme.MUTED)
	_list.add_child(l)


func _connect() -> void:
	_set_status("Connecting...", UITheme.MUTED)
	_set_online_ui(false)
	_show_message_row("Connecting to the game service..." if not Net.is_websocket_address(Net.host) \
		else "Connecting... a free server may need up to a minute to wake up.")
	Net.connect_to_server(Net.host, Net.port)


func _username_ok() -> bool:
	var err := AppearanceData.validate_username(PlayerProfile.username)
	if err != "":
		_toasts.push("Fix your username first (Character Customization): " + err, Color("#ff6b6b"), 5.0)
		return false
	return true


# ---------------------------------------------------------------- network callbacks

func _on_connected(info: Dictionary) -> void:
	_set_status("Connected: %s" % info.get("server_name", Net.host), UITheme.TEAL)
	_set_busy(false)
	_show_message_row("Loading servers...")
	if _quick_connect:
		_quick_connect = false
		_on_quick_play_pressed()
		return
	Net.request_room_list()


func _on_connection_failed(message: String) -> void:
	if _quick_connect:
		_quick_connect = false
		_set_busy(false)
		_toasts.push("Quick Play could not reach the game service. Check the address and your internet.", Color("#ff6b6b"), 5.0)
	_set_status("Offline", Color("#ff6b6b"))
	_set_online_ui(false)
	_show_message_row(message + "\nCheck the game service address above, then press RECONNECT.")


func _on_disconnected(message: String) -> void:
	_set_status("Offline", Color("#ff6b6b"))
	_set_online_ui(false)
	_show_message_row(message)
	Net.pending_notice = ""


func _on_room_list(rooms: Array) -> void:
	if _quick_pending:
		_quick_pending = false
		_quick_play(rooms)
		return
	_count_label.text = "%d public server%s" % [rooms.size(), "" if rooms.size() == 1 else "s"]
	for c in _list.get_children():
		c.queue_free()
	if rooms.is_empty():
		_show_message_row("No public servers yet. Press CREATE SERVER to start one!")
		return
	for r in rooms:
		var row := _row([r["name"], r["map_name"], "%d/%d" % [r["players"], r["max"]], "Public", r["status"], ""], false)
		var jb := Button.new()
		jb.text = "JOIN"
		jb.custom_minimum_size = Vector2(120, 40)
		jb.disabled = int(r["players"]) >= int(r["max"]) or _busy
		var rid := int(r["id"])
		jb.pressed.connect(func() -> void:
			AudioManager.play_click()
			_join_public(rid))
		row.remove_child(row.get_child(5))
		row.add_child(jb)
		_list.add_child(row)


func _on_join_succeeded(_info: Dictionary) -> void:
	SceneManager.go("lobby_online")


func _on_join_failed(_code: int, message: String) -> void:
	_set_busy(false)
	_create_overlay.visible = false
	_toasts.push(message, Color("#ff6b6b"), 4.5)
	Net.request_room_list()


# ---------------------------------------------------------------- button handlers

## QUICK PLAY: join the fullest public server that still has space; if none exists, create one and join it.
func _on_quick_play_pressed() -> void:
	if _busy or not _username_ok():
		return
	if Net.state != Net.State.ONLINE:
		# Offline (or still connecting): connect first, then quick-play as soon as we are online.
		_quick_connect = true
		_set_busy(true)
		if Net.state == Net.State.OFFLINE:
			_connect()
		return
	_set_busy(true)
	_quick_pending = true
	_quick_timer = 0.0
	Net.request_room_list()


func _quick_play(rooms: Array) -> void:
	var best_id := -1
	var best_players := -1
	for r in rooms:
		var n := int(r["players"])
		if n < int(r["max"]) and n > best_players:
			best_players = n
			best_id = int(r["id"])
	if best_id != -1:
		Net.join_room(best_id)
		return
	var maps: Array = Net.server_info.get("maps", MapRegistry.list())
	if maps.is_empty():
		_on_join_failed(0, "No maps available on this server.")
		return
	Net.create_room("Public Hangout", false, str(maps[0]["id"]))


func _on_refresh_pressed() -> void:
	_refresh_t = 0.0
	Net.request_room_list()


func _on_reconnect_pressed() -> void:
	var p := _port_edit.text.strip_edges()
	if not p.is_valid_int():
		_toasts.push("The port must be a number.", Color("#ff6b6b"))
		return
	GameSettings.set_value("server_host", _host_edit.text.strip_edges())
	GameSettings.set_value("server_port", p.to_int())
	GameSettings.save_settings()
	Net.host = _host_edit.text.strip_edges()
	Net.port = p.to_int()
	Net.disconnect_from_server()
	_connect()


func _join_public(room_id: int) -> void:
	if _busy or not _username_ok():
		return
	_set_busy(true)
	Net.join_room(room_id)


func _on_join_code_pressed() -> void:
	if _busy or not _username_ok():
		return
	var code := _code_edit.text.strip_edges().to_upper()
	if code == "":
		_toasts.push("Enter an invitation code first.", Color("#ff6b6b"))
		return
	_set_busy(true)
	Net.join_with_code(code)


func _open_create() -> void:
	if not _username_ok():
		return
	_map_opt.clear()
	var maps: Array = Net.server_info.get("maps", MapRegistry.list())
	for mp in maps:
		_map_opt.add_item(str(mp["name"]))
		_map_opt.set_item_metadata(_map_opt.item_count - 1, str(mp["id"]))
	_name_edit.text = "%s's Room" % PlayerProfile.username
	_create_err.text = ""
	_create_overlay.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_create_confirmed() -> void:
	var n := _name_edit.text.strip_edges()
	var err := NetProtocol.validate_room_name(n)
	if err != "":
		_create_err.text = err
		return
	if _map_opt.item_count == 0:
		_create_err.text = "No maps available."
		return
	_set_busy(true)
	Net.create_room(n, _vis_opt.selected == 1, str(_map_opt.get_item_metadata(_map_opt.selected)))


func _on_back_pressed() -> void:
	Net.disconnect_from_server()
	SceneManager.go("main_menu")
