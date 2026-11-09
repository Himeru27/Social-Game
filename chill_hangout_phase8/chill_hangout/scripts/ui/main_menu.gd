class_name MainMenu
extends Node3D
## Main menu: bright low-poly diorama (the player's character, trees, grass, rocks, clouds) + UI.
## PLAY orbits the camera behind the character and opens the server browser in the same scene.
## Everything is built in code, so the scene file only needs this script on a root Node3D.

const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
const MENU_MUSIC := "res://assets/audio/music/menu_theme.ogg"
## Display font for the main menu and About screen (Anton, SIL Open Font License - see assets/fonts/OFL.txt).
const MENU_FONT: Font = preload("res://assets/fonts/Anton-Regular.ttf")

const ORANGE := MenuStyle.ORANGE
const INK := MenuStyle.INK
const PAPER := MenuStyle.WHITE
const SLANT := MenuStyle.SLANT

## Low camera looking up at the character (relative to the pivot), with a slight tilt.
const CAM_POS := Vector3(0.0, -0.95, 2.3)
const CAM_PITCH := 20.0
const CAM_ROLL := -5.0

## Set by SceneManager when you leave a room: the menu then opens straight on the server screen.
static var start_in_servers := false

var _pivot: Node3D
var _camera: Camera3D
var _backdrop: MenuBackdrop
var _trees: Array[Node3D] = []
var _hero: CharacterModel
var _wave := 0.06
var _t := 0.0
var _ui: CanvasLayer
var _ui_root: Control
var _menu_col: Control
var _buttons: Array[Button] = []
var _browser: ServerBrowser
var _orbit := 0.0              # 0 = in front of the character, PI = behind him
var _server_mode := false
var _transitioning := false


func _ready() -> void:
	_build_environment()
	_build_scenery()
	_build_characters()
	_build_camera()
	_build_ui()
	AudioManager.play_music(MENU_MUSIC, "menu")
	if start_in_servers:
		start_in_servers = false
		_enter_servers(true)


func _process(delta: float) -> void:
	_t += delta
	var sway := lerpf(0.55, 0.22, _orbit / PI)
	_pivot.rotation.y = _orbit + sin(_t * 0.12) * sway
	_backdrop.sun_rig.rotation.y = _orbit
	_camera.position.y = CAM_POS.y + sin(_t * 0.3) * 0.05
	for tr in _trees:
		tr.rotation.z = sin(_t * 0.8 + float(tr.get_meta("phase"))) * 0.025
	_animate_hero(delta)


func get_browser() -> ServerBrowser:
	return _browser


# ---------------------------------------------------------------- 3D world

func _build_environment() -> void:
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# Ring of trees around the character, outside the camera's orbit.
	var near := 28
	for i in near:
		var ang := float(i) / float(near) * TAU + rng.randf_range(-0.12, 0.12)
		var dist := rng.randf_range(5.0, 9.0)
		_make_tree(Vector3(cos(ang) * dist, 0.0, sin(ang) * dist), rng.randf_range(0.9, 1.4), rng)

	# Scattered trees farther out, planted on the hills.
	for i in 26:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(11.0, 45.0)
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		_make_tree(Vector3(x, _backdrop.height_at(x, z), z), rng.randf_range(1.0, 1.8), rng)


func _make_tree(pos: Vector3, scale_f: float, rng: RandomNumberGenerator) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * scale_f
	LowPoly.cylinder(tree, 0.18, 0.24, 1.2, 6, Color("#8a6440"), Vector3(0, 0.6, 0))
	var green := Color("#58b46a").lerp(Color("#8fd47a"), rng.randf())
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
	tag.position = Vector3(0, 2.25 * float(PlayerProfile.appearance["height"]), 0)
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
	# Waves hello on the title screen; arm stays down on the server screen (he is facing away).
	if not _server_mode and fmod(_t, 7.0) < 3.0:
		target = PI * 0.82 + sin(_t * 9.0) * 0.25
	_wave = lerpf(_wave, target, 1.0 - exp(-8.0 * delta))
	_hero.get_right_shoulder().rotation.z = _wave


# ---------------------------------------------------------------- PLAY -> server screen

func _on_play_pressed() -> void:
	if _transitioning or _server_mode:
		return
	_enter_servers(false)


func _set_menu_clickable(on: bool) -> void:
	for b in _buttons:
		b.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


func _enter_servers(instant: bool) -> void:
	_transitioning = true
	_server_mode = true
	_set_menu_clickable(false)
	if instant:
		_orbit = PI
		_menu_col.visible = false
		_open_browser(false)
		_transitioning = false
		return
	var fade := create_tween()
	fade.tween_property(_menu_col, "modulate:a", 0.0, 0.3)
	var orbit := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	orbit.tween_property(self, "_orbit", PI, 1.3)
	await orbit.finished
	_menu_col.visible = false
	_open_browser(true)
	_transitioning = false


func _open_browser(animate: bool) -> void:
	_browser = ServerBrowser.new()
	_browser.back_requested.connect(_leave_servers)
	_ui_root.add_child(_browser)
	_browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if animate:
		_browser.modulate.a = 0.0
		create_tween().tween_property(_browser, "modulate:a", 1.0, 0.35)


func _leave_servers() -> void:
	if _transitioning or _browser == null:
		return
	_transitioning = true
	var old := _browser
	_browser = null
	var out := create_tween()
	out.tween_property(old, "modulate:a", 0.0, 0.2)
	await out.finished
	old.queue_free()
	_server_mode = false
	_menu_col.visible = true
	_menu_col.modulate.a = 0.0
	create_tween().tween_property(_menu_col, "modulate:a", 1.0, 0.3)
	var orbit := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	orbit.tween_property(self, "_orbit", 0.0, 1.3)
	await orbit.finished
	_set_menu_clickable(true)
	_transitioning = false


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	_ui_root = root

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
	_menu_col = col

	# Logo block, tilted like a sticker: "Vibe n'" in white, "Chat" in orange.
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(520, 150)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.pivot_offset = Vector2(0, 150)
	logo.rotation = deg_to_rad(-5.0)
	col.add_child(logo)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 20)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_child(title_row)
	title_row.add_child(MenuStyle.title_word("Vibe n'", PAPER))
	title_row.add_child(MenuStyle.title_word("Chat", ORANGE))

	var sub := Label.new()
	sub.text = "Join the chill zone!"
	sub.position = Vector2(6, 118)
	MenuStyle.outlined(sub, 20, PAPER, 8)
	logo.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	_buttons.append(_add_button(col, "PLAY", _on_play_pressed))
	_buttons.append(_add_button(col, "CHARACTER CUSTOMIZATION", func() -> void: SceneManager.go("character_customization")))
	_buttons.append(_add_button(col, "SETTINGS", _open_settings))
	_buttons.append(_add_button(col, "ABOUT", _open_about))
	_buttons.append(_add_button(col, "QUIT GAME", func() -> void: get_tree().quit()))

	for i in _buttons.size():
		var b := _buttons[i]
		b.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(b, "modulate:a", 1.0, 0.4).set_delay(0.1 * i)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var ver := Label.new()
	ver.text = "v%s" % str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	MenuStyle.outlined(ver, 18, Color(1, 1, 1, 0.9), 5)
	col.add_child(ver)


## Slanted strip used by the menu buttons.
func _strip(fill: Color, border: Color, border_w: int = 0) -> StyleBoxFlat:
	return MenuStyle.strip(fill, border, border_w)


func _add_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(400, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	MenuStyle.style_button(b, 30)
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
	sb.border_color = ORANGE
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

	box.add_child(_about_heading("DEVELOPMENT TEAM", 28, ORANGE))
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
	MenuStyle.style_button(close, 26)
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
	bar.color = ORANGE
	bar.size = Vector2(width, 6)
	holder.add_child(bar)
	return holder
