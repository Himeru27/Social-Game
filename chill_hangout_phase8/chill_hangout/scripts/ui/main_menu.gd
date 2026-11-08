extends Node3D
## Main menu: procedural low-poly diorama + UI. Everything is built in code, so the
## scene file only needs this script on a root Node3D.

const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
const MENU_MUSIC := "res://assets/audio/music/menu_theme.ogg"

var _pivot: Node3D
var _camera: Camera3D
var _clouds: Array[Node3D] = []
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
	_camera.position.y = 0.4 + sin(_t * 0.3) * 0.08
	for c in _clouds:
		c.position.x += delta * float(c.get_meta("speed"))
		if c.position.x > 40.0:
			c.position.x = -40.0
	for tr in _trees:
		tr.rotation.z = sin(_t * 0.8 + float(tr.get_meta("phase"))) * 0.025
	_animate_hero(delta)


# ---------------------------------------------------------------- 3D world

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#6fa8dc")
	sky_mat.sky_horizon_color = Color("#f6d6a8")
	sky_mat.ground_horizon_color = Color("#f6d6a8")
	sky_mat.ground_bottom_color = Color("#8fb98b")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#f2d9b5")
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_color = Color("#fff0d6")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	LowPoly.cylinder(self, 14.0, 14.0, 0.6, 9, Color("#6fb26c"), Vector3(0, -0.3, 0))
	LowPoly.cylinder(self, 5.0, 5.0, 0.05, 8, Color("#e6d3a3"), Vector3(0, 0.025, 0))

	for i in 16:
		var ang := float(i) / 16.0 * TAU + rng.randf_range(-0.15, 0.15)
		var dist := rng.randf_range(7.0, 12.0)
		var pos := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		if pos.z > 3.0:
			continue # keep the area behind the camera clear
		_make_tree(pos, rng.randf_range(0.8, 1.3), rng)

	for i in 6:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(5.5, 9.0)
		var rock := LowPoly.sphere(self, rng.randf_range(0.2, 0.45), Color("#9aa0a6"), Vector3(cos(ang) * dist, 0.1, sin(ang) * dist), 5, 3)
		rock.scale = Vector3(1.2, 0.7, 1.0)

	# Bench
	var bench := Node3D.new()
	bench.position = Vector3(-4.5, 0, -3.0)
	bench.rotation.y = 0.5
	add_child(bench)
	LowPoly.box(bench, Vector3(1.6, 0.1, 0.5), Color("#a5703d"), Vector3(0, 0.5, 0))
	LowPoly.box(bench, Vector3(1.6, 0.4, 0.08), Color("#a5703d"), Vector3(0, 0.75, 0.22))
	for x in [-0.7, 0.7]:
		LowPoly.box(bench, Vector3(0.1, 0.5, 0.4), Color("#5b4630"), Vector3(x, 0.25, 0))

	# Lamp post
	var lamp := Node3D.new()
	lamp.position = Vector3(4.2, 0, -3.5)
	add_child(lamp)
	LowPoly.cylinder(lamp, 0.05, 0.07, 2.4, 6, Color("#3b3f4a"), Vector3(0, 1.2, 0))
	LowPoly.sphere(lamp, 0.22, Color("#ffe6a0"), Vector3(0, 2.5, 0), 6, 3)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.5, 0)
	light.light_color = Color("#ffd98a")
	light.light_energy = 1.2
	light.omni_range = 6.0
	lamp.add_child(light)

	for i in 7:
		var cloud := Node3D.new()
		cloud.position = Vector3(rng.randf_range(-40, 40), rng.randf_range(9, 14), rng.randf_range(-30, -6))
		cloud.set_meta("speed", rng.randf_range(0.2, 0.6))
		for j in 3:
			var b := LowPoly.box(cloud, Vector3(rng.randf_range(2.5, 4.5), rng.randf_range(0.8, 1.2), rng.randf_range(1.5, 2.5)), Color("#ffffff"), Vector3(j * 2.0 - 2.0, rng.randf_range(-0.2, 0.3), rng.randf_range(-0.5, 0.5)))
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cloud)
		_clouds.append(cloud)


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
	_camera.position = Vector3(0, 0.4, 6.0)
	_camera.rotation_degrees.x = -3.0
	_camera.fov = 55.0
	_camera.h_offset = -1.6 # pushes the characters to the right, clear of the menu
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

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var title := Label.new()
	title.text = "CHILL HANGOUT"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.add_theme_color_override("font_outline_color", UITheme.BG)
	title.add_theme_constant_override("outline_size", 10)
	col.add_child(title)

	var sub := Label.new()
	sub.text = "a relaxing low-poly social space"
	sub.add_theme_color_override("font_color", UITheme.TEXT)
	sub.add_theme_color_override("font_outline_color", UITheme.BG)
	sub.add_theme_constant_override("outline_size", 6)
	col.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	var buttons: Array[Button] = []
	buttons.append(_add_button(col, "PLAY", func() -> void: SceneManager.go("server_browser")))
	buttons.append(_add_button(col, "CHARACTER CUSTOMIZATION", func() -> void: SceneManager.go("character_customization")))
	buttons.append(_add_button(col, "SETTINGS", _open_settings))
	buttons.append(_add_button(col, "ABOUT", _open_about))
	if OS.is_debug_build():
		buttons.append(_add_button(col, "DEV: HANGOUT ROOM (LOCAL)", func() -> void: SceneManager.go("lobby_local")))
		buttons.append(_add_button(col, "DEV: TEST ARENA", func() -> void: SceneManager.go("test_arena")))
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


func _add_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void:
		AudioManager.play_click()
		cb.call())
	b.mouse_entered.connect(AudioManager.play_hover)
	parent.add_child(b)
	return b


func _open_settings() -> void:
	_ui.add_child(SETTINGS_SCENE.instantiate())


func _open_about() -> void:
	var overlay := Control.new()
	overlay.theme = UITheme.get_theme()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	var t := Label.new()
	t.text = "ABOUT"
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", UITheme.ACCENT)
	box.add_child(t)
	var body := Label.new()
	body.text = "Chill Hangout (working title) is a low-poly multiplayer social game built with Godot 4 and GDScript.\n\nPlayers customize an avatar, meet in servers, chat, emote and relax together.\n\nBuild status: Phase 7 - pause menu and full menu flow."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void:
		AudioManager.play_click()
		overlay.queue_free())
	box.add_child(close)
