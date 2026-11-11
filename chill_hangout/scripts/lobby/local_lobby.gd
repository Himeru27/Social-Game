extends Node3D
## Single-machine lobby: the hangout room + your character. No networking yet - Phase 5 replaces
## this with real server-spawned players. Esc frees the mouse, click recaptures, Backspace -> menu.

const ROOM_SCENE: PackedScene = preload("res://scenes/lobby/hangout_room.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

var player: Player


func _ready() -> void:
	add_child(ROOM_SCENE.instantiate())
	player = PLAYER_SCENE.instantiate()
	player.initial_appearance = PlayerProfile.appearance
	player.display_name = PlayerProfile.username
	var spawns := get_tree().get_nodes_in_group("spawn_points")
	player.position = (spawns[randi() % spawns.size()] as Node3D).global_position if not spawns.is_empty() else Vector3(0, 0.5, 10)
	add_child(player)
	var hud := GameHUD.new()
	add_child(hud)
	hud.bind_player(player)
	hud.set_hint("%s%s%s%s move  |  %s sprint  |  %s crouch  |  %s sit/stand  |  Esc free mouse  |  Backspace menu" % [
		GameSettings.key_label("move_forward"), GameSettings.key_label("move_left"),
		GameSettings.key_label("move_back"), GameSettings.key_label("move_right"),
		GameSettings.key_label("sprint"), GameSettings.key_label("crouch"), GameSettings.key_label("interact")])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		player.input_enabled = not captured
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		player.input_enabled = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_BACKSPACE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		SceneManager.go("main_menu")
