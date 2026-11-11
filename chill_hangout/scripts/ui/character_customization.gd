extends Control
## Character customization: live 3D preview (drag to rotate, scroll to zoom) + option tabs.
## Apply = use for this session. Save = also write to disk. Back discards unapplied edits.

var _app: Dictionary
var _name := ""
var _refreshers: Array[Callable] = []
var _model: CharacterModel
var _pivot: Node3D
var _cam: Camera3D
var _status: Label
var _name_msg: Label
var _apply_btn: Button
var _save_btn: Button
var _gender_label: Label
var _cam_tween: Tween
var _face_focus := false


func _ready() -> void:
	theme = MenuStyle.get_theme()
	_app = PlayerProfile.appearance.duplicate()
	_name = PlayerProfile.username
	# Bright sky, like the main menu and the server browser.
	var sky := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color("#3f9cf0"), Color("#bfe6ff")])
	sky.gradient = grad
	sky.fill_from = Vector2(0, 0)
	sky.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = sky
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)
	row.add_child(_build_preview_column())
	row.add_child(_build_panel())
	_on_name_changed(_name)
	_status.text = ""
	_refresh_controls()


func _process(delta: float) -> void:
	_model.animate(delta, 0.0, false)


# ------------------------------------------------------------ preview

func _build_preview_column() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	col.add_child(MenuStyle.title_word("CHARACTER", MenuStyle.ORANGE, 64))

	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(320, 320)
	holder.clip_contents = true
	col.add_child(holder)
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(vpc)
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", MenuStyle.flat(Color(0, 0, 0, 0), MenuStyle.WHITE, 3, 0))
	holder.add_child(frame)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vpc.add_child(vp)
	_build_preview_world(vp)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_preview_input)
	holder.add_child(overlay)

	var hint := Label.new()
	hint.text = "Drag to rotate  -  scroll to zoom"
	MenuStyle.outlined(hint, 18)
	col.add_child(hint)
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 10)
	views.add_child(_button("FULL BODY", func() -> void: _focus(false)))
	views.add_child(_button("FACE CLOSE-UP", func() -> void: _focus(true)))
	col.add_child(views)
	return col


func _build_preview_world(vp: SubViewport) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#bfe6ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ffffff")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.shadow_enabled = true
	vp.add_child(sun)
	LowPoly.cylinder(vp, 0.9, 0.95, 0.1, 10, Color("#6fcf4a"), Vector3(0, -0.05, 0))
	_pivot = Node3D.new()
	_pivot.rotation.y = PI # model faces -Z; turn it toward the camera
	vp.add_child(_pivot)
	_model = CharacterModel.create(_app)
	_pivot.add_child(_model)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.position = Vector3(0, 1.15, 4.0)
	_cam.rotation_degrees.x = -3.0
	vp.add_child(_cam)
	_cam.current = true


func _on_preview_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_pivot.rotation.y += (e as InputEventMouseMotion).relative.x * 0.012
	elif e is InputEventMouseButton and e.pressed:
		var z := _cam.position.z
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam.position.z = clampf(z - 0.25, 1.2, 5.5)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam.position.z = clampf(z + 0.25, 1.2, 5.5)


func _focus(face: bool) -> void:
	_face_focus = face
	if _cam_tween:
		_cam_tween.kill()
	var h := float(_app["height"])
	var target_pos := Vector3(0, 1.72 * h, 1.6) if face else Vector3(0, 1.15, 4.0)
	var target_rot := 0.0 if face else -3.0
	_cam_tween = create_tween().set_parallel(true)
	_cam_tween.tween_property(_cam, "position", target_pos, 0.35).set_trans(Tween.TRANS_CUBIC)
	_cam_tween.tween_property(_cam, "rotation_degrees:x", target_rot, 0.35)


# ------------------------------------------------------------ option panel

func _build_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	var psb := MenuStyle.flat(Color(MenuStyle.INK, 0.97), MenuStyle.ORANGE, 0, 0)
	psb.border_width_top = 8
	psb.shadow_color = Color(0, 0, 0, 0.45)
	psb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", psb)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)

	var body := _tab(tabs, "Body")
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 10)
	presets.add_child(_button("MALE PRESET", func() -> void: _load_preset("male")))
	presets.add_child(_button("FEMALE PRESET", func() -> void: _load_preset("female")))
	body.add_child(presets)
	_gender_label = Label.new()
	_gender_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	body.add_child(_gender_label)
	_add_swatches(body, "Skin tone", "skin_tone", AppearanceData.SKIN_TONES)
	_add_range(body, "Height", "height")
	_add_range(body, "Body width", "width")
	_add_range(body, "Body thickness", "thickness")
	_add_range(body, "Arm length", "arm_length")
	_add_range(body, "Leg length", "leg_length")

	var hair := _tab(tabs, "Hair")
	_add_choice(hair, "Hairstyle", "hair_style", AppearanceData.HAIR_STYLES)
	_add_swatches(hair, "Hair color", "hair_color", AppearanceData.HAIR_COLORS)

	var face := _tab(tabs, "Face")
	_add_choice(face, "Eye shape", "eye_shape", AppearanceData.EYE_SHAPES)
	_add_swatches(face, "Eye color", "eye_color", AppearanceData.EYE_COLORS)
	_add_choice(face, "Eyebrows", "eyebrows", AppearanceData.EYEBROWS)
	_add_choice(face, "Expression", "expression", AppearanceData.EXPRESSIONS)
	_add_choice(face, "Nose", "nose", AppearanceData.NOSES)
	_add_choice(face, "Mouth", "mouth", AppearanceData.MOUTHS)
	_add_choice(face, "Facial details", "face_detail", AppearanceData.FACE_DETAILS)

	var clothes := _tab(tabs, "Clothing")
	_add_choice(clothes, "Shirt", "shirt_style", AppearanceData.SHIRTS)
	_add_swatches(clothes, "Shirt color", "shirt_color", AppearanceData.CLOTH_COLORS)
	_add_choice(clothes, "Pants", "pants_style", AppearanceData.PANTS)
	_add_swatches(clothes, "Pants color", "pants_color", AppearanceData.CLOTH_COLORS)
	_add_choice(clothes, "Shoes", "shoes_style", AppearanceData.SHOES)
	_add_swatches(clothes, "Shoe color", "shoes_color", AppearanceData.CLOTH_COLORS)

	var acc := _tab(tabs, "Accessories")
	for i in AppearanceData.ACCESSORIES.size():
		_add_flag(acc, AppearanceData.ACCESSORIES[i], i)
	_add_swatches(acc, "Accessory color", "accessory_color", AppearanceData.CLOTH_COLORS)

	var name_tab := _tab(tabs, "Name")
	var nl := Label.new()
	nl.text = "Username shown above your character (%d-%d characters)" % [AppearanceData.MIN_NAME_LEN, AppearanceData.MAX_NAME_LEN]
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_tab.add_child(nl)
	var edit := LineEdit.new()
	MenuStyle.style_line_edit(edit)
	edit.text = _name
	edit.max_length = AppearanceData.MAX_NAME_LEN
	edit.placeholder_text = "Username"
	edit.text_changed.connect(_on_name_changed)
	name_tab.add_child(edit)
	_name_msg = Label.new()
	name_tab.add_child(_name_msg)
	var rules := Label.new()
	rules.text = "Letters, numbers, spaces, - and _ only. Must be unique on the server you join."
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	name_tab.add_child(rules)

	_status = Label.new()
	_status.add_theme_color_override("font_color", MenuStyle.ORANGE)
	v.add_child(_status)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	_apply_btn = _button("APPLY CHANGES", _on_apply)
	_apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_apply_btn)
	_save_btn = _button("SAVE CHARACTER", _on_save)
	_save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_save_btn)
	var rnd := _button("RANDOMIZE", func() -> void:
		_app = AppearanceData.randomized(str(_app["gender"]))
		_changed())
	rnd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(rnd)
	var reset := _button("RESET APPEARANCE", func() -> void: _load_preset(str(_app["gender"])))
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(reset)
	v.add_child(_button("BACK TO MAIN MENU", func() -> void: SceneManager.go("main_menu")))
	return panel


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


## Slanted dark strip around one control row, like the rows in the server browser.
func _strip(parent: Control) -> HBoxContainer:
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", MenuStyle.strip(MenuStyle.ROW_FILL, Color(1, 1, 1, 0.4), 1, Vector4(34, 26, 8, 8)))
	parent.add_child(strip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	strip.add_child(h)
	return h


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := _strip(parent)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 150
	h.add_child(l)
	return h


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	MenuStyle.style_button(b, 24)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func() -> void:
		AudioManager.play_click()
		cb.call())
	b.mouse_entered.connect(AudioManager.play_hover)
	return b


func _add_choice(parent: Control, label: String, key: String, names: Array[String]) -> void:
	var h := _row(parent, label)
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.custom_minimum_size.x = 220
	h.add_child(o)
	o.item_selected.connect(func(i: int) -> void:
		AudioManager.play_click()
		_set_opt(key, i))
	_refreshers.append(func() -> void: o.select(int(_app[key])))


func _style_swatch(b: Button, color: Color, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(4 if selected else 1)
	sb.border_color = Color.WHITE if selected else Color(1, 1, 1, 0.35)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)


func _add_swatches(parent: Control, label: String, key: String, colors: Array[Color]) -> void:
	var h := _row(parent, label)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	h.add_child(flow)
	var buttons: Array[Button] = []
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(32, 32)
		b.pressed.connect(func() -> void:
			AudioManager.play_click()
			_set_opt(key, i))
		flow.add_child(b)
		buttons.append(b)
	_refreshers.append(func() -> void:
		for i in buttons.size():
			_style_swatch(buttons[i], colors[i], int(_app[key]) == i))


func _add_range(parent: Control, label: String, key: String) -> void:
	var r: Vector2 = AppearanceData.RANGES[key]
	var h := _row(parent, label)
	var s := HSlider.new()
	s.min_value = r.x
	s.max_value = r.y
	s.step = 0.01
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var val := Label.new()
	val.custom_minimum_size.x = 56
	h.add_child(val)
	s.value_changed.connect(func(x: float) -> void:
		val.text = "%d%%" % roundi(x * 100.0)
		_set_opt(key, x))
	_refreshers.append(func() -> void:
		s.set_value_no_signal(float(_app[key]))
		val.text = "%d%%" % roundi(s.value * 100.0))


func _add_flag(parent: Control, label: String, bit: int) -> void:
	var c := CheckButton.new()
	c.text = label
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_color_override("font_color", MenuStyle.WHITE)
	c.add_theme_color_override("font_hover_color", MenuStyle.WHITE)
	c.add_theme_color_override("font_pressed_color", MenuStyle.WHITE)
	c.add_theme_color_override("font_hover_pressed_color", MenuStyle.WHITE)
	c.toggled.connect(func(on: bool) -> void:
		AudioManager.play_click()
		var bits := int(_app["accessories"])
		_set_opt("accessories", (bits | (1 << bit)) if on else (bits & ~(1 << bit))))
	_strip(parent).add_child(c)
	_refreshers.append(func() -> void: c.set_pressed_no_signal((int(_app["accessories"]) >> bit) & 1 == 1))


# ------------------------------------------------------------ state

func _set_opt(key: String, value: Variant) -> void:
	_app[key] = value
	_changed()


func _changed() -> void:
	_app = AppearanceData.sanitize(_app)
	_model.rebuild(_app)
	_refresh_controls()
	_status.text = "Unsaved changes"
	if _face_focus:
		_cam.position.y = 1.72 * float(_app["height"])


func _refresh_controls() -> void:
	for r in _refreshers:
		r.call()
	if _gender_label:
		_gender_label.text = "Current body preset: %s" % str(_app["gender"]).capitalize()


func _load_preset(kind: String) -> void:
	_app = AppearanceData.default_for(kind)
	_changed()


func _on_name_changed(text: String) -> void:
	_name = text
	var err := AppearanceData.validate_username(text)
	_name_msg.text = err if err != "" else "Looks good"
	_name_msg.add_theme_color_override("font_color", MenuStyle.WARN if err != "" else MenuStyle.ORANGE)
	_apply_btn.disabled = err != ""
	_save_btn.disabled = err != ""
	if _status:
		_status.text = "Unsaved changes"


func _on_apply() -> void:
	PlayerProfile.apply(_name, _app)
	_status.text = "Applied for this session (not saved to disk)"


func _on_save() -> void:
	PlayerProfile.apply(_name, _app)
	_status.text = "Character saved" if PlayerProfile.save_profile() else "Could not save - check disk permissions"
