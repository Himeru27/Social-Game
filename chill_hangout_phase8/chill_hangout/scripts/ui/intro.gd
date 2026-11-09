extends Control
## Boot intro: plays the video, then fades into the main menu. Any key/click skips.

const VIDEO := "res://assets/video/intro.ogv"

var _done := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var player := VideoStreamPlayer.new()
	player.set_anchors_preset(Control.PRESET_FULL_RECT)
	player.expand = true
	player.stream = load(VIDEO)
	player.finished.connect(_finish)
	add_child(player)
	player.play()


func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.pressed and not event.is_echo():
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	SceneManager.go("main_menu")
