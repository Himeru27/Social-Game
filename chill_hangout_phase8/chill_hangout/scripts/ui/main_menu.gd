extends Node3D
## Main menu: procedural low-poly diorama (the player's character surrounded by trees) + UI.
## Everything is built in code, so the scene file only needs this script on a root Node3D.

const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
const MENU_MUSIC := "res://assets/audio/music/menu_theme.ogg"
## Display font for the main menu and About screen (Anton, SIL Open Font License - see assets/fonts/OFL.txt).
const MENU_FONT: Font = preload("res://assets/fonts/Anton-Regular.ttf")

const RED := Color("#e60012")
const INK := Color("#0b0b10")
const PAPER := Color("#f6f3ec")
const SLANT := 0.28

## Low camera looking up at the character (relative to the pivot), with a slight tilt.
const CAM_POS := Vector3(0.0, -0.95, 2.3)
const CAM_PITCH := 20.0
const CAM_ROLL := -5.0

var _pivot: Node3D
var _camera: Camera3D
var _trees: Array[Node3D] = []
var _hero: CharacterModel
var _wave := 0.06
var _t := 0.0
var _ui: CanvasLayer


func _ready() -> void:
	_build_environment()
	_build_scenery()
	_build_characters()
	_build_camera()
	_build_ui()
	AudioManager.play_music(MENU_MUSIC, "menu")


func _process(delta: float) -> void:
	_t += delta
	_pivot.rotation.y = sin(_t * 0.12) * 0.55
	_camera.position.y = CAM_POS.y + sin(_t * 0.3) * 0.05
	for tr in _trees:
		tr.rotation.z = sin(_t * 0.8 + float(tr.get_meta("phase"))) * 0.025
	_animate_hero(delta)


# ---------------------------------------------------------------- 3D world

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#06060a")
	sky_mat.sky_horizon_color = Color("#7a0c17")
	sky_mat.sky_curve = 0.25
	sky_mat.ground_horizon_color = Color("#7a0c17")
	sky_mat.ground_bottom_color = Color("#050507")
	sky_mat.ground_curve = 0.05
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#7a6f80")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#2a060b")
	env.fog_density = 0.05
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, -30, 0)
	key.light_color = Color("#fff3ec")
	key.light_energy = 0.55
	key.shadow_enabled = true
	add_child(key)

	# Red rim light behind the character.
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.0, 2.0, -2.4)
	rim.light_color = RED
	rim.light_energy = 2.2
	rim.omni_range = 7.0
	add_child(rim)


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# Trees all around the character; nothing between the camera and the character.
	var count := 28
	for i in count:
		var ang := float(i) / float(count) * TAU + rng.randf_range(-0.12, 0.12)
		var dist := rng.randf_range(3.0, 8.0)
		var pos := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		if pos.z > 1.0:
			continue
		_make_tree(pos, rng.randf_range(0.9, 1.4), rng)


func _make_tree(pos: Vector3, scale_f: float, rng: RandomNumberGenerator) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * scale_f
	LowPoly.cylinder(tree, 0.18, 0.24, 1.2, 6, Color("#7a5a3a"), Vector3(0, 0.6, 0))
	var green := Color("#4f9d69").lerp(Color("#7fc47a"), rng.randf())
	LowPoly.cylinder(tree, 0.0, 1.2, 1.8, 6, green, Vector3(0, 2.0, 0))
	LowPoly.cylinder(tree, 0.0, 0.9, 1.5, 6, green.lightened(0.08), Vector3(0, 3.0, 0))
	tree.set_meta("phase", rng.randf() * TAU)
	add_child(tree)
	_trees.append(tree)


func _build_characters() -> void:
	_hero = CharacterModel.create(PlayerProfile.appearance)
	_hero.rotation.y = PI
	add_child(_hero)
	var tag := Label3D.new()
	tag.text = PlayerProfile.username
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 48
	tag.pixel_size = 0.005
	tag.outline_size = 12
	tag.position = Vector3(0, 2.05 * float(PlayerProfile.appearance["height"]), 0)
	add_child(tag)


func _build_camera() -> void:
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 1.1, 0)
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.position = CAM_POS
	_camera.rotation_degrees = Vector3(CAM_PITCH, 0.0, CAM_ROLL)
	_camera.fov = 66.0
	_camera.h_offset = -0.9 # pushes the character to the right, clear of the menu
	_pivot.add_child(_camera)
	_camera.current = true


func _animate_hero(delta: float) -> void:
	_hero.animate(delta, 0.0, false)
	var target := 0.06
	if fmod(_t, 7.0) < 3.0:
		target = PI * 0.82 + sin(_t * 9.0) * 0.25
	_wave = lerpf(_wave, target, 1.0 - exp(-8.0 * delta))
	_hero.get_right_shoulder().rotation.z = _wave


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	# Slanted black panel with a red and a white edge stripe behind the menu.
	_add_slab(root, [Vector2(-40, -40), Vector2(640, -40), Vector2(500, 1500), Vector2(-40, 1500)], Color(INK.r, INK.g, INK.b, 0.82))
	_add_slab(root, [Vector2(640, -40), Vector2(668, -40), Vector2(528, 1500), Vector2(500, 1500)], RED)
	_add_slab(root, [Vector2(676, -40), Vector2(684, -40), Vector2(544, 1500), Vector2(536, 1500)], PAPER)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# Logo block, tilted like a sticker.
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(520, 150)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.pivot_offset = Vector2(0, 150)
	logo.rotation = deg_to_rad(-5.0)
	col.add_child(logo)

	var title := Label.new()
	title.text = "Vibe n' Chat"
	title.position = Vector2(0, 0)
	title.add_theme_font_override("font", MENU_FONT)
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", RED)
	title.add_theme_color_override("font_outline_color", PAPER)
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", INK)
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_outline_size", 14)
	logo.add_child(title)

	var sub := Label.new()
	sub.text = "a relaxing low-poly social space"
	sub.position = Vector2(6, 118)
	sub.add_theme_color_override("font_color", PAPER)
	sub.add_theme_color_override("font_outline_color", INK)
	sub.add_theme_constant_override("outline_size", 6)
	logo.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	var buttons: Array[Button] = []
	buttons.append(_add_button(col, "PLAY", func() -> void: SceneManager.go("server_browser")))
	buttons.append(_add_button(col, "CHARACTER CUSTOMIZATION", func() -> void: SceneManager.go("character_customization")))
	buttons.append(_add_button(col, "SETTINGS", _open_settings))
	buttons.append(_add_button(col, "ABOUT", _open_about))
	buttons.append(_add_button(col, "QUIT GAME", func() -> void: get_tree().quit()))

	for i in buttons.size():
		var b := buttons[i]
		b.modulate.a = 0.0
		b.position.x -= 30
		var tw := create_tween().set_parallel(true)
		tw.tween_property(b, "modulate:a", 1.0, 0.4).set_delay(0.1 * i)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var ver := Label.new()
	ver.text = "v%s  -  Phase 7" % str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	ver.add_theme_color_override("font_color", UITheme.MUTED)
	col.add_child(ver)


func _add_slab(parent: Control, pts: Array, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array(pts)
	poly.color = color
	parent.add_child(poly)


## Slanted strip used by the menu buttons.
func _strip(fill: Color, border: Color, border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.skew = Vector2(SLANT, 0.0)
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.content_margin_left = 34
	sb.content_margin_right = 20
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _add_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(400, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", MENU_FONT)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_stylebox_override("normal", _strip(INK, PAPER, 2))
	b.add_theme_stylebox_override("hover", _strip(RED, PAPER, 2))
	b.add_theme_stylebox_override("pressed", _strip(PAPER, RED, 2))
	b.add_theme_stylebox_override("focus", _strip(RED, PAPER, 2))
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", INK)
	b.pressed.connect(func() -> void:
		AudioManager.play_click()
		cb.call())
	b.mouse_entered.connect(AudioManager.play_hover)
	parent.add_child(b)
	return b


func _open_settings() -> void:
	_ui.add_child(SETTINGS_SCENE.instantiate())


const ABOUT_INTRO := "Vibe n' Chat is an online social game designed to bring people together through conversations, shared experiences, hobbies, and interactive virtual environments. Connect with people from around the world, meet new friends, and enjoy social interactions in a fun and welcoming space."
const ABOUT_IDENTITY := "Create your own identity by customizing your character, choosing your fashion style, and express your personality through your avatar. Explore, hang out, chat, and meet new people! Vibe n' Chat gives you the freedom to socialize and enjoy every moment your way."
const ABOUT_TEAM := [
	["Programmer / Developer", "Himeru"],
	["UI/UX Designer", "Himeru"],
	["Game Designer", "Himeru"],
]


func _open_about() -> void:
	var overlay := Control.new()
	overlay.theme = UITheme.get_theme()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(800, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = INK
	sb.set_corner_radius_all(0)
	sb.border_width_top = 8
	sb.border_color = RED
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vh := get_viewport().get_visible_rect().size.y
	scroll.custom_minimum_size = Vector2(0, minf(vh - 170.0, 560.0))
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	box.add_child(_about_heading("ABOUT", 38, PAPER))
	box.add_child(_accent_bar(96))
	box.add_child(_about_body(ABOUT_INTRO))
	box.add_child(_about_body(ABOUT_IDENTITY))

	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.14)
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)

	box.add_child(_about_heading("DEVELOPMENT TEAM", 28, RED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for row in ABOUT_TEAM:
		var role := Label.new()
		role.text = String(row[0]).to_upper()
		role.custom_minimum_size = Vector2(260, 0)
		role.add_theme_font_size_override("font_size", 16)
		role.add_theme_color_override("font_color", UITheme.MUTED)
		grid.add_child(role)
		grid.add_child(_about_heading(String(row[1]), 22, PAPER))

	var thanks := _about_heading("Thank you all for playing!", 26, PAPER)
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thanks.custom_minimum_size = Vector2(0, 34)
	thanks.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	box.add_child(thanks)

	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0, 52)
	close.add_theme_font_override("font", MENU_FONT)
	close.add_theme_font_size_override("font_size", 26)
	close.add_theme_stylebox_override("normal", _strip(INK, PAPER, 2))
	close.add_theme_stylebox_override("hover", _strip(RED, PAPER, 2))
	close.add_theme_stylebox_override("pressed", _strip(PAPER, RED, 2))
	close.add_theme_color_override("font_color", PAPER)
	close.add_theme_color_override("font_hover_color", Color.WHITE)
	close.add_theme_color_override("font_pressed_color", INK)
	close.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.mouse_entered.connect(AudioManager.play_hover)
	close.pressed.connect(func() -> void:
		AudioManager.play_click()
		overlay.queue_free())
	outer.add_child(close)


func _about_heading(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MENU_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _about_body(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color("#e9e6df"))
	l.add_theme_constant_override("line_spacing", 3)
	return l


func _accent_bar(width: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 6)
	var bar := ColorRect.new()
	bar.color = RED
	bar.size = Vector2(width, 6)
	holder.add_child(bar)
	return holder
