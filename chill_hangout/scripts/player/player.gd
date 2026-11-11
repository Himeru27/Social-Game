class_name Player
extends CharacterBody3D
## Third-person player: CharacterBody3D movement, spring-arm camera, sprint + stamina, crouch.
## Collision layers: world = 1, players = 2 (players do not block each other).
## `is_local` is false for remote players (Phase 5): no camera, no input.

signal stamina_changed(value: float, max_value: float, depleted: bool)
signal crouch_changed(crouching: bool)
signal prompt_changed(text: String)
signal seated_changed(seated: bool)
## Online rooms only: the local player asks to sit; the SERVER decides (see OnlineRoom).
signal sit_requested(seat: Seat)
signal emote_changed(emote_id: int)

@export var is_local := true
@export var appearance_preset := "male"
@export var display_name := "Player"
## If non-empty it overrides appearance_preset (set before add_child).
var initial_appearance: Dictionary = {}

const WALK_SPEED := 3.2
const SPRINT_SPEED := 5.8
const CROUCH_SPEED := 1.6
const ACCEL := 22.0
const DECEL := 18.0
const GRAVITY := 20.0
const STAND_H := 1.8
const CROUCH_H := 1.2
const RADIUS := 0.3
const STAMINA_MAX := 100.0
const STAMINA_DRAIN := 20.0
const STAMINA_REGEN := 16.0
const STAMINA_DELAY := 1.0
const STAMINA_RECOVER_AT := 20.0
const CAM_DIST := 3.6

var model: CharacterModel
var stamina := STAMINA_MAX
var depleted := false
var crouching := false
var sprinting := false
var input_enabled := true
var seated := false
var current_seat: Seat = null
var detector: InteractionDetector
## Phase 5 networking. net_mode = local player in an online room (sitting goes through the server).
## Remote players (is_local = false) are driven by remote_buffer instead of input/physics.
var net_mode := false
var net_id := 0
var remote_buffer: SnapshotBuffer
var name_tag: NameTag
var emote := -1

var _yaw := 0.0
var _pitch := -0.2
var _regen_timer := 0.0
var _last_stamina_sent := -1.0
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _rig: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _locked := false
var _seat_tween: Tween
var _step_player: AudioStreamPlayer3D
var _fx_player: AudioStreamPlayer3D
var _lean_tween: Tween
var _fx_tween: Tween


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_capsule.height = STAND_H
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = STAND_H / 2.0
	add_child(_shape)
	set_appearance(initial_appearance if not initial_appearance.is_empty() else CharacterModel.preset(appearance_preset))
	_step_player = _make_audio3d(-3.0)
	_step_player.max_db = 6.0
	_step_player.unit_size = 6.0
	_fx_player = _make_audio3d(-4.0)
	name_tag = NameTag.new()
	add_child(name_tag)
	name_tag.setup(display_name, 2.05 * float(model_height_scale()) + 0.28)
	if is_local:
		_build_camera()
		GameSettings.settings_changed.connect(_apply_fov)
		detector = InteractionDetector.new()
		detector.player = self
		add_child(detector)
		detector.prompt_changed.connect(func(t: String) -> void: prompt_changed.emit(t))
	stamina_changed.emit(stamina, STAMINA_MAX, depleted)


func _make_audio3d(volume_db: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.bus = "SFX"
	a.volume_db = volume_db
	a.unit_size = 4.0
	a.max_distance = 30.0
	add_child(a)
	return a


## One footstep per foot plant of the walk/run animation (CharacterModel.step_pending), so the sound is locked
## to the legs: faster running = faster steps automatically. Crouch steps are quieter, sprint steps louder.
func _footsteps(_delta: float, speed: float, on_ground: bool, crouch: bool, moving: bool = true) -> void:
	if not moving or not on_ground or speed < 1.0:
		# Standing still (or sliding to a stop): no new steps, and cut any step that is still sounding.
		model.step_pending = false
		if _step_player.playing:
			_step_player.stop()
		return
	if not model.step_pending:
		return
	model.step_pending = false
	_step_player.stream = AudioManager.get_footstep()
	_step_player.volume_db = -4.0 if crouch else (5.0 if speed > 4.5 else 2.0)
	_step_player.pitch_scale = randf_range(0.97, 1.03)
	_step_player.play()


func _play_fx(stream: AudioStream) -> void:
	if stream == null or _fx_player == null:
		return
	if _fx_tween:
		_fx_tween.kill()
	_fx_player.volume_db = -4.0
	_fx_player.stream = stream
	_fx_player.play()


## Fades the emote sound out instead of cutting it (used when an emote ends early).
func _fade_out_fx(secs: float) -> void:
	if _fx_player == null or not _fx_player.playing:
		return
	if _fx_tween:
		_fx_tween.kill()
	_fx_tween = create_tween()
	_fx_tween.tween_property(_fx_player, "volume_db", -60.0, secs)
	_fx_tween.tween_callback(_fx_player.stop)


func model_height_scale() -> float:
	return model.scale.y if model else 1.0


## Starts an emote locally. Refused while seated, crouching, locked or moving.
func play_emote(id: int) -> bool:
	if seated or crouching or _locked or model == null:
		return false
	if is_local and Vector2(velocity.x, velocity.z).length() > 0.6:
		return false
	emote = id
	model.play_emote(id)
	_play_fx(AudioManager.get_emote_sound(id))
	if is_local and id == NetProtocol.EMOTE_AURA:
		_snap_to_wall()
	emote_changed.emit(id)
	return true


## Aura Farm: turn your back to the nearest wall within reach and step back until you are leaning on it.
func _snap_to_wall() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.0, 0)
	var best_d := 1.4
	var found := false
	var wall_n := Vector3.ZERO
	var wall_p := Vector3.ZERO
	for i in 8:
		var dir := Vector3(sin(TAU * float(i) / 8.0), 0.0, cos(TAU * float(i) / 8.0))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * best_d)
		q.collision_mask = 1
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		n.y = 0.0
		if n.length() < 0.5:
			continue
		var d := from.distance_to(hit["position"])
		if d < best_d:
			best_d = d
			found = true
			wall_n = n.normalized()
			wall_p = hit["position"]
	if not found:
		return
	var target := Vector3(wall_p.x, global_position.y, wall_p.z) + wall_n * (RADIUS + 0.03)
	var target_yaw := atan2(-wall_n.x, -wall_n.z)       # model back (+Z) toward the wall
	var start_yaw := model.rotation.y
	if _lean_tween:
		_lean_tween.kill()
	_lean_tween = create_tween().set_parallel(true)
	_lean_tween.tween_property(self, "global_position", target, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_lean_tween.tween_method(func(k: float) -> void: model.rotation.y = lerp_angle(start_yaw, target_yaw, k), 0.0, 1.0, 0.3)


func cancel_emote() -> void:
	if emote == -1:
		return
	emote = -1
	_fade_out_fx(0.6)              # the emote music fades away with the emote
	if _lean_tween:
		_lean_tween.kill()
	model.stop_emote()
	emote_changed.emit(-1)


func _on_model_emote_ended() -> void:
	if emote != -1:
		emote = -1
		emote_changed.emit(-1)


func set_appearance(opts: Dictionary) -> void:
	var yaw_keep := 0.0
	if model:
		yaw_keep = model.rotation.y
		model.queue_free()
	model = CharacterModel.create(opts)
	model.rotation.y = yaw_keep
	model.emote_ended.connect(_on_model_emote_ended)
	add_child(model)


func _build_camera() -> void:
	_rig = Node3D.new()
	_rig.position.y = 1.5
	add_child(_rig)
	_arm = SpringArm3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	_arm.shape = sphere
	_arm.spring_length = CAM_DIST
	_arm.margin = 0.1
	_arm.collision_mask = 1
	_arm.add_excluded_object(get_rid())
	_arm.rotation.x = _pitch
	_rig.add_child(_arm)
	_camera = Camera3D.new()
	_arm.add_child(_camera)
	_camera.current = true
	_apply_fov()


func _apply_fov() -> void:
	if _camera:
		_camera.fov = float(GameSettings.get_value("fov"))


func _input(event: InputEvent) -> void:
	if not is_local or not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := deg_to_rad(float(GameSettings.get_value("mouse_sensitivity")) * float(GameSettings.get_value("camera_sensitivity")))
		var rel := (event as InputEventMouseMotion).relative
		_yaw -= rel.x * s
		_pitch = clampf(_pitch - rel.y * s, -1.05, 0.45)
		_rig.rotation.y = _yaw
		_arm.rotation.x = _pitch
	elif event.is_action_pressed("crouch") and not seated and not _locked:
		if crouching:
			if _can_stand():
				_set_crouch(false)
		else:
			_set_crouch(true)


func _physics_process(delta: float) -> void:
	if not is_local:
		_remote_process(delta)
		return
	var input := Vector2.ZERO
	if is_local and input_enabled and not seated and not _locked:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var wish := Vector3.ZERO
	if input != Vector2.ZERO:
		wish = (Basis(Vector3.UP, _yaw) * Vector3(input.x, 0, input.y)).normalized()

	_update_stamina(delta, wish != Vector3.ZERO)
	if emote != -1 and (wish != Vector3.ZERO or crouching):
		cancel_emote()

	if seated or _locked:
		velocity = Vector3.ZERO
		model.animate(delta, 0.0, false, seated)
		_update_rig(delta)
		return

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	var accel := ACCEL if wish != Vector3.ZERO else DECEL
	velocity.x = move_toward(velocity.x, wish.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, accel * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	if wish != Vector3.ZERO:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-wish.x, -wish.z), 1.0 - exp(-12.0 * delta))
	model.animate(delta, Vector2(velocity.x, velocity.z).length(), crouching)
	_footsteps(delta, Vector2(velocity.x, velocity.z).length(), is_on_floor(), crouching, wish != Vector3.ZERO)

	_update_rig(delta)


func _update_rig(delta: float) -> void:
	if _rig:
		var target_y := 1.5
		if crouching:
			target_y = 1.05
		elif seated:
			target_y = 1.15
		_rig.position.y = lerpf(_rig.position.y, target_y, 1.0 - exp(-10.0 * delta))


func is_locked() -> bool:
	return _locked


## Horizontal direction the camera faces (used by the interaction detector).
func get_look_forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func set_look_yaw(yaw: float) -> void:
	_yaw = yaw
	if _rig:
		_rig.rotation.y = yaw
	if model:
		model.rotation.y = yaw


func sit(seat: Seat, confirmed := false) -> bool:
	if seated or _locked:
		return false
	if net_mode and not confirmed:
		sit_requested.emit(seat)
		return false
	if not seat.claim(self):
		return false
	if crouching:
		_set_crouch(false)
	cancel_emote()
	seated = true
	current_seat = seat
	velocity = Vector3.ZERO
	_shape.set_deferred("disabled", true)
	model.sit_height = seat.seat_height
	if _seat_tween:
		_seat_tween.kill()
	var start_yaw := model.rotation.y
	var target_yaw := seat.facing_yaw()
	_seat_tween = create_tween().set_parallel(true)
	_seat_tween.tween_property(self, "global_position", seat.global_position, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_seat_tween.tween_method(func(w: float) -> void: model.rotation.y = lerp_angle(start_yaw, target_yaw, w), 0.0, 1.0, 0.35)
	AudioManager.play_sit()
	seated_changed.emit(true)
	return true


func stand() -> void:
	if not seated:
		return
	var seat := current_seat
	var exit_pos := seat.find_exit()
	seat.release(self)
	seated = false
	current_seat = null
	_locked = true
	if _seat_tween:
		_seat_tween.kill()
	_seat_tween = create_tween()
	_seat_tween.tween_property(self, "global_position", exit_pos, 0.3).set_trans(Tween.TRANS_CUBIC)
	_seat_tween.tween_callback(func() -> void:
		_shape.set_deferred("disabled", false)
		_locked = false)
	seated_changed.emit(false)


# ---------------------------------------------------------------- remote (networked) players

## Interpolated position/animation from received snapshots. Seated players hold their seat.
func _remote_process(delta: float) -> void:
	if remote_buffer == null or model == null:
		return
	var s := remote_buffer.sample(Time.get_ticks_msec() / 1000.0 - NetProtocol.INTERP_DELAY)
	if s.is_empty():
		return
	var flags: int = s["flags"]
	crouching = (flags & NetProtocol.FLAG_CROUCH) != 0
	if seated:
		velocity = Vector3.ZERO
		model.animate(delta, 0.0, false, true)
		return
	var prev_pos := global_position
	global_position = s["pos"]
	model.rotation.y = lerp_angle(model.rotation.y, s["yaw"], 1.0 - exp(-14.0 * delta))
	model.animate(delta, s["speed"], crouching)
	# Trust the real movement of the interpolated body over the reported speed, so a remote player who
	# stopped never keeps stepping.
	var moved := (global_position - prev_pos).length() / maxf(delta, 0.0001)
	_footsteps(delta, minf(float(s["speed"]), moved), true, crouching, moved > 0.3)


func remote_emote(id: int) -> void:
	if id < 0 or seated:
		cancel_emote()
		return
	emote = id
	model.play_emote(id)
	_play_fx(AudioManager.get_emote_sound(id))
	emote_changed.emit(id)


func remote_sit(seat: Seat) -> void:
	cancel_emote()
	if current_seat != null:
		current_seat.release(self)
	seated = true
	current_seat = seat
	seat.occupant = self
	_play_fx(AudioManager.get_sit_sound())
	model.sit_height = seat.seat_height
	if _seat_tween:
		_seat_tween.kill()
	var start_yaw := model.rotation.y
	var target_yaw := seat.facing_yaw()
	_seat_tween = create_tween().set_parallel(true)
	_seat_tween.tween_property(self, "global_position", seat.global_position, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_seat_tween.tween_method(func(w: float) -> void: model.rotation.y = lerp_angle(start_yaw, target_yaw, w), 0.0, 1.0, 0.35)
	seated_changed.emit(true)


func remote_stand() -> void:
	if current_seat != null:
		current_seat.release(self)
	current_seat = null
	seated = false
	if _seat_tween:
		_seat_tween.kill()
	seated_changed.emit(false)


## The server rejected our movement: snap back to the last accepted position.
func server_correct(pos: Vector3, yaw: float) -> void:
	if seated:
		return
	global_position = pos
	velocity = Vector3.ZERO
	if model:
		model.rotation.y = yaw


func _exit_tree() -> void:
	if current_seat != null:
		current_seat.release(self)


func _update_stamina(delta: float, moving: bool) -> void:
	var want := is_local and input_enabled and Input.is_action_pressed("sprint") \
		and moving and not crouching and not depleted
	sprinting = want and stamina > 0.0
	if sprinting:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN * delta)
		_regen_timer = STAMINA_DELAY
		if stamina <= 0.0:
			depleted = true
			sprinting = false
	else:
		if _regen_timer > 0.0:
			_regen_timer -= delta
		else:
			stamina = minf(STAMINA_MAX, stamina + STAMINA_REGEN * delta)
		if depleted and stamina >= STAMINA_RECOVER_AT:
			depleted = false
	if not is_equal_approx(stamina, _last_stamina_sent):
		_last_stamina_sent = stamina
		stamina_changed.emit(stamina, STAMINA_MAX, depleted)


func _set_crouch(on: bool) -> void:
	crouching = on
	_capsule.height = CROUCH_H if on else STAND_H
	_shape.position.y = _capsule.height / 2.0
	crouch_changed.emit(on)


## True if there is room overhead to stand up.
func _can_stand() -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = RADIUS - 0.02
	probe.height = STAND_H - 0.15
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 0.1 + probe.height / 2.0, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
