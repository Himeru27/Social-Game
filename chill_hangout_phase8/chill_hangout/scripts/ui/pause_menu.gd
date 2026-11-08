class_name PauseMenu
extends CanvasLayer
## In-game pause menu. It does NOT pause the game: the world, the network and every other player
## keep running while it is open (the tree is never paused). Styled like the main menu.

signal resumed
signal join_requested
signal leave_requested
signal quit_requested

const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")

var is_open := false
var _root: Control
var _settings: Control


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.theme = UITheme.get_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(UITheme.BG, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(title)
	var sub := Label.new()
	sub.text = "The server keeps running - others can still see you."
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", UITheme.MUTED)
	v.add_child(sub)
	_button(v, "RESUME", close)
	_button(v, "SETTINGS", _open_settings)
	_button(v, "JOIN SERVER", func() -> void: join_requested.emit())
	_button(v, "LEAVE SERVER", func() -> void: leave_requested.emit())
	_button(v, "QUIT GAME", func() -> void: quit_requested.emit())


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void:
		AudioManager.play_click()
		cb.call())
	b.mouse_entered.connect(AudioManager.play_hover)
	parent.add_child(b)


func open() -> void:
	if is_open:
		return
	is_open = true
	_root.visible = true


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	if _settings != null and is_instance_valid(_settings):
		_settings.queue_free()
	resumed.emit()


func _open_settings() -> void:
	if _settings != null and is_instance_valid(_settings):
		return
	_settings = SETTINGS_SCENE.instantiate()
	_root.add_child(_settings)


## Esc: resume (the settings screen handles and consumes its own Esc first).
func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause") and (_settings == null or not is_instance_valid(_settings)):
		close()
		get_viewport().set_input_as_handled()
