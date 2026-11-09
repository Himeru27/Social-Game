extends Control
## Settings overlay. Instance scenes/ui/settings_menu.tscn, add it to any CanvasLayer/Control,
## and listen to the `closed` signal. Usable from the main menu and (Phase 7) the pause menu.

signal closed

var _listening := ""
var _key_buttons: Dictionary = {}
var _refreshers: Array[Callable] = []


func _ready() -> void:
	theme = MenuStyle.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.1, 0.16, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Same panel as CREATE SERVER: dark ink, orange bar on top.
	var panel := PanelContainer.new()
	var vs := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(820.0, vs.x - 60.0), minf(560.0, vs.y - 60.0))
	var sb := MenuStyle.flat(Color(MenuStyle.INK, 0.97), MenuStyle.ORANGE, 0, 0)
	sb.border_width_top = 8
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", MenuStyle.ORANGE)
	v.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)

	var audio := _tab(tabs, "Audio")
	_add_slider(audio, "Master volume", "master_volume", 0.0, 1.0, 0.01, "pct")
	_add_slider(audio, "Music volume", "music_volume", 0.0, 1.0, 0.01, "pct")
	_add_slider(audio, "Sound effects volume", "sfx_volume", 0.0, 1.0, 0.01, "pct")

	var gameplay := _tab(tabs, "Gameplay")
	_add_slider(gameplay, "Mouse sensitivity", "mouse_sensitivity", 0.05, 1.0, 0.01, "num")
	_add_slider(gameplay, "Camera sensitivity", "camera_sensitivity", 0.2, 3.0, 0.05, "num")
	_add_slider(gameplay, "Field of view", "fov", 60.0, 110.0, 1.0, "deg")

	var gfx := _tab(tabs, "Graphics")
	_add_option(gfx, "Graphics quality", "graphics_quality", GameSettings.QUALITY_NAMES)
	var res_names: Array[String] = []
	for r in GameSettings.RESOLUTIONS:
		res_names.append("%d x %d" % [r.x, r.y])
	_add_option(gfx, "Resolution (windowed)", "resolution_index", res_names)
	_add_check(gfx, "Fullscreen", "fullscreen")

	var controls := _tab(tabs, "Controls")
	for entry in GameSettings.ACTIONS:
		_add_key_row(controls, entry[0], entry[1])
	var pause_row := _row(controls, "Pause menu")
	var pause_btn := Button.new()
	pause_btn.text = "Esc"
	pause_btn.disabled = true
	pause_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_btn.custom_minimum_size.x = 150
	pause_row.add_child(pause_btn)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	v.add_child(bottom)
	var reset := _button("RESET TO DEFAULTS", _on_reset)
	reset.custom_minimum_size.x = 300
	bottom.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var back := _button("BACK", close)
	back.custom_minimum_size.x = 200
	bottom.add_child(back)


func _tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	# Side margins leave room for the slant of the row strips.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	scroll.add_child(pad)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	pad.add_child(box)
	return box


## Each setting sits in a slanted dark strip, like the rows in the server browser.
func _row(parent: Control, text: String) -> HBoxContainer:
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", MenuStyle.strip(MenuStyle.ROW_FILL, Color(1, 1, 1, 0.4), 1, Vector4(34, 26, 8, 8)))
	parent.add_child(strip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	strip.add_child(h)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 230
	h.add_child(l)
	return h


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	MenuStyle.style_button(b, 26)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func() -> void:
		AudioManager.play_click()
		cb.call())
	b.mouse_entered.connect(AudioManager.play_hover)
	return b


func _fmt(kind: String, x: float) -> String:
	match kind:
		"pct": return "%d%%" % roundi(x * 100.0)
		"deg": return "%d°" % roundi(x)
		_: return "%.2f" % x


func _add_slider(parent: Control, label: String, key: String, lo: float, hi: float, step: float, kind: String) -> void:
	var h := _row(parent, label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(GameSettings.get_value(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var val := Label.new()
	val.custom_minimum_size.x = 70
	val.text = _fmt(kind, s.value)
	h.add_child(val)
	s.value_changed.connect(func(x: float) -> void:
		GameSettings.set_value(key, x)
		val.text = _fmt(kind, x))
	_refreshers.append(func() -> void:
		s.set_value_no_signal(float(GameSettings.get_value(key)))
		val.text = _fmt(kind, s.value))


func _add_option(parent: Control, label: String, key: String, items: Array[String]) -> void:
	var h := _row(parent, label)
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(int(GameSettings.get_value(key)))
	o.custom_minimum_size.x = 220
	h.add_child(o)
	o.item_selected.connect(func(i: int) -> void:
		AudioManager.play_click()
		GameSettings.set_value(key, i))
	_refreshers.append(func() -> void: o.select(int(GameSettings.get_value(key))))


func _add_check(parent: Control, label: String, key: String) -> void:
	var h := _row(parent, label)
	var c := CheckButton.new()
	c.button_pressed = bool(GameSettings.get_value(key))
	h.add_child(c)
	c.toggled.connect(func(on: bool) -> void:
		AudioManager.play_click()
		GameSettings.set_value(key, on))
	_refreshers.append(func() -> void: c.set_pressed_no_signal(bool(GameSettings.get_value(key))))


func _add_key_row(parent: Control, action: String, label: String) -> void:
	var h := _row(parent, label)
	var b := Button.new()
	b.custom_minimum_size.x = 150
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.text = GameSettings.key_label(action)
	b.pressed.connect(func() -> void:
		AudioManager.play_click()
		_listening = action
		_refresh_keys()
		b.text = "Press a key...")
	h.add_child(b)
	_key_buttons[action] = b


func _refresh_keys() -> void:
	for a in _key_buttons:
		(_key_buttons[a] as Button).text = GameSettings.key_label(a)


func _on_reset() -> void:
	GameSettings.reset_defaults()
	_listening = ""
	for r in _refreshers:
		r.call()
	_refresh_keys()


func _input(event: InputEvent) -> void:
	if _listening != "" and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		var code := int((event as InputEventKey).physical_keycode)
		if code != KEY_ESCAPE:
			GameSettings.rebind(_listening, code)
		_listening = ""
		_refresh_keys()
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	GameSettings.save_settings()
	closed.emit()
	queue_free()
