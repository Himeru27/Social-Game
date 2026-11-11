class_name PauseMenu
extends CanvasLayer
## In-game pause menu. It does NOT pause the game: the world, the network and every other player
## keep running while it is open (the tree is never paused). Same look as the main menu and the
## server browser: Anton title, slanted dark strips, white + orange.

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
	dim.color = Color(0.04, 0.1, 0.16, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	_root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	col.add_child(MenuStyle.title_word("PAUSED", MenuStyle.ORANGE, 72))
	var sub := Label.new()
	sub.text = "The server keeps running - others can still see you."
	MenuStyle.outlined(sub, 20, MenuStyle.WHITE, 8)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	_button(col, "RESUME", close)
	_button(col, "SETTINGS", _open_settings)
	_button(col, "JOIN SERVER", func() -> void: join_requested.emit())
	_button(col, "LEAVE SERVER", func() -> void: leave_requested.emit())
	_button(col, "QUIT GAME", func() -> void: quit_requested.emit())


func _button(parent: Control, text: String, cb: Callable) -> void:
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


func open() -> void:
	if is_open:
		return
	is_open = true
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.15)
	AudioManager.play_pause()


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
