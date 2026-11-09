class_name RoomInfoPanel
extends CanvasLayer
## Top-right panel in an online room: server name, invitation code (+ COPY), PLAYERS ONLINE n/10,
## ping. The code is shown to every member of a private room so they can invite friends.
## Styled like the server browser rows: slanted dark strips, Anton headings.

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
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(330, 0)
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.offset_left = -366      # the slant overhangs a little, so keep clear of the edge
	col.offset_right = -36
	col.offset_top = 16
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)

	var title := Label.new()
	title.text = str(info.get("room_name", "Server"))
	title.add_theme_font_override("font", MenuStyle.FONT)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", MenuStyle.ORANGE)
	title.clip_text = true
	col.add_child(_strip(title))

	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 4)
	var sub := Label.new()
	sub.text = "%s  |  %s" % [str(info.get("map_name", "")), "PRIVATE" if info.get("private", false) else "PUBLIC"]
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	detail.add_child(sub)
	if _code != "":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		detail.add_child(row)
		var code_l := Label.new()
		code_l.text = "CODE: " + _code
		code_l.add_theme_font_override("font", MenuStyle.FONT)
		code_l.add_theme_font_size_override("font_size", 20)
		code_l.add_theme_color_override("font_color", MenuStyle.WHITE)
		code_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(code_l)
		_copy = Button.new()
		_copy.text = "COPY"
		_copy.custom_minimum_size = Vector2(84, 32)
		_copy.alignment = HORIZONTAL_ALIGNMENT_CENTER
		MenuStyle.style_button(_copy, 16, Vector4(18, 10, 2, 2))
		_copy.pressed.connect(_on_copy)
		row.add_child(_copy)
	col.add_child(_strip(detail))

	_players_l = Label.new()
	_players_l.add_theme_font_override("font", MenuStyle.FONT)
	_players_l.add_theme_font_size_override("font_size", 24)
	_players_l.add_theme_color_override("font_color", MenuStyle.WHITE)
	col.add_child(_strip(_players_l))

	_ping_l = Label.new()
	MenuStyle.outlined(_ping_l, 16, Color(1, 1, 1, 0.9), 5)
	col.add_child(_ping_l)
	set_count(1)


## One slanted dark strip around a piece of content.
func _strip(content: Control) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", MenuStyle.strip(Color(MenuStyle.INK, 0.92), Color(1, 1, 1, 0.55), 1, Vector4(34, 22, 7, 7)))
	pc.add_child(content)
	return pc


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
