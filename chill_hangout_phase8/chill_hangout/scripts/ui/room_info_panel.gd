class_name RoomInfoPanel
extends CanvasLayer
## Top-right panel in an online room: server name, invitation code (+ COPY), PLAYERS ONLINE n/10,
## ping. The code is shown to every member of a private room so they can invite friends.

var _players_l: Label
var _ping_l: Label
var _copy: Button
var _code := ""
var _max := NetProtocol.MAX_PLAYERS_PER_ROOM
var _t := 0.0


func _ready() -> void:
	layer = 11


func build(info: Dictionary) -> void:
	_code = str(info.get("code", ""))
	_max = int(info.get("max", _max))
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -336
	panel.offset_right = -16
	panel.offset_top = 16
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var title := Label.new()
	title.text = str(info.get("room_name", "Server"))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.clip_text = true
	v.add_child(title)

	var sub := Label.new()
	sub.text = "%s  |  %s" % [str(info.get("map_name", "")), "PRIVATE" if info.get("private", false) else "PUBLIC"]
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", UITheme.MUTED)
	v.add_child(sub)

	if _code != "":
		var row := HBoxContainer.new()
		v.add_child(row)
		var code_l := Label.new()
		code_l.text = "CODE: " + _code
		code_l.add_theme_color_override("font_color", UITheme.TEAL)
		code_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(code_l)
		_copy = Button.new()
		_copy.text = "COPY"
		_copy.add_theme_font_size_override("font_size", 14)
		_copy.pressed.connect(_on_copy)
		row.add_child(_copy)

	_players_l = Label.new()
	v.add_child(_players_l)
	_ping_l = Label.new()
	_ping_l.add_theme_font_size_override("font_size", 14)
	_ping_l.add_theme_color_override("font_color", UITheme.MUTED)
	v.add_child(_ping_l)
	set_count(1)


func set_count(n: int) -> void:
	if _players_l:
		_players_l.text = "PLAYERS ONLINE: %d/%d" % [n, _max]


func _on_copy() -> void:
	AudioManager.play_click()
	DisplayServer.clipboard_set(_code)
	_copy.text = "COPIED!"
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(_copy):
		_copy.text = "COPY"


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.5 and _ping_l:
		_t = 0.0
		var rtt := Net.get_rtt_ms()
		_ping_l.text = "Ping: %d ms" % rtt if rtt >= 0 else "Ping: n/a"
