extends Node3D
## Phase 2 dev arena: flat ground, a crouch-only tunnel, a ramp and walls (camera collision).
## F1 flips body type (keeps your customization). Esc releases the mouse, click recaptures. Backspace -> main menu.
## Replaced by the real lobby map in Phase 4.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

var _player: Player


func _ready() -> void:
	LowPoly.add_sky_and_sun(self)
	_build_level()
	_player = PLAYER_SCENE.instantiate()
	_player.initial_appearance = PlayerProfile.appearance
	_player.display_name = PlayerProfile.username
	_player.position = Vector3(0, 0.1, 6)
	add_child(_player)
	var hud := GameHUD.new()
	add_child(hud)
	hud.bind_player(_player)
	hud.set_hint("%s%s%s%s move  |  %s sprint  |  %s crouch  |  F1 flip body type  |  Esc free mouse  |  Backspace menu" % [
		GameSettings.key_label("move_forward"), GameSettings.key_label("move_left"),
		GameSettings.key_label("move_back"), GameSettings.key_label("move_right"),
		GameSettings.key_label("sprint"), GameSettings.key_label("crouch")])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		_player.input_enabled = not captured
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_player.input_enabled = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			var app := PlayerProfile.appearance.duplicate()
			app["gender"] = "female" if app["gender"] == "male" else "male"
			_player.set_appearance(app)
		elif event.keycode == KEY_BACKSPACE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			SceneManager.go("main_menu")


func _solid(size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	add_child(body)
	LowPoly.box(body, size, color)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)


func _build_level() -> void:
	_solid(Vector3(80, 1, 80), Vector3(0, -0.5, 0), Color("#6fb26c"))
	# Crouch tunnel: underside of the lintel is 1.4 m (stand = 1.8, crouch = 1.2).
	_solid(Vector3(0.5, 2.5, 0.8), Vector3(-1.5, 1.25, -8), Color("#9aa0a6"))
	_solid(Vector3(0.5, 2.5, 0.8), Vector3(1.5, 1.25, -8), Color("#9aa0a6"))
	_solid(Vector3(3.5, 1.0, 0.8), Vector3(0, 1.9, -8), Color("#d98e5f"))
	# Ramp
	_solid(Vector3(4, 0.4, 9), Vector3(10, 0.95, -4), Color("#e6d3a3"), Vector3(15, 0, 0))
	# Walls for camera collision tests
	_solid(Vector3(12, 3, 0.4), Vector3(-8, 1.5, 0), Color("#7c9aa8"))
	_solid(Vector3(0.4, 3, 8), Vector3(-14, 1.5, 3), Color("#7c9aa8"))
	# Scattered blocks
	_solid(Vector3(1.5, 1.0, 1.5), Vector3(4, 0.5, 2), Color("#e0605a"))
	_solid(Vector3(1.0, 0.5, 3.0), Vector3(-4, 0.25, 8), Color("#e6cf6a"))
	_solid(Vector3(2.0, 2.0, 2.0), Vector3(0, 1.0, -16), Color("#4a7fc1"))
