extends Node
## Autoload "GameSettings": persistent user settings + the runtime InputMap.
## Saved to user://settings.cfg so values survive restarts.

signal settings_changed

const SAVE_PATH := "user://settings.cfg"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440),
]
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]
const VIDEO_KEYS: Array[String] = ["graphics_quality", "resolution_index", "fullscreen"]

const DEFAULTS := {
	"master_volume": 0.8,
	"music_volume": 0.5,
	"sfx_volume": 0.8,
	"mouse_sensitivity": 0.3,
	"camera_sensitivity": 1.0,
	"graphics_quality": 1,
	"resolution_index": 0,
	"fullscreen": false,
	"fov": 75.0,
	"server_host": "wss://social-game-t1gb.onrender.com",
	"server_port": 7777,
}

## [action name, label shown in the Controls tab]
const ACTIONS := [
	["move_forward", "Move forward"],
	["move_back", "Move backward"],
	["move_left", "Move left"],
	["move_right", "Move right"],
	["sprint", "Sprint"],
	["crouch", "Crouch"],
	["interact", "Interact / Sit"],
	["chat", "Open text chat"],
	["emote_menu", "Emote menu"],
	["player_list", "Player list (hold)"],
]
const DEFAULT_KEYS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"sprint": KEY_SHIFT,
	"crouch": KEY_C,
	"interact": KEY_E,
	"chat": KEY_T,
	"emote_menu": KEY_PERIOD,
	"player_list": KEY_TAB,
	"pause": KEY_ESCAPE,
}

var data: Dictionary = DEFAULTS.duplicate()
var keys: Dictionary = DEFAULT_KEYS.duplicate()


func _ready() -> void:
	load_settings()
	apply_all()


func get_value(key: String) -> Variant:
	return data[key]


func set_value(key: String, value: Variant) -> void:
	data[key] = value
	if key in VIDEO_KEYS:
		_apply_video()
	settings_changed.emit()


func reset_defaults() -> void:
	data = DEFAULTS.duplicate()
	keys = DEFAULT_KEYS.duplicate()
	apply_all()


func key_label(action: String) -> String:
	return OS.get_keycode_string(int(keys[action]))


## Rebinds an action. If another action already uses the key, the two swap.
func rebind(action: String, keycode: int) -> void:
	for other in keys:
		if other != action and int(keys[other]) == keycode:
			keys[other] = keys[action]
	keys[action] = keycode
	_apply_input()
	settings_changed.emit()


func apply_all() -> void:
	_apply_input()
	_apply_video()
	settings_changed.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in data:
		cfg.set_value("settings", k, data[k])
	for a in keys:
		cfg.set_value("keys", a, keys[a])
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for k in DEFAULTS:
		var v: Variant = cfg.get_value("settings", k, DEFAULTS[k])
		match typeof(DEFAULTS[k]):
			TYPE_INT: data[k] = int(v)
			TYPE_FLOAT: data[k] = float(v)
			TYPE_BOOL: data[k] = bool(v)
			TYPE_STRING: data[k] = str(v)
	for a in DEFAULT_KEYS:
		keys[a] = int(cfg.get_value("keys", a, DEFAULT_KEYS[a]))


func _apply_input() -> void:
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_erase_events(a)
		var ev := InputEventKey.new()
		ev.physical_keycode = int(keys[a]) as Key
		InputMap.action_add_event(a, ev)


func _apply_video() -> void:
	var win := get_window()
	if bool(data["fullscreen"]):
		win.mode = Window.MODE_FULLSCREEN
	else:
		win.mode = Window.MODE_WINDOWED
		var size: Vector2i = RESOLUTIONS[clampi(int(data["resolution_index"]), 0, RESOLUTIONS.size() - 1)]
		win.size = size
		var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		win.position = screen.position + (screen.size - size) / 2
	var q: int = clampi(int(data["graphics_quality"]), 0, 2)
	var msaa: Array[Viewport.MSAA] = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
	var shadow_sizes: Array[int] = [1024, 2048, 4096]
	get_viewport().msaa_3d = msaa[q]
	RenderingServer.directional_shadow_atlas_set_size(shadow_sizes[q], true)
