class_name IntroPopup
extends CanvasLayer
## "How to play" card shown ONCE, the first time the player joins a server. It lists the controls
## (using the player's current key bindings) and is closed with the GOT IT button, Esc or Enter.
## Whether it was already shown is remembered by GameSettings.has_seen / mark_seen.

signal closed

const FLAG := "intro_controls"

var is_open := false
var _root: Control
var _button: Button


func _ready() -> void:
	layer = 18
	_root = Control.new()
	_root.theme = UITheme.get_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.1, 0.16, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	var sb := MenuStyle.flat(Color(MenuStyle.INK, 0.97), MenuStyle.ORANGE, 0, 0)
	sb.border_width_top = 8
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 14)
	title_row.add_child(MenuStyle.title_word("HOW", MenuStyle.WHITE, 52))
	title_row.add_child(MenuStyle.title_word("TO PLAY", MenuStyle.ORANGE, 52))
	v.add_child(title_row)

	var intro := Label.new()
	intro.text = "Welcome to the chill zone! Here is everything you need to get around."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 640
	intro.add_theme_font_size_override("font_size", 18)
	intro.add_theme_color_override("font_color", Color("#e9e6df"))
	v.add_child(intro)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	var wasd := "%s%s%s%s" % [GameSettings.key_label("move_forward"), GameSettings.key_label("move_left"),
		GameSettings.key_label("move_back"), GameSettings.key_label("move_right")]
	var entries := [
		[wasd, "Move"],
		[GameSettings.key_label("sprint"), "Sprint"],
		[GameSettings.key_label("crouch"), "Crouch"],
		[GameSettings.key_label("interact"), "Sit / interact"],
		[GameSettings.key_label("chat"), "Text chat"],
		[GameSettings.key_label("emote_menu"), "Emotes"],
		[GameSettings.key_label("player_list"), "Players (hold)"],
		["Esc", "Pause menu"],
	]
	for e in entries:
		grid.add_child(_key_chip(str(e[0])))
		var l := Label.new()
		l.text = str(e[1])
		l.custom_minimum_size.x = 150
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", MenuStyle.WHITE)
		grid.add_child(l)

	var tip := Label.new()
	tip.text = "You can change any key in Settings > Controls."
	tip.add_theme_font_size_override("font_size", 16)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	v.add_child(tip)

	_button = Button.new()
	_button.text = "GOT IT!"
	_button.custom_minimum_size = Vector2(0, 54)
	MenuStyle.style_button(_button, 28)
	_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button.pressed.connect(func() -> void:
		AudioManager.play_click()
		close())
	_button.mouse_entered.connect(AudioManager.play_hover)
	v.add_child(_button)


## Orange slanted key cap.
func _key_chip(text: String) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(112, 38)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.add_theme_stylebox_override("panel", MenuStyle.strip(MenuStyle.ORANGE, MenuStyle.ORANGE, 0, Vector4(16, 12, 3, 3)))
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", MenuStyle.FONT)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", MenuStyle.INK)
	pc.add_child(l)
	return pc


func open() -> void:
	if is_open:
		return
	is_open = true
	GameSettings.mark_seen(FLAG)      # counts as seen as soon as it appears: it never shows twice
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.25)
	_button.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	closed.emit()


## Esc closes it too (and stops Esc from also opening the pause menu).
func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
