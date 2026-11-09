class_name ServerBrowser
extends Control
## Server browser: lists public servers, creates public/private servers, joins by code.
## All rules (capacity, codes, names) are enforced by the dedicated server - this screen only asks.
## "Game service" is the dedicated server's address; invitation codes never involve IPs.
## It is shown inside the main menu (MainMenu creates it when PLAY is pressed) and emits
## back_requested when BACK is pressed.

signal back_requested

const COL_W := 600.0
## Column widths: SERVER (0 = fills the rest), MAP, PLAYERS, STATUS, JOIN button.
const COL_WIDTHS := [0, 100, 76, 90, 100]

var _status: Label
var _list: VBoxContainer
var _count_label: Label
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
		_toasts.push(Net.pending_notice, MenuStyle.WARN, 5.0)
		Net.pending_notice = ""
	match Net.state:
		Net.State.ONLINE:
			_on_connected(Net.server_info)
		Net.State.OFFLINE:
			_connect()
		_:
			_set_status("Connecting...", MenuStyle.WHITE)


func _process(delta: float) -> void:
	if _quick_pending:
		_quick_timer += delta
		if _quick_timer > 8.0:
			_quick_pending = false
			_set_busy(false)
			_toasts.push("Quick Play: the server did not answer. Try again.", MenuStyle.WARN, 4.0)
	if Net.state != Net.State.ONLINE or _busy:
		return
	_refresh_t += delta
	if _refresh_t >= 5.0:
		_refresh_t = 0.0
		Net.request_room_list()


# ---------------------------------------------------------------- layout

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)

	var col := VBoxContainer.new()
	col.custom_minimum_size.x = COL_W
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# Title, same look as the main menu logo.
	var logo := HBoxContainer.new()
	logo.add_theme_constant_override("separation", 16)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_child(MenuStyle.title_word("SERVER", MenuStyle.WHITE, 64))
	logo.add_child(MenuStyle.title_word("BROWSER", MenuStyle.ORANGE, 64))
	col.add_child(logo)

	# Status line + reconnect.
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 12)
	col.add_child(info)
	_status = _outlined_label("", 18)
	info.add_child(_status)
	_count_label = _outlined_label("", 18)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_child(_count_label)
	var reconnect := _button(info, "RECONNECT", _on_reconnect_pressed, false, 18)
	reconnect.size_flags_horizontal = Control.SIZE_SHRINK_END
	reconnect.custom_minimum_size = Vector2(150, 38)

	# Column headers (same margins as the row strips so they line up).
	var head_margin := MarginContainer.new()
	head_margin.add_theme_constant_override("margin_left", 34)
	head_margin.add_theme_constant_override("margin_right", 20)
	head_margin.add_child(_row(["SERVER", "MAP", "PLAYERS", "STATUS", ""], true))
	col.add_child(head_margin)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	# Actions.
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	col.add_child(row1)
	_quick_btn = _button(row1, "QUICK PLAY", _on_quick_play_pressed, false)
	_button(row1, "CREATE SERVER", _open_create, true)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	col.add_child(row2)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Invitation code (CHILL-K7QM2)"
	_code_edit.custom_minimum_size = Vector2(0, 50)
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.max_length = 12
	_code_edit.add_theme_font_size_override("font_size", 20)
	MenuStyle.style_line_edit(_code_edit)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join_code_pressed())
	row2.add_child(_code_edit)
	var join_priv := _button(row2, "JOIN PRIVATE", _on_join_code_pressed, true)
	join_priv.size_flags_horizontal = Control.SIZE_SHRINK_END
	join_priv.custom_minimum_size = Vector2(220, 50)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 10)
	col.add_child(row3)
	_button(row3, "REFRESH", _on_refresh_pressed, true)
	_button(row3, "BACK", _on_back_pressed, false)

	_build_create_overlay()
	_show_message_row("Connecting to the game service...")


func _outlined_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	MenuStyle.outlined(l, size)
	return l


func _button(parent: Control, text: String, cb: Callable, needs_online: bool, font_size: int = 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.style_button(b, font_size)
	b.pressed.connect(func() -> void:
		AudioManager.play_click()
		cb.call())
	b.mouse_entered.connect(AudioManager.play_hover)
	parent.add_child(b)
	if needs_online:
		_action_buttons.append(b)
		b.disabled = true
	return b


## One table row of cells (labels). Header rows are outlined white, data rows plain white.
func _row(cols: Array, header: bool) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	for i in cols.size():
		var l := Label.new()
		l.text = str(cols[i])
		if header:
			MenuStyle.outlined(l, 15, Color(1, 1, 1, 0.85), 5)
		else:
			l.add_theme_font_size_override("font_size", 17)
			l.add_theme_color_override("font_color", MenuStyle.WHITE)
		if COL_WIDTHS[i] == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
		else:
			l.custom_minimum_size.x = COL_WIDTHS[i]
		r.add_child(l)
	return r


## Wraps a row in a slanted dark strip, like a menu button.
func _strip_panel(content: Control) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", MenuStyle.strip(Color(MenuStyle.INK, 0.92), Color(1, 1, 1, 0.55), 1, Vector4(34, 20, 6, 6)))
	pc.add_child(content)
	return pc


func _build_create_overlay() -> void:
	_create_overlay = Control.new()
	_create_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_overlay.visible = false
	add_child(_create_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.1, 0.16, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var sb := MenuStyle.flat(Color(MenuStyle.INK, 0.97), MenuStyle.ORANGE, 0, 0)
	sb.border_width_top = 8
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var t := Label.new()
	t.text = "CREATE SERVER"
	t.add_theme_font_override("font", MenuStyle.FONT)
	t.add_theme_font_size_override("font_size", 38)
	t.add_theme_color_override("font_color", MenuStyle.ORANGE)
	v.add_child(t)
	var nl := Label.new()
	nl.text = "Server name"
	v.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.max_length = NetProtocol.ROOM_NAME_MAX
	MenuStyle.style_line_edit(_name_edit)
	v.add_child(_name_edit)
	var vl := Label.new()
	vl.text = "Visibility"
	v.add_child(vl)
	_vis_opt = OptionButton.new()
	_vis_opt.add_item("Public - listed in the browser")
	_vis_opt.add_item("Private - join with an invitation code")
	MenuStyle.style_option(_vis_opt)
	v.add_child(_vis_opt)
	var ml := Label.new()
	ml.text = "Map"
	v.add_child(ml)
	_map_opt = OptionButton.new()
	MenuStyle.style_option(_map_opt)
	v.add_child(_map_opt)
	_create_err = Label.new()
	_create_err.add_theme_color_override("font_color", MenuStyle.WARN)
	_create_err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_create_err)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var create := _button(row, "CREATE", _on_create_confirmed, false)
	create.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cancel := _button(row, "CANCEL", func() -> void: _create_overlay.visible = false, false)
	cancel.alignment = HORIZONTAL_ALIGNMENT_CENTER


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
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 480
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", MenuStyle.WHITE)
	_list.add_child(_strip_panel(l))


func _connect() -> void:
	_set_status("Connecting...", MenuStyle.WHITE)
	_set_online_ui(false)
	_show_message_row("Connecting to the game service..." if not Net.is_websocket_address(Net.host) \
		else "Connecting... a free server may need up to a minute to wake up.")
	Net.connect_to_server(Net.host, Net.port)


func _username_ok() -> bool:
	var err := AppearanceData.validate_username(PlayerProfile.username)
	if err != "":
		_toasts.push("Fix your username first (Character Customization): " + err, MenuStyle.WARN, 5.0)
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
		_toasts.push("Quick Play could not reach the game service. Check the address and your internet.", MenuStyle.WARN, 5.0)
	_set_status("Offline", MenuStyle.WARN)
	_set_online_ui(false)
	_show_message_row(message + "\nCheck the game service address above, then press RECONNECT.")


func _on_disconnected(message: String) -> void:
	_set_status("Offline", MenuStyle.WARN)
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
		var row := _row([r["name"], r["map_name"], "%d/%d" % [r["players"], r["max"]], r["status"]], false)
		var jb := Button.new()
		jb.text = "JOIN"
		jb.custom_minimum_size = Vector2(COL_WIDTHS[4], 36)
		MenuStyle.style_button(jb, 20, Vector4(14, 10, 2, 2))
		jb.alignment = HORIZONTAL_ALIGNMENT_CENTER
		jb.disabled = int(r["players"]) >= int(r["max"]) or _busy
		var rid := int(r["id"])
		jb.pressed.connect(func() -> void:
			AudioManager.play_click()
			_join_public(rid))
		jb.mouse_entered.connect(AudioManager.play_hover)
		row.add_child(jb)
		_list.add_child(_strip_panel(row))


func _on_join_succeeded(_info: Dictionary) -> void:
	SceneManager.go("lobby_online")


func _on_join_failed(_code: int, message: String) -> void:
	_set_busy(false)
	_create_overlay.visible = false
	_toasts.push(message, MenuStyle.WARN, 4.5)
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
		_toasts.push("Enter an invitation code first.", MenuStyle.WARN)
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
	back_requested.emit()
