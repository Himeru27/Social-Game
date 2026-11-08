extends Node
## Autoload "SceneManager": fade-to-black scene transitions by key.

const SCENES := {
	"main_menu": "res://scenes/main_menu/main_menu.tscn",
	"character_customization": "res://scenes/character_customization/character_customization.tscn",
	"server_browser": "res://scenes/server_browser/server_browser.tscn",
	"test_arena": "res://scenes/lobby/test_arena.tscn",
	"lobby_local": "res://scenes/lobby/local_lobby.tscn",
	"lobby_online": "res://scenes/lobby/online_room.tscn",
}

var _rect: ColorRect
var _busy := false
var _queued := ""   ## a go() requested mid-transition runs right after it (e.g. a join result that arrives early)


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_rect = ColorRect.new()
	_rect.color = Color(0.04, 0.05, 0.1, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_rect)


func go(key: String) -> void:
	if not SCENES.has(key):
		push_warning("SceneManager: unknown scene '%s'" % key)
		return
	if _busy:
		_queued = key
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var out := create_tween()
	out.tween_property(_rect, "color:a", 1.0, 0.25)
	await out.finished
	get_tree().change_scene_to_file(SCENES[key])
	await get_tree().process_frame
	await get_tree().process_frame
	var back := create_tween()
	back.tween_property(_rect, "color:a", 0.0, 0.3)
	await back.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	if _queued != "":
		var next := _queued
		_queued = ""
		go(next)
