class_name CharacterModel
extends Node3D
## Quaternius GLB character wrapper. Keeps the Phase 8 CharacterModel API while driving
## each imported rig with its own animation names and bone map. Faces -Z, origin at the feet.

const SOLE := 0.02
const CROUCH_ANGLE := 0.95

signal emote_ended

var body: Node3D
var _thigh := 0.4
var _shin := 0.4
var _hip_l: Node3D
var _hip_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _sh_l: Node3D
var _sh_r: Node3D
var _elb_l: Node3D
var _elb_r: Node3D
var _app: Dictionary

var _t := 0.0
var _phase := 0.0
var _amp := 0.0
var _run := 0.0
var _crouch := 0.0
var _sit := 0.0
var _emote := -1          ## active emote id (-1 none); _pose keeps the last one while blending out
var _pose := -1
var _pt := 0.0            ## seconds since the current pose started
var _ew := 0.0            ## emote blend weight 0..1
var _fore := 0.3
var _cup: Node3D          ## coffee mug held by the right hand during the coffee emote
var _hi: Sprite3D         ## pixel-art "HI" shown next to the head during the hi emote

# Imported Quaternius character scenes. The two rigs are intentionally kept separate:
# their skeletons and animation names are not interchangeable.
const MALE_MODEL: PackedScene = preload("res://assets/characters/male_character.glb")
const FEMALE_MODEL: PackedScene = preload("res://assets/characters/female_character.glb")
const MALE_VISUAL_SCALE := 0.372
const FEMALE_VISUAL_SCALE := 0.34

var _visual: Node3D
var _animation_player: AnimationPlayer
var _skeleton: Skeleton3D
var _model_kind := "male"
var _active_animation := ""
var _runtime_animations: Dictionary = {}
var _bone_indices: Dictionary = {}
var _body_origin_y := 0.82
var _was_sitting := false
var _stand_animation := ""
var _stand_in_progress := false
var _sit_transition_in_progress := false
var _external_shoulder_pose := false
## Gait sync: set to true on every foot plant (see animate). Player consumes it to play the footstep sound.
var step_pending := false
var _step_idx := -1000000
## Height of the seat surface in world units (set by Player.sit).
var sit_height := 0.45


static func preset(kind: String) -> Dictionary:
	return AppearanceData.default_for(kind)


static func create(app: Dictionary) -> CharacterModel:
	var m := CharacterModel.new()
	m.rebuild(app)
	return m


## Emotes are procedural poses blended on top of the normal animation (see _apply_emote).
func play_emote(id: int) -> void:
	if id < 0 or id >= NetProtocol.EMOTES.size():
		stop_emote()
		return
	_emote = id
	_pose = id
	_pt = 0.0


func stop_emote() -> void:
	_emote = -1


func get_emote() -> int:
	return _emote


func get_right_hand_position() -> Vector3:
	return _elb_r.to_global(Vector3(0, -_fore, 0))


func get_right_shoulder() -> Node3D:
	# The Phase 8 main-menu hero writes a wave angle through this proxy each frame.
	_external_shoulder_pose = true
	return _sh_r


func rebuild(app: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_app = AppearanceData.sanitize(app)
	_emote = -1
	_pose = -1
	_ew = 0.0
	_pt = 0.0
	_active_animation = ""
	_animation_player = null
	_skeleton = null
	_visual = null
	_runtime_animations.clear()
	_bone_indices.clear()
	_was_sitting = false
	_stand_in_progress = false
	_sit_transition_in_progress = false
	_external_shoulder_pose = false
	_cup = null
	_hi = null
	_build(_app)


func _build(a: Dictionary) -> void:
	_model_kind = str(a.get("gender", "male"))
	scale = Vector3.ONE # Keep the source model's proportions; only its imported visual root is uniformly fitted.
	_thigh = 0.4
	_shin = 0.4
	_fore = 0.3
	_body_origin_y = _thigh + _shin + SOLE

	var packed: PackedScene = MALE_MODEL if _model_kind == "male" else FEMALE_MODEL
	_visual = packed.instantiate() as Node3D
	_visual.name = "QuaterniusMale" if _model_kind == "male" else "QuaterniusFemale"
	# The supplied Quaternius GLBs face +Z after import; Phase 8 player models face -Z.
	_visual.rotation.y = PI
	var fit_scale := MALE_VISUAL_SCALE if _model_kind == "male" else FEMALE_VISUAL_SCALE
	_visual.scale = Vector3.ONE * fit_scale
	add_child(_visual)
	_find_imported_nodes(_visual)
	_cache_bone_indices()
	_cache_animation_names()
	_apply_male_material_customization(a)

	# Keep a lightweight pose rig for the existing procedural emotes, crouch and coffee/Hi props.
	# It contains no replacement geometry: all visible character geometry remains in the GLB.
	body = Node3D.new()
	body.position.y = _body_origin_y
	add_child(body)
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(0.13 * side, 0.0, 0.0)
		body.add_child(hip)
		var knee := Node3D.new()
		knee.position = Vector3(0.0, -_thigh, 0.0)
		hip.add_child(knee)
		var sh := Node3D.new()
		sh.position = Vector3((0.5 / 2.0 + 0.09) * side, 0.56, 0.0)
		body.add_child(sh)
		var elbow := Node3D.new()
		elbow.position = Vector3(0.0, -0.28, 0.0)
		sh.add_child(elbow)
		if side < 0:
			_hip_l = hip
			_knee_l = knee
			_sh_l = sh
			_elb_l = elbow
		else:
			_hip_r = hip
			_knee_r = knee
			_sh_r = sh
			_elb_r = elbow

	_play_model_animation("Man_Idle" if _model_kind == "male" else "Idle", true, 0.0)
	if _animation_player == null:
		push_warning("CharacterModel: the imported %s GLB has no AnimationPlayer." % _model_kind)
	if _skeleton == null:
		push_warning("CharacterModel: the imported %s GLB has no Skeleton3D." % _model_kind)


func _find_imported_nodes(node: Node) -> void:
	if node is AnimationPlayer and _animation_player == null:
		_animation_player = node as AnimationPlayer
	if node is Skeleton3D and _skeleton == null:
		_skeleton = node as Skeleton3D
	for child in node.get_children():
		_find_imported_nodes(child)


func _cache_bone_indices() -> void:
	if _skeleton == null:
		return
	for i in _skeleton.get_bone_count():
		_bone_indices[str(_skeleton.get_bone_name(i))] = i


func _cache_animation_names() -> void:
	if _animation_player == null:
		return
	_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func _find_animation(fragment: String) -> String:
	if _animation_player == null:
		return ""
	var wanted := fragment.to_lower()
	for animation_name in _animation_player.get_animation_list():
		var library_parts := str(animation_name).split("/", false)
		var local_name := str(library_parts[library_parts.size() - 1])
		var clip_parts := local_name.split("|", false)
		var base_name := str(clip_parts[clip_parts.size() - 1]).to_lower()
		if base_name == wanted:
			return str(animation_name)
	return ""


func _runtime_clip(source_name: String, looped: bool) -> String:
	if source_name.is_empty() or _animation_player == null:
		return ""
	var key := source_name + ("#loop" if looped else "#once")
	if _runtime_animations.has(key):
		return str(_runtime_animations[key])
	var source: Animation = _animation_player.get_animation(source_name)
	if source == null:
		return ""
	var clip := source.duplicate(true) as Animation
	clip.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	if not _animation_player.has_animation_library("runtime"):
		_animation_player.add_animation_library("runtime", AnimationLibrary.new())
	var runtime_name := "runtime/clip_%d" % _runtime_animations.size()
	_animation_player.get_animation_library("runtime").add_animation(runtime_name.get_slice("/", 1), clip)
	_runtime_animations[key] = runtime_name
	return runtime_name


func _play_model_animation(fragment: String, looped := true, blend := 0.16) -> void:
	if _animation_player == null:
		return
	var source_name := _find_animation(fragment)
	if source_name.is_empty():
		return
	var runtime_name := _runtime_clip(source_name, looped)
	if runtime_name.is_empty() or runtime_name == _active_animation:
		return
	_active_animation = runtime_name
	_animation_player.play(runtime_name, blend)


func _update_model_animation(delta: float, speed: float, sitting: bool, airborne: bool) -> void:
	if _animation_player == null:
		return
	var idle_name := "Man_Idle" if _model_kind == "male" else "Idle"
	var walk_name := "Man_Walk" if _model_kind == "male" else "Walking"
	var run_name := "Man_Run" if _model_kind == "male" else "Running"
	var jump_name := "Man_Jump" if _model_kind == "male" else "Jump"

	if _was_sitting and not sitting and _model_kind == "male":
		_stand_animation = _find_animation("Man_Standing")
		_stand_in_progress = not _stand_animation.is_empty()
	if sitting:
		_stand_in_progress = false
	if sitting and not _was_sitting and _model_kind == "female" and not _find_animation("Sitting").is_empty():
		_sit_transition_in_progress = true
		_play_model_animation("Sitting", false, 0.12)
	_was_sitting = sitting

	if _stand_in_progress:
		var stand_runtime := _runtime_clip(_stand_animation, false)
		if _active_animation != stand_runtime:
			_play_model_animation("Man_Standing", false, 0.12)
		elif not _animation_player.is_playing():
			_stand_in_progress = false
			_play_model_animation(idle_name, true)
	elif _emote >= 0:
		_sit_transition_in_progress = false
		_play_model_animation(idle_name, true)
	elif sitting:
		if _model_kind == "female":
			if _sit_transition_in_progress and not _animation_player.is_playing():
				_sit_transition_in_progress = false
				_play_model_animation("SitIdle", true)
			elif not _sit_transition_in_progress:
				_play_model_animation("SitIdle", true)
		else:
			_play_model_animation("Man_Sitting", true)
	elif airborne:
		_sit_transition_in_progress = false
		if _model_kind == "male" and speed > 4.5 and not _find_animation("Man_RunningJump").is_empty():
			_play_model_animation("Man_RunningJump", false)
		else:
			_play_model_animation(jump_name, false)
	elif speed > 4.5:
		_sit_transition_in_progress = false
		_play_model_animation(run_name, true)
	elif speed > 0.15:
		_sit_transition_in_progress = false
		_play_model_animation(walk_name, true)
	else:
		_sit_transition_in_progress = false
		_play_model_animation(idle_name, true)
	_animation_player.advance(delta)


func _apply_male_material_customization(a: Dictionary) -> void:
	# The male GLB has distinct Shirt/Skin/Pants/Eyes/Socks/Hair materials. Duplicate
	# only the selected material at runtime; imported source materials are never edited.
	if _model_kind != "male":
		return
	var defaults := AppearanceData.default_for("male")
	var mesh_instance := _find_first_mesh(_visual)
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var palette_by_option := {
		"shirt_color": AppearanceData.CLOTH_COLORS,
		"skin_tone": AppearanceData.SKIN_TONES,
		"pants_color": AppearanceData.CLOTH_COLORS,
		"eye_color": AppearanceData.EYE_COLORS,
		"shoes_color": AppearanceData.CLOTH_COLORS,
		"hair_color": AppearanceData.HAIR_COLORS,
	}
	var material_by_option := {
		"shirt_color": "shirt", "skin_tone": "skin", "pants_color": "pants",
		"eye_color": "eyes", "shoes_color": "socks", "hair_color": "hair",
	}
	for surface in mesh_instance.mesh.get_surface_count():
		var source_material := mesh_instance.mesh.surface_get_material(surface)
		if not (source_material is StandardMaterial3D):
			continue
		var material_name := str(source_material.resource_name).to_lower()
		if material_name.is_empty():
			var fallback_names := ["shirt", "skin", "pants", "eyes", "socks", "hair"]
			if surface < fallback_names.size():
				material_name = fallback_names[surface]
		for option in material_by_option:
			if material_name.contains(str(material_by_option[option])) and int(a.get(option, defaults[option])) != int(defaults[option]):
				var palette: Array = palette_by_option[option]
				var index := clampi(int(a[option]), 0, palette.size() - 1)
				var material := (source_material as StandardMaterial3D).duplicate() as StandardMaterial3D
				material.albedo_color = palette[index]
				mesh_instance.set_surface_override_material(surface, material)
				break


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


func _apply_external_right_shoulder_pose() -> void:
	if _skeleton == null:
		return
	var bone_name := "UpperArm.R" if _model_kind == "male" else "RightArm"
	var bone_index := int(_bone_indices.get(bone_name, -1))
	if bone_index >= 0:
		_skeleton.set_bone_pose_rotation(bone_index, _sh_r.quaternion)


func _apply_proxy_pose() -> void:
	if _skeleton == null:
		return
	# The imported models have different bone names. Only the major joints used by
	# the existing procedural emotes/crouch are mapped; finger/detail bones stay native.
	var map := {}
	if _model_kind == "male":
		map = {
			"body": "Body", "hip_l": "UpperLeg.L", "hip_r": "UpperLeg.R",
			"knee_l": "LowerLeg.L", "knee_r": "LowerLeg.R",
			"sh_l": "UpperArm.L", "sh_r": "UpperArm.R",
			"elb_l": "LowerArm.L", "elb_r": "LowerArm.R",
		}
	else:
		map = {
			"body": "Hips", "hip_l": "LeftUpLeg", "hip_r": "RightUpLeg",
			"knee_l": "LeftLeg", "knee_r": "RightLeg",
			"sh_l": "LeftArm", "sh_r": "RightArm",
			"elb_l": "LeftForeArm", "elb_r": "RightForeArm",
		}
	var proxies := {
		"body": body, "hip_l": _hip_l, "hip_r": _hip_r,
		"knee_l": _knee_l, "knee_r": _knee_r,
		"sh_l": _sh_l, "sh_r": _sh_r,
		"elb_l": _elb_l, "elb_r": _elb_r,
	}
	for key in map:
		var bone_index := int(_bone_indices.get(str(map[key]), -1))
		var proxy: Node3D = proxies[key]
		if bone_index >= 0 and proxy != null:
			_skeleton.set_bone_pose_rotation(bone_index, proxy.quaternion)
	# Keep root translations from the procedural choreography, but not its dummy torso height.
	if _visual != null:
		_visual.position = Vector3(body.position.x, body.position.y - _body_origin_y, body.position.z)


## speed = horizontal speed in m/s. Parameters are smoothed, so state changes blend.
func animate(delta: float, speed: float, crouching: bool, sitting: bool = false, airborne: bool = false) -> void:
	_t += delta
	_update_model_animation(delta, speed, sitting, airborne)
	var seat_h := sit_height
	var moving := clampf(speed / 2.0, 0.0, 1.0)
	var k := 1.0 - exp(-10.0 * delta)
	_run = lerpf(_run, clampf((speed - 3.2) / 2.4, 0.0, 1.0), k)
	_crouch = lerpf(_crouch, 1.0 if crouching else 0.0, k)
	var amp_target := moving * lerpf(0.5, 0.85, _run) * lerpf(1.0, 0.5, _crouch)
	_amp = lerpf(_amp, amp_target, k)
	_phase += delta * speed * 2.3
	# A foot lands each time sin(_phase) peaks (both legs are then at full stride): every PI of phase.
	var idx := floori((_phase - PI * 0.5) / PI)
	if _step_idx == -1000000:
		_step_idx = idx
	elif idx != _step_idx:
		_step_idx = idx
		if _amp > 0.1:
			step_pending = true

	_sit = lerpf(_sit, 1.0 if sitting else 0.0, 1.0 - exp(-9.0 * delta))
	var s := sin(_phase)
	var c := cos(_phase)
	var base := CROUCH_ANGLE * _crouch
	var swing := clampf(_amp * 2.0, 0.0, 1.0)

	var tl := base + s * _amp
	var tr := base - s * _amp
	var kl := -2.0 * base - maxf(0.0, c) * _amp * 1.2
	var kr := -2.0 * base - maxf(0.0, -c) * _amp * 1.2
	var lean := -(0.28 * _crouch + 0.15 * _run * swing)

	if _sit > 0.001:
		# Thighs forward, shins vertical, feet flat on the floor for the given seat height.
		var hip_y := seat_h / maxf(scale.y, 0.01) + 0.12
		var theta := acos(clampf((hip_y - _shin - SOLE) / _thigh, -0.2, 1.0))
		tl = lerpf(tl, theta, _sit)
		tr = lerpf(tr, theta, _sit)
		kl = lerpf(kl, -theta, _sit)
		kr = lerpf(kr, -theta, _sit)
		lean = lerpf(lean, 0.0, _sit)

	body.rotation.x = lean
	_hip_l.rotation.x = tl - lean
	_hip_r.rotation.x = tr - lean
	_knee_l.rotation.x = kl
	_knee_r.rotation.x = kr

	# Keep the lowest foot exactly on the ground (this also yields the correct seated hip height).
	var hl := _thigh * cos(tl) + _shin * cos(tl + kl)
	var hr := _thigh * cos(tr) + _shin * cos(tr + kr)
	body.position.y = maxf(hl, hr) + SOLE

	var breath := sin(_t * 1.6) * 0.03 * (1.0 - swing)
	_sh_l.rotation.x = -s * _amp * 1.1 + breath + base * 0.25 - lean + 0.5 * _sit
	_sh_r.rotation.x = s * _amp * 1.1 - breath + base * 0.25 - lean + 0.5 * _sit
	if not _external_shoulder_pose:
		_sh_l.rotation.z = -0.06
		_sh_r.rotation.z = 0.06
	var elbow := 0.12 + _run * 0.9 * swing + 0.9 * _sit
	_elb_l.rotation.x = elbow
	_elb_r.rotation.x = elbow
	body.rotation.y = 0.0          # emotes may twist/tilt these; reset so nothing stays stuck after an emote
	body.rotation.z = 0.0
	_elb_l.rotation.z = 0.0
	_elb_r.rotation.z = 0.0
	body.position.x = 0.0
	body.position.z = 0.0
	for hn in [_hip_l, _hip_r]:
		hn.rotation.y = 0.0
		hn.rotation.z = 0.0
	_sh_l.rotation.y = 0.0
	_sh_r.rotation.y = 0.0
	_apply_emote(delta)
	if _ew > 0.001 or _crouch > 0.001 or _sit > 0.001:
		_apply_proxy_pose()
	elif _visual != null:
		_visual.position = Vector3.ZERO
	if _external_shoulder_pose:
		_apply_external_right_shoulder_pose()


func _apply_emote(delta: float) -> void:
	_pt += delta
	if _emote >= 0:
		var e: Dictionary = NetProtocol.EMOTES[_emote]
		if not e["loop"] and _pt >= float(e["dur"]):
			_emote = -1
			emote_ended.emit()
	_ew = move_toward(_ew, 1.0 if _emote >= 0 else 0.0, delta * 5.0)
	var w := smoothstep(0.0, 1.0, _ew)
	_update_props(w)
	if _ew <= 0.0 or _pose < 0:
		return
	var t := _pt
	var p := {}
	match _pose:
		NetProtocol.EMOTE_BRAZILIAN:
			p = _pose_brazilian(t)
		NetProtocol.EMOTE_COFFEE:
			# Left arm tucked at the waist, right hand brings the mug up, head tips back for the sip.
			var r := _coffee_lift(t)
			var sip := _coffee_sip_arm()
			p = {"shr_x": lerpf(0.7, sip[0], r), "shr_y": lerpf(0.0, sip[1], r), "shr_z": lerpf(-0.35, sip[2], r),
				"elr_x": lerpf(1.7, sip[3], r),
				"shl_x": 0.45, "shl_z": 0.3, "ell_x": 1.4,
				"body_x": 0.07 * r, "body_z": sin(t * 1.4) * 0.015}
		NetProtocol.EMOTE_STRANGER:
			p = _pose_stranger(t)
		NetProtocol.EMOTE_HI:
			p = {"shr_z": 2.6 + 0.1 * sin(t * 4.5), "shr_x": 0.15, "elr_z": sin(t * 9.0) * 0.6, "elr_x": 0.2,
				"body_z": sin(t * 4.5) * 0.03}
		NetProtocol.EMOTE_AURA:
			# Back and shoulders on the wall, arms crossed, ankles crossed, slow breathing, tiny foot tap.
			p = {"body_x": 0.28 + sin(t * 1.3) * 0.01, "body_z": 0.0,
				"shl_x": 0.8, "shl_z": 0.5, "ell_x": 2.0, "shr_x": 0.8, "shr_z": -0.5, "elr_x": 2.0,
				"hipl_x": -0.16, "hipr_x": -0.05, "kneel_x": 0.0,
				"kneer_x": -0.5 + maxf(0.0, sin(t * TAU / 2.0)) * 0.06}
	_mix(_sh_l, "x", p, "shl_x", w)
	_mix(_sh_l, "z", p, "shl_z", w)
	_mix(_sh_r, "x", p, "shr_x", w)
	_mix(_sh_r, "z", p, "shr_z", w)
	_mix(_elb_l, "x", p, "ell_x", w)
	_mix(_elb_r, "x", p, "elr_x", w)
	_mix(_elb_r, "z", p, "elr_z", w)
	_mix(body, "x", p, "body_x", w)
	_mix(body, "z", p, "body_z", w)
	_mix(body, "y", p, "body_ry", w)
	_mix(_hip_l, "x", p, "hipl_x", w)
	_mix(_hip_r, "x", p, "hipr_x", w)
	_mix(_knee_l, "x", p, "kneel_x", w)
	_mix(_knee_r, "x", p, "kneer_x", w)
	_mix(_hip_l, "y", p, "hipl_y", w)
	_mix(_hip_r, "y", p, "hipr_y", w)
	_mix(_hip_l, "z", p, "hipl_z", w)
	_mix(_hip_r, "z", p, "hipr_z", w)
	_mix(_sh_l, "y", p, "shl_y", w)
	_mix(_sh_r, "y", p, "shr_y", w)
	if p.has("body_px"):
		body.position.x += float(p["body_px"]) * w
	if p.has("body_y"):
		body.position.y += float(p["body_y"]) * w
	if p.has("ground"):
		_ground_fix(w)
	if _cup != null and is_instance_valid(_cup) and _pose == NetProtocol.EMOTE_COFFEE:
		# Keep the mug upright whatever the arm does; tip the rim toward the mouth while sipping.
		var r2 := _coffee_lift(t)
		var arm_b := _sh_r.basis * _elb_r.basis
		var hold := Basis(Vector3.RIGHT, COFFEE_TILT * r2)
		_cup.basis = arm_b.inverse() * hold
		# The hand carries the mug from underneath, so the forearm stays below the chin instead of covering the mouth.
		_cup.position = Vector3(0.0, -_fore, 0.0) - arm_b.inverse() * (hold * COFFEE_GRIP)


# ---------------------------------------------------------------- dance choreography

## Puts the lowest foot back on the floor whatever the pose does to the legs (used by the two dances).
func _ground_fix(w: float) -> void:
	var lo := 1000.0
	for k in [_knee_l, _knee_r]:
		var a: Vector3 = to_local((k as Node3D).to_global(Vector3(0.0, -_shin, 0.0)))
		lo = minf(lo, a.y)
	body.position.y += (SOLE - lo) * w


func _lerp_arm(a: Array, b: Array, k: float) -> Array:
	return [lerpf(float(a[0]), float(b[0]), k), lerpf(float(a[1]), float(b[1]), k),
			lerpf(float(a[2]), float(b[2]), k), lerpf(float(a[3]), float(b[3]), k)]


## Arm shape = [shoulder flex, abduction (+ outward), forearm turn-in (+ toward centre), elbow flex].
func _arm_keys(p: Dictionary, nm: String, sd: float, a: Array) -> void:
	p["sh%s_x" % nm] = float(a[0])
	p["sh%s_z" % nm] = sd * float(a[1])
	p["sh%s_y" % nm] = sd * float(a[2])
	p["el%s_x" % nm] = float(a[3])


# Brazilian arm shapes, taken from the reference clip (fist at the chin, arm out low, fists together, ...).
const _BR_CHIN := [1.19, 0.52, 1.18, 1.66]
const _BR_LOW := [0.0, 0.08, -0.77, 0.89]
const _BR_CHEST := [0.56, 0.13, 0.89, 1.61]
const _BR_GUARD := [0.89, 0.43, 0.87, 1.82]
const _BR_CROSS := [0.94, 0.83, 1.79, 0.81]
## 8-beat sequence following the clip: [right arm, left arm] per beat.
const _BR_SEQ := [[_BR_CHIN, _BR_LOW], [_BR_LOW, _BR_CHIN], [_BR_CHIN, _BR_LOW], [_BR_CHEST, _BR_CHEST],
		[_BR_LOW, _BR_CHIN], [_BR_CHIN, _BR_LOW], [_BR_CROSS, _BR_LOW], [_BR_GUARD, _BR_GUARD]]


## Brazilian funk "passinho" as in the reference clip: boxing guard (one fist at the chin, the other arm out low, fists
## together, arm sweeping across the chest, high guard), a foot flicked out to the side on every beat (right, left,
## right...), the hips shifting over the planted foot and a knee-bend bounce that is lowest on the kick.
func _pose_brazilian(t: float) -> Dictionary:
	var b: float = (t - NetProtocol.EMOTE_OFFSET_BRAZILIAN) / NetProtocol.EMOTE_BEAT_BRAZILIAN
	var n: int = floori(b)
	var f: float = b - float(n)
	var s: float = 1.0 if posmod(n, 2) == 0 else -1.0       # +1: the character's right foot flicks on this beat
	var env: float = smoothstep(0.0, 0.26, f) * (1.0 - smoothstep(0.40, 0.72, f))
	var bounce: float = 0.5 + 0.5 * cos(TAU * f)
	var bounce2: float = 0.5 + 0.5 * cos(TAU * 2.0 * f)
	var lean := -0.10
	var sq: float = 0.30 + 0.12 * bounce + 0.03 * bounce2
	var dx: float = -s * 0.055 * smoothstep(0.0, 0.2, f) * (1.0 - smoothstep(0.55, 0.85, f))
	var yaw: float = s * 0.22 * env
	var p := {"ground": true, "body_x": lean, "body_px": dx, "body_ry": yaw}
	var leff: float = (_thigh + _shin) * cos(sq)
	var comp: float = asin(clampf(-dx / leff, -0.5, 0.5)) - 0.12 * yaw
	for side in [-1, 1]:
		var sd: float = float(side)
		var nm := "r" if side > 0 else "l"
		var lift: float = env if s * sd > 0.0 else 0.0
		p["hip%s_x" % nm] = lerpf(sq - lean, 0.40 - lean, lift)
		p["knee%s_x" % nm] = lerpf(-2.0 * sq, -1.55, lift)
		p["hip%s_z" % nm] = sd * 0.36 * lift + comp * (1.0 - lift)
		p["hip%s_y" % nm] = -yaw
	var m: int = posmod(n, 8)
	var cur: Array = _BR_SEQ[m]
	var prev: Array = _BR_SEQ[posmod(m - 1, 8)]
	var k: float = smoothstep(0.0, 0.30, f)
	for side in [-1, 1]:
		var idx: int = 0 if side > 0 else 1
		var a: Array = _lerp_arm(prev[idx], cur[idx], k)
		a[0] = float(a[0]) + 0.10 * bounce
		a[3] = float(a[3]) + 0.10 * bounce
		_arm_keys(p, "r" if side > 0 else "l", float(side), a)
	return p


# Baby arm shapes (see the Stranger Things reference clip).
const _BB_HANG := [0.0, 0.10, 0.0, 0.15]
const _BB_MOUTH := [1.19, 0.05, 0.96, 1.62]
const _BB_BELLY := [0.05, 0.0, 0.79, 1.59]
const _BB_OPEN := [0.10, 0.35, -0.30, 0.30]
const _BB_REACH := [0.78, 1.03, 0.59, 1.25]
const _BB_ZOMBIE := [1.40, 0.12, 0.15, 0.35]
const _BB_HANGFWD := [0.35, 0.10, 0.20, 0.50]
const _BB_SIDEOUT := [0.20, 0.80, -0.30, 0.50]
const _BB_NECK := [0.90, -0.10, 0.91, 1.92]
const _STRANGER_LOOP_END := 14.2        ## length of stranger_things_dance.ogg (s); it loops back to 0.75 s
const _STRANGER_LOOP_START := 0.75

var _baby_kf: Array = []


func _bk(beat: float, lean: float, yaw: float, roll: float, c0: float, sq: float, sway: float, march: float,
		bob: float, ra: Array, la: Array) -> Array:
	return [beat, lean, yaw, roll, c0, sq, sway, march, bob,
			ra[0], ra[1], ra[2], ra[3], la[0], la[1], la[2], la[3]]


## Keyframes in beats after the music drop: [beat, lean(-fwd/+back), yaw, roll, stance width, knee bend, sway,
## march, bob, right arm (4), left arm (4)].
func _baby_keys() -> Array:
	if _baby_kf.is_empty():
		var H := _BB_HANG
		_baby_kf = [
			_bk(-3.0, 0.05, 0.0, 0.0, 0.02, 0.03, 0.0, 0.0, 0.0, H, H),                       # standing still, arms down
			_bk(0.0, 0.05, 0.0, 0.0, 0.02, 0.03, 0.0, 0.0, 0.0, H, H),
			_bk(0.5, -0.12, 0.0, 0.0, 0.30, 0.25, 1.0, 0.0, 1.0, _BB_MOUTH, _BB_MOUTH),       # wide-stance sway, hands at mouth
			_bk(2.5, -0.12, 0.0, 0.0, 0.30, 0.25, 1.0, 0.0, 1.0, _BB_MOUTH, _BB_MOUTH),
			_bk(3.0, 0.0, 0.0, 0.0, 0.03, 0.05, 0.0, 0.0, 0.3, _BB_BELLY, _BB_BELLY),
			_bk(3.5, 0.30, 0.0, 0.0, 0.04, 0.06, 0.0, 0.5, 0.3, _BB_OPEN, _BB_OPEN),          # looking up at the ceiling
			_bk(4.5, 0.30, 0.0, 0.0, 0.04, 0.06, 0.0, 0.5, 0.3, _BB_OPEN, _BB_OPEN),
			_bk(5.0, -0.22, 0.0, 0.0, 0.04, 0.10, 0.0, 1.0, 0.3, _BB_BELLY, _BB_REACH),       # looking down, one hand reaching
			_bk(6.3, -0.22, 0.0, 0.0, 0.04, 0.10, 0.0, 1.0, 0.3, _BB_BELLY, _BB_REACH),
			_bk(7.0, 0.06, -1.45, 0.0, 0.05, 0.30, 0.0, 0.5, 0.3, _BB_ZOMBIE, _BB_ZOMBIE),    # turned to profile, arms forward
			_bk(8.5, 0.06, -1.45, 0.0, 0.05, 0.30, 0.0, 0.5, 0.3, _BB_ZOMBIE, _BB_ZOMBIE),
			_bk(9.0, -0.10, -1.45, 0.0, 0.05, 0.40, 0.0, 0.0, 1.0, _BB_HANGFWD, _BB_HANGFWD), # crouched bounce, arms hanging
			_bk(10.5, -0.10, -1.45, 0.0, 0.05, 0.40, 0.0, 0.0, 1.0, _BB_HANGFWD, _BB_HANGFWD),
			_bk(11.3, 0.0, 0.0, 0.0, 0.04, 0.12, 0.0, 1.0, 0.3, _BB_SIDEOUT, H),              # turns back, stepping
			_bk(12.2, 0.30, 0.0, 0.0, 0.03, 0.05, 0.0, 0.0, 0.2, H, H),                        # looks up again
			_bk(13.5, 0.25, 0.0, 0.0, 0.03, 0.05, 0.0, 0.0, 0.2, _BB_NECK, H),                 # hand up to the neck
			_bk(15.5, 0.25, 0.0, 0.0, 0.03, 0.05, 0.0, 0.0, 0.2, _BB_NECK, H),
			_bk(16.75, 0.05, 0.0, 0.0, 0.02, 0.03, 0.0, 0.0, 0.0, H, H),                       # eases back to the start pose
		]
	return _baby_kf


## The baby's dance from the reference clip, timed to the music: still through the intro, the dance starts on the drop
## (beat 3 of the track), and the pose eases back to the start pose right before the audio loops (14.2 s -> 0.75 s,
## exactly 19 beats), so every repeat lines up with the music.
func _pose_stranger(t: float) -> Dictionary:
	var beat := NetProtocol.EMOTE_BEAT_STRANGER
	var u: float = t
	if t >= _STRANGER_LOOP_END:
		u = _STRANGER_LOOP_START + fposmod(t - _STRANGER_LOOP_END, _STRANGER_LOOP_END - _STRANGER_LOOP_START)
	var b: float = (u - (NetProtocol.EMOTE_OFFSET_STRANGER + 3.0 * beat)) / beat
	var kf := _baby_keys()
	var i := 0
	while i < kf.size() - 2 and b >= float((kf[i + 1] as Array)[0]):
		i += 1
	var ka: Array = kf[i]
	var kb: Array = kf[i + 1]
	var k: float = smoothstep(float(ka[0]), float(kb[0]), b)
	var v: Array = []
	for j in ka.size():
		v.append(lerpf(float(ka[j]), float(kb[j]), k))
	var lean: float = v[1]
	var yaw: float = v[2]
	var roll_k: float = v[3]
	var c0: float = v[4]
	var sq0: float = v[5]
	var sway: float = v[6]
	var march: float = v[7]
	var bob: float = v[8]
	var n: int = floori(b)
	var f: float = b - float(n)
	var side_a: float = cos(PI * b)                                  # leans left / right on alternate beats
	var wide: float = 0.5 - 0.5 * cos(TAU * b)                       # 0 on the beat, 1 on the half beat
	var c: float = lerpf(c0, c0 * 0.35, sway * wide)                 # feet wide on the beat, together between
	var sq: float = sq0 + 0.08 * bob * (0.5 + 0.5 * cos(TAU * b))
	var roll: float = roll_k + 0.10 * sway * side_a
	var dx: float = 0.05 * sway * side_a
	var p := {"ground": true, "body_x": lean, "body_ry": yaw, "body_z": roll, "body_px": dx}
	var march_env: float = march * smoothstep(0.0, 0.25, f) * (1.0 - smoothstep(0.45, 0.75, f))
	var s: float = 1.0 if posmod(n, 2) == 0 else -1.0
	for side in [-1, 1]:
		var sd: float = float(side)
		var nm := "r" if side > 0 else "l"
		var lift: float = march_env if s * sd > 0.0 else 0.0
		var desired: float = sd * (0.13 + 0.65 * sin(c))
		var hip_x_now: float = dx + sd * 0.13
		var hz: float = asin(clampf((desired - hip_x_now) / 0.65, -0.6, 0.6)) - roll
		p["hip%s_x" % nm] = lerpf(sq - lean, 0.70 - lean, lift)
		p["knee%s_x" % nm] = lerpf(-2.0 * sq, -1.30, lift)
		p["hip%s_z" % nm] = hz * (1.0 - lift)
	_arm_keys(p, "r", 1.0, [v[9], v[10], v[11], v[12]])
	_arm_keys(p, "l", -1.0, [v[13], v[14], v[15], v[16]])
	return p


## How far the mug is raised (0 = held at the chest, 1 = at the mouth). Timed to the audio: a small lift at ~1 s,
## then the sip while the slurp plays (4.2 - 5.15 s) and the mug comes back down.
func _coffee_lift(t: float) -> float:
	return maxf(0.3 * _sip(t, 0.8, 1.0, 1.3, 1.5), _sip(t, 3.3, 4.0, 5.1, 5.6))


## Mug tilt at the sip (radians, rim tipped toward the face) and where the near rim edge meets the lips (body space).
const COFFEE_TILT := 0.4
const COFFEE_LIPS := Vector3(0.0, 0.8, -0.158)
const COFFEE_GRIP := Vector3(0.0, -0.03, 0.0)      ## where the hand holds the mug, relative to its origin: under the base


## Arm angles [shoulder x, y, z, elbow x] that put the near edge of the mug rim on the lips at the full sip.
## Two-bone IK in body space, so it holds for every arm length: the elbow stays low and out to the side.
func _coffee_sip_arm() -> Array:
	var tip := Basis(Vector3.RIGHT, COFFEE_TILT) * Vector3(0.0, 0.05, 0.048)       # near rim edge, relative to the mug origin
	var target := COFFEE_LIPS - tip + Basis(Vector3.RIGHT, COFFEE_TILT) * COFFEE_GRIP   # where the hand has to be
	var d := target - _sh_r.position
	var l1 := -_elb_r.position.y
	var l2 := _fore                                                                 # elbow -> hand
	var dl := clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var bend := acos(clampf((dl * dl - l1 * l1 - l2 * l2) / (2.0 * l1 * l2), -1.0, 1.0))
	var gamma := acos(clampf((l1 + l2 * cos(bend)) / dl, -1.0, 1.0))
	var axis := d.normalized()
	var pole := Vector3(0.7, -1.0, 0.15)                                            # elbow points down and out
	var side := (pole - axis * pole.dot(axis)).normalized()
	var upper := axis * cos(gamma) + side * sin(gamma)                              # shoulder -> elbow direction
	var fore := ((axis * dl) - upper * l1).normalized()                             # elbow -> mug direction
	var hinge := upper.cross(fore).normalized()
	var down := -upper
	var rot := Basis(hinge, down, hinge.cross(down))
	var e := rot.get_euler()
	return [e.x, e.y, e.z, bend]


## 0 -> 1 between a and b, holds until c, back to 0 at d (used for the sips).
func _sip(t: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, t) * (1.0 - smoothstep(c, d, t))


## Creates / removes the emote props (coffee mug, "HI" text) so they only exist while their emote is active.
func _update_props(w: float) -> void:
	var want_cup := _emote == NetProtocol.EMOTE_COFFEE
	if want_cup and (_cup == null or not is_instance_valid(_cup)):
		_cup = _build_cup()
	if _cup != null and is_instance_valid(_cup):
		if not want_cup and (_ew <= 0.0 or _pose != NetProtocol.EMOTE_COFFEE):
			_cup.queue_free()
			_cup = null
		else:
			_cup.visible = w > 0.02
			_cup.scale = Vector3.ONE * maxf(w, 0.01)    # pops into the hand
	var want_hi := _emote == NetProtocol.EMOTE_HI
	if want_hi and (_hi == null or not is_instance_valid(_hi)):
		_hi = _build_hi()
	if _hi != null and is_instance_valid(_hi):
		if not want_hi:
			_hi.queue_free()
			_hi = null
		else:
			var dur := float(NetProtocol.EMOTES[NetProtocol.EMOTE_HI]["dur"])
			var pop := clampf(_pt / 0.18, 0.0, 1.0)
			var out := clampf((dur - _pt) / 0.3, 0.0, 1.0)
			var k := (pop + sin(pop * PI) * 0.25) * out         # little overshoot, then shrinks away
			_hi.scale = Vector3.ONE * maxf(k, 0.01)
			_hi.position.y = 1.0 + floorf(sin(_pt * 6.0) * 2.0) * 0.012    # steps up and down (retro, not smooth)


func _build_cup() -> Node3D:
	var cup := Node3D.new()
	LowPoly.cylinder(cup, 0.048, 0.04, 0.1, 8, Color("#f1ece4"), Vector3.ZERO)
	LowPoly.cylinder(cup, 0.042, 0.042, 0.008, 8, Color("#4a2c1a"), Vector3(0, 0.048, 0))
	LowPoly.box(cup, Vector3(0.012, 0.06, 0.03), Color("#f1ece4"), Vector3(0.062, 0.0, 0))
	cup.position = Vector3(0, -_fore + 0.02, -0.02)
	_elb_r.add_child(cup)
	return cup


func _build_hi() -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = _pixel_text_texture("HI")
	sp.pixel_size = 0.045
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.double_sided = true
	sp.transparent = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.offset = Vector2(11.0, 0.0)          # beside the head (in texture pixels, so it holds from any camera angle)
	sp.position = Vector3(0, 1.0, 0)
	body.add_child(sp)
	return sp


## 5x7 pixel font (only the letters we need), drawn with a dark outline + drop shadow for a retro look.
const _PIXEL_FONT := {
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
}


static func _pixel_text_texture(text: String) -> ImageTexture:
	var cols := text.length() * 6 - 1
	var img := Image.create(cols + 4, 7 + 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var lit: Array[Vector2i] = []
	for i in text.length():
		var rows: Array = _PIXEL_FONT.get(text[i], [])
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "1":
					lit.append(Vector2i(2 + i * 6 + x, 2 + y))
	var dark := Color("#1b1030")
	for q in lit:
		for dx in range(-1, 2):
			for dy in range(-1, 3):          # dy up to +2: extra row below = drop shadow
				var o := q + Vector2i(dx, dy)
				if o.x >= 0 and o.y >= 0 and o.x < img.get_width() and o.y < img.get_height():
					img.set_pixelv(o, dark)
	for q in lit:
		img.set_pixelv(q, Color("#fff3a8"))
	return ImageTexture.create_from_image(img)


func _mix(n: Node3D, axis: String, p: Dictionary, key: String, w: float) -> void:
	if not p.has(key):
		return
	match axis:
		"x":
			n.rotation.x = lerpf(n.rotation.x, float(p[key]), w)
		"y":
			n.rotation.y = lerpf(n.rotation.y, float(p[key]), w)
		_:
			n.rotation.z = lerpf(n.rotation.z, float(p[key]), w)
