class_name CharacterModel
extends Node3D
## Character built from an appearance Dictionary (see AppearanceData): the supplied Quaternius GLB for the chosen
## gender, driven by its own idle / walk / run / sit clips plus the original procedural crouch and emotes.
## Faces -Z, origin at the feet. Call rebuild(app) to change look, animate() every frame.

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
## Gait sync: set to true on every foot plant (see animate). Player consumes it to play the footstep sound.
var step_pending := false
var _clock := 0.0
var _pos_w := 0.0             ## weight of the driver's body translation this frame (dances / crouch)
var _sh_r_z_written := 0.06   ## what animate() last wrote to the right shoulder (anything else = external wave)
## Height of the seat surface in world units (set by Player.sit).
var sit_height := 0.45


## ---------------------------------------------------------------------------------------------------------------
## Phase 9: the visible body is the supplied Quaternius GLB (assets/characters/*.glb). The procedural rig below
## (body / hips / knees / shoulders / elbows) is kept as an invisible "driver": all of the original gait, sit,
## emote and prop code keeps running on it unchanged, and _retarget() copies its joint angles onto the matching
## bones of the GLB skeleton wherever the driver is in charge (emotes, crouch, main-menu wave). Everything else
## (idle / walk / run / sit / stand) plays the GLB's own animations.
## ---------------------------------------------------------------------------------------------------------------

const MODEL_PATHS := {
	"male": "res://assets/characters/male_character.glb",
	"female": "res://assets/characters/female_character.glb",
}

## Per-model rig description (the two GLBs have different skeletons, clip names and materials).
## scale: uniform factor that brings the GLB (about 5 units tall) to a human size; it is the only scaling applied.
## head_y / head_top / face_z / lips_y: measured on the GLB (metres, model space, GLB frame: +Z = front).
const RIGS := {
	"male": {
		"scale": 0.38,
		"body": "Body", "hip_l": "UpperLeg.L", "hip_r": "UpperLeg.R", "knee_l": "LowerLeg.L", "knee_r": "LowerLeg.R",
		"ankle_l": "LowerLeg.L_end", "ankle_r": "LowerLeg.R_end", "foot_l": "", "foot_r": "",
		"sh_l": "UpperArm.L", "sh_r": "UpperArm.R", "elb_l": "LowerArm.L", "elb_r": "LowerArm.R",
		"hand_l": "Palm.L", "hand_r": "Palm.R", "hand2_l": "MiddleHand.L", "hand2_r": "MiddleHand.R",
		"head": "Head", "torso": "Torso", "neck": "Neck", "head_dz": -0.03,
		"idle": "HumanArmature|Man_Idle", "walk": "HumanArmature|Man_Walk", "run": "HumanArmature|Man_Run",
		"sit": "HumanArmature|Man_Sitting", "sit_loop": "", "stand": "HumanArmature|Man_Standing",
		"walk_speed": 1.5, "run_speed": 3.2, "sit_hip_y": 0.48,
		"head_y": 1.68, "head_top": 1.83, "head_w": 0.17, "head_d": 0.24, "face_z": 0.13, "lips_y": 1.60, "eye_y": 1.70,
		"materials": {"Shirt": "shirt", "Skin": "skin", "Pants": "pants", "Eyes": "eyes", "Socks": "shoes", "Hair": "hair"},
	},
	"female": {
		"scale": 0.337,
		"body": "Hips", "hip_l": "LeftUpLeg", "hip_r": "RightUpLeg", "knee_l": "LeftLeg", "knee_r": "RightLeg",
		"ankle_l": "LeftFoot", "ankle_r": "RightFoot", "foot_l": "LeftFoot", "foot_r": "RightFoot",
		"sh_l": "LeftArm", "sh_r": "RightArm", "elb_l": "LeftForeArm", "elb_r": "RightForeArm",
		"hand_l": "LeftHand", "hand_r": "RightHand", "hand2_l": "", "hand2_r": "",
		"head": "Head", "torso": "Spine2", "neck": "Neck", "head_dz": -0.01,
		"idle": "Armature|Idle", "walk": "Armature|Walking", "run": "Armature|Running",
		"sit": "Armature|SitIdle", "sit_loop": "Armature|SitIdle", "stand": "",
		"walk_speed": 1.23, "run_speed": 3.13, "sit_hip_y": 0.54,
		"head_y": 1.58, "head_top": 1.75, "head_w": 0.17, "head_d": 0.22, "face_z": 0.10, "lips_y": 1.52, "eye_y": 1.60,
		"materials": {},
	},
}
## The woman has ONE material whose 32x32 texture holds six flat colours; these are swapped (never edited on disk).
const FEMALE_PALETTE := {
	"shirt": Color8(231, 101, 92), "hair": Color8(209, 194, 112), "skin": Color8(231, 189, 145),
	"pants": Color8(97, 135, 211), "shoes": Color8(240, 71, 47), "eyes": Color8(41, 41, 41),
}
## Appearance keys the GLB models can honour without altering their geometry (everything else is shown disabled).
const SUPPORTED := ["skin_tone", "hair_color", "eye_color", "shirt_color", "pants_color", "shoes_color",
	"height", "width", "thickness", "accessories", "accessory_color"]
const RUN_ENTER := 2.6
const RUN_EXIT := 2.2
const CLIP_BLEND := 0.2

var _kind := ""
var _rig: Dictionary
var _offset: Node3D          ## vertical/horizontal correction applied while seated
var _vis: Node3D             ## scale + 180 degree turn (the GLB faces +Z, the game faces -Z)
var _glb: Node3D
var _skel: Skeleton3D
var _ap: AnimationPlayer
var _mesh: MeshInstance3D
var _s2m := Transform3D.IDENTITY            ## skeleton space -> model space (without the seat offset)
var _hip_y := 0.8
var _hip_z := 0.0
var _body_c := Vector3.ZERO                 ## real root bone pivot minus the driver body origin
var _lips := Vector3(0.0, 0.8, -0.158)
var _hi_y := 1.0
var _feet: Array = []                      ## foot bones kept flat while the legs are driven (crouch)
var _bone := {}                             ## joint name -> {idx, parent, n (Basis), rest (Basis)}
var _anim_bones := {}                       ## bone idx -> true when the GLB animations key it
var _touched := {}                          ## driver joint -> emote weight this frame
var _wave_ref := 0.0
var _clip := ""
var _was_sitting := false
var _stand_until := 0.0
var _speed_in := 0.0
var _sitting_in := false
var _run_mode := false
var _head_anchor: Node3D
var _torso_anchor: Node3D
var _head_idx := -1
var _torso_idx := -1
var _props: Node3D
var _foot_idx := [-1, -1]
var _foot_up := [false, false]
var _ground_ref := 0.05
var _sit_w := 0.0
var _orig_mats := {}                        ## surface index -> original (shared) material, never modified


static func preset(kind: String) -> Dictionary:
	return AppearanceData.default_for(kind)


static func create(app: Dictionary) -> CharacterModel:
	var m := CharacterModel.new()
	m.rebuild(app)
	return m


## Is this appearance option applied to the GLB models? (the customization UI greys out the others)
static func option_supported(key: String) -> bool:
	return key in SUPPORTED


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
	return _sh_r


## Switching gender loads the other GLB; any other change only re-skins / re-scales the loaded one.
func rebuild(app: Dictionary) -> void:
	_app = AppearanceData.sanitize(app)
	var kind: String = _app["gender"]
	if kind != _kind or _glb == null:
		for c in get_children():
			remove_child(c)
			c.queue_free()
		_cup = null
		_hi = null
		_kind = ""
		_load_model(kind)
	_apply_look(_app)


func _load_model(kind: String) -> void:
	_kind = kind
	_rig = RIGS[kind]
	_offset = Node3D.new()
	add_child(_offset)
	_vis = Node3D.new()
	_vis.scale = Vector3.ONE * float(_rig["scale"])
	_vis.rotation.y = PI
	_offset.add_child(_vis)
	_glb = (load(MODEL_PATHS[kind]) as PackedScene).instantiate()
	_vis.add_child(_glb)
	_skel = _glb.find_children("*", "Skeleton3D", true, false)[0]
	_ap = _glb.find_children("*", "AnimationPlayer", true, false)[0]
	_mesh = _glb.find_children("*", "MeshInstance3D", true, false)[0]
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for k in ["idle", "walk", "run", "sit_loop"]:
		var n: String = _rig[k]
		if n != "" and _ap.has_animation(n):
			_ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_anim_bones.clear()
	var any_clip: Animation = _ap.get_animation(_rig["idle"])
	for i in any_clip.get_track_count():
		var p := str(any_clip.track_get_path(i))
		var bi := _skel.find_bone(p.get_slice(":", 1))
		if bi >= 0:
			_anim_bones[bi] = true
	# skeleton space -> model space: every node between the skeleton and the seat offset node
	_s2m = Transform3D.IDENTITY
	var n3: Node = _skel
	while n3 != _offset:
		_s2m = (n3 as Node3D).transform * _s2m
		n3 = n3.get_parent()
	_build_driver()
	_head_idx = _skel.find_bone(_rig["head"])
	_torso_idx = _skel.find_bone(_rig["torso"])
	_props = null
	_orig_mats.clear()
	for s in _mesh.mesh.get_surface_count():
		_orig_mats[s] = _mesh.mesh.surface_get_material(s)
	_foot_idx = [_skel.find_bone(_rig["ankle_l"]), _skel.find_bone(_rig["ankle_r"])]
	_foot_up = [false, false]
	_clip = ""
	_was_sitting = false
	_play_clip(_rig["idle"], 0.0, 1.0)


func _rest_model(bone: String) -> Vector3:
	return _s2m * _skel.get_bone_global_rest(_skel.find_bone(bone)).origin


## Builds the invisible procedural rig with the REAL limb lengths of the GLB, so the unchanged gait / sit / ground /
## coffee-IK maths produce angles that fit the actual skeleton.
func _build_driver() -> void:
	var r := _rig
	var hl := _rest_model(r["hip_l"])
	var hr := _rest_model(r["hip_r"])
	var kl := _rest_model(r["knee_l"])
	var al := _rest_model(r["ankle_l"])
	_hip_y = (hl.y + hr.y) * 0.5
	_hip_z = (hl.z + hr.z) * 0.5
	var ground := minf(al.y, _rest_model(r["ankle_r"]).y)
	_ground_ref = ground
	_thigh = hl.distance_to(kl)
	_shin = kl.distance_to(al) + maxf(ground - SOLE, 0.0)   # knee -> floor (ankle height included), as in the original rig
	var root := _rest_model(r["body"])
	body = Node3D.new()
	add_child(body)
	body.position = Vector3(0, _thigh + _shin + SOLE, _hip_z)
	_body_c = root - Vector3(0, _hip_y, _hip_z)
	var sh_l := _rest_model(r["sh_l"])
	var sh_r := _rest_model(r["sh_r"])
	var el_l := _rest_model(r["elb_l"])
	var el_r := _rest_model(r["elb_r"])
	var ua := sh_l.distance_to(el_l)
	var hand := _rest_model(r["hand_r"])
	if r["hand2_r"] != "":
		hand = (hand + _rest_model(r["hand2_r"])) * 0.5
	_fore = el_r.distance_to(hand)
	var origin := Vector3(0, _hip_y, _hip_z)
	for side in [-1, 1]:
		var hp: Vector3 = (hl if side < 0 else hr) - origin
		var hip := Node3D.new()
		hip.position = hp
		body.add_child(hip)
		var knee := Node3D.new()
		knee.position = Vector3(0, -_thigh, 0)
		hip.add_child(knee)
		var sp: Vector3 = (sh_l if side < 0 else sh_r) - origin
		var sh := Node3D.new()
		sh.position = sp
		body.add_child(sh)
		var elb := Node3D.new()
		elb.position = Vector3(0, -ua, 0)
		sh.add_child(elb)
		if side < 0:
			_hip_l = hip
			_knee_l = knee
			_sh_l = sh
			_elb_l = elb
		else:
			_hip_r = hip
			_knee_r = knee
			_sh_r = sh
			_elb_r = elb
	_lips = Vector3(0.0, float(r["lips_y"]) - _hip_y, -float(r["face_z"]) - _hip_z)
	_hi_y = float(r["head_y"]) - _hip_y + 0.1
	# retarget table: neutral (hanging) correction and rest orientation of every driven bone
	_bone.clear()
	var s2m_rot := _s2m.basis.orthonormalized()
	var table := {
		"body": [r["body"], ""], "hip_l": [r["hip_l"], r["knee_l"]], "hip_r": [r["hip_r"], r["knee_r"]],
		"knee_l": [r["knee_l"], r["ankle_l"]], "knee_r": [r["knee_r"], r["ankle_r"]],
		"sh_l": [r["sh_l"], r["elb_l"]], "sh_r": [r["sh_r"], r["elb_r"]],
		"elb_l": [r["elb_l"], r["hand_l"]], "elb_r": [r["elb_r"], r["hand_r"]],
	}
	for k in table:
		var bi := _skel.find_bone(table[k][0])
		var n := Basis.IDENTITY
		if table[k][1] != "":
			var d := _rest_model(table[k][1]) - _rest_model(table[k][0])
			n = Basis(Quaternion(d.normalized(), Vector3.DOWN))
		_bone[k] = {"idx": bi, "parent": _skel.get_bone_parent(bi), "n": n,
			"rest": s2m_rot * _skel.get_bone_global_rest(bi).basis.orthonormalized()}
	_feet.clear()
	for k in ["foot_l", "foot_r"]:
		if r[k] != "":
			var fi := _skel.find_bone(r[k])
			_feet.append({"idx": fi, "parent": _skel.get_bone_parent(fi),
				"rest": s2m_rot * _skel.get_bone_global_rest(fi).basis.orthonormalized()})


## Re-skins / re-scales the loaded GLB. Options equal to the model's own default leave the ORIGINAL imported
## materials in place, so the default look is exactly the supplied GLB. Overrides are duplicates; the shared
## imported resources are never edited.
func _apply_look(a: Dictionary) -> void:
	scale = Vector3(a["width"], a["height"], a["thickness"])
	var d := AppearanceData.default_for(_kind)
	var cols := {}
	if a["skin_tone"] != d["skin_tone"]:
		cols["skin"] = AppearanceData.SKIN_TONES[int(a["skin_tone"])]
	if a["hair_color"] != d["hair_color"]:
		cols["hair"] = AppearanceData.HAIR_COLORS[int(a["hair_color"])]
	if a["eye_color"] != d["eye_color"]:
		cols["eyes"] = AppearanceData.EYE_COLORS[int(a["eye_color"])]
	for k in ["shirt", "pants", "shoes"]:
		if a[k + "_color"] != d[k + "_color"]:
			cols[k] = AppearanceData.CLOTH_COLORS[int(a[k + "_color"])]
	if _orig_mats.is_empty():      # headless / dummy renderer: no mesh data to re-skin
		pass
	elif _kind == "male":
		var map: Dictionary = _rig["materials"]
		for s in _orig_mats:
			var orig: Material = _orig_mats[s]
			var role: String = map.get(orig.resource_name, "")
			if cols.has(role):
				var m := orig.duplicate() as StandardMaterial3D
				m.albedo_color = cols[role]
				_mesh.set_surface_override_material(s, m)
			else:
				_mesh.set_surface_override_material(s, null)
	else:
		_mesh.set_surface_override_material(0, null if cols.is_empty() else _female_material(cols))
	_build_accessories(int(a["accessories"]), AppearanceData.CLOTH_COLORS[int(a["accessory_color"])])


func _female_material(cols: Dictionary) -> Material:
	var orig := _orig_mats[0] as StandardMaterial3D
	var src: Image = orig.albedo_texture.get_image()
	if src.is_compressed():
		src.decompress()
	var img := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			for role in cols:
				var p: Color = FEMALE_PALETTE[role]
				if absf(c.r - p.r) < 0.01 and absf(c.g - p.g) < 0.01 and absf(c.b - p.b) < 0.01:
					c = Color(cols[role], c.a)
					break
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := orig.duplicate() as StandardMaterial3D
	m.albedo_texture = ImageTexture.create_from_image(img)
	return m


func _b(parent: Node, size: Vector3, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := LowPoly.box(parent, size, color, pos)
	mi.rotation_degrees = rot_deg
	return mi


## Optional accessories (all off by default). Boxes follow the head / torso bone; they are not part of the GLB.
func _build_accessories(bits: int, col: Color) -> void:
	if _props != null:
		_props.queue_free()
		_props = null
	if bits == 0:
		return
	_props = Node3D.new()
	_offset.add_child(_props)
	var hc := Node3D.new()      # head-anchored (origin = head centre, +Z = back, -Z = front)
	var tc := Node3D.new()      # torso-anchored (origin = torso bone)
	_props.add_child(hc)
	_props.add_child(tc)
	_head_anchor = hc
	_torso_anchor = tc
	var hw: float = _rig["head_w"]
	var hd: float = _rig["head_d"]
	var fz: float = float(_rig["face_z"])
	if bits & 1: # glasses
		var frame := Color("#1d1d22")
		var ey: float = float(_rig["eye_y"]) - float(_rig["head_y"])
		for side in [-1, 1]:
			var gx: float = hw * 0.22 * side
			_b(hc, Vector3(0.07, 0.01, 0.01), frame, Vector3(gx, ey + 0.03, -fz))
			_b(hc, Vector3(0.07, 0.01, 0.01), frame, Vector3(gx, ey - 0.03, -fz))
			_b(hc, Vector3(0.01, 0.06, 0.01), frame, Vector3(gx - 0.035, ey, -fz))
			_b(hc, Vector3(0.01, 0.06, 0.01), frame, Vector3(gx + 0.035, ey, -fz))
		_b(hc, Vector3(0.02, 0.01, 0.01), frame, Vector3(0, ey + 0.02, -fz))
	if bits & 2: # cap
		var top: float = float(_rig["head_top"]) - float(_rig["head_y"])
		_b(hc, Vector3(hw + 0.05, 0.08, hd + 0.04), col, Vector3(0, top - 0.05, 0.0))
		_b(hc, Vector3(hw * 0.8, 0.015, 0.12), col.darkened(0.15), Vector3(0, top - 0.085, -hd * 0.62))
	var neck_y: float = _rest_model(_rig["neck"]).y - _rest_model(_rig["torso"]).y
	if bits & 4: # backpack
		_b(tc, Vector3(0.3, 0.38, 0.12), col, Vector3(0, neck_y - 0.24, 0.17))
		for sx in [-0.11, 0.11]:
			_b(tc, Vector3(0.04, 0.42, 0.02), col.darkened(0.2), Vector3(sx, neck_y - 0.2, -0.13))
	if bits & 8: # scarf
		_b(tc, Vector3(0.27, 0.09, 0.24), col, Vector3(0, neck_y - 0.04, 0.0))
		_b(tc, Vector3(0.09, 0.24, 0.04), col, Vector3(0.09, neck_y - 0.17, -0.13))


# ---------------------------------------------------------------- GLB animation + retargeting

func _process(delta: float) -> void:
	if _glb != null:
		advance_pose(delta)


## One frame of GLB animation: pick / advance the clip, then let the driver overrule the bones it controls.
func advance_pose(delta: float) -> void:
	_clock += delta
	_update_clip()
	_ap.advance(delta)
	_skel.force_update_all_bone_transforms()     # fresh global poses for the retarget maths below
	_retarget()
	_skel.force_update_all_bone_transforms()
	_update_seat_offset(delta)
	_update_anchors()
	_detect_steps()


func _play_clip(clip: String, blend: float, spd: float) -> void:
	if clip == "" or not _ap.has_animation(clip):
		return
	if clip != _clip:
		_ap.play(clip, blend)
		_clip = clip
	_ap.speed_scale = spd


func _update_clip() -> void:
	var sp := _speed_in
	if _sitting_in:
		_was_sitting = true
		_stand_until = 0.0
		_play_clip(_rig["sit"], 0.3, 1.0)
		return
	if _was_sitting:
		_was_sitting = false
		var st: String = _rig["stand"]
		if st != "" and _ap.has_animation(st):
			_stand_until = _clock + _ap.get_animation(st).length
			_play_clip(st, 0.2, 1.0)
	if _stand_until > _clock and sp < 0.5:
		return
	_stand_until = 0.0
	if sp < 0.3:
		_play_clip(_rig["idle"], CLIP_BLEND, 1.0)
		return
	if _run_mode and sp < RUN_EXIT:
		_run_mode = false
	elif not _run_mode and sp > RUN_ENTER:
		_run_mode = true
	if _run_mode:
		_play_clip(_rig["run"], CLIP_BLEND, clampf(sp / float(_rig["run_speed"]), 0.8, 2.0))
	else:
		_play_clip(_rig["walk"], CLIP_BLEND, clampf(sp / float(_rig["walk_speed"]), 0.5, 1.8))


func _node_key(n: Node3D) -> String:
	if n == body:
		return "body"
	if n == _hip_l:
		return "hip_l"
	if n == _hip_r:
		return "hip_r"
	if n == _knee_l:
		return "knee_l"
	if n == _knee_r:
		return "knee_r"
	if n == _sh_l:
		return "sh_l"
	if n == _sh_r:
		return "sh_r"
	if n == _elb_l:
		return "elb_l"
	return "elb_r"


## Copies the driver's joint angles onto the GLB bones, blended with the clip pose by a per-joint weight:
## emote weight for the joints an emote drives, crouch weight for body / legs, and the main menu's wave.
func _retarget() -> void:
	var cw := _crouch * (1.0 - _sit)
	var w := {"body": cw, "hip_l": cw, "hip_r": cw, "knee_l": cw, "knee_r": cw,
		"sh_l": 0.0, "sh_r": 0.0, "elb_l": 0.0, "elb_r": 0.0}
	for k in _touched:
		w[k] = maxf(float(w[k]), float(_touched[k]))
	var dz := absf(_sh_r.rotation.z - _sh_r_z_written)
	if dz > 0.02 and not _touched.has("sh_r"):
		w["sh_r"] = smoothstep(0.02, 0.35, dz)
	var qb := body.basis
	var qh_l := qb * _hip_l.basis
	var qh_r := qb * _hip_r.basis
	var qs_l := qb * _sh_l.basis
	var qs_r := qb * _sh_r.basis
	var chain := {"body": qb, "hip_l": qh_l, "hip_r": qh_r, "knee_l": qh_l * _knee_l.basis, "knee_r": qh_r * _knee_r.basis,
		"sh_l": qs_l, "sh_r": qs_r, "elb_l": qs_l * _elb_l.basis, "elb_r": qs_r * _elb_r.basis}
	var s2m_inv := _s2m.basis.orthonormalized().inverse()
	for k in ["body", "hip_l", "hip_r", "knee_l", "knee_r", "sh_l", "sh_r", "elb_l", "elb_r"]:
		var wk: float = w[k]
		if wk <= 0.001:
			continue
		var info: Dictionary = _bone[k]
		var target: Basis = s2m_inv * (chain[k] as Basis) * (info["n"] as Basis) * (info["rest"] as Basis)
		var par: int = info["parent"]
		var pg := _skel.get_bone_global_pose(par).basis.orthonormalized() if par >= 0 else Basis.IDENTITY
		var q := (pg.inverse() * target).orthonormalized().get_rotation_quaternion()
		var idx: int = info["idx"]
		_skel.set_bone_pose_rotation(idx, _skel.get_bone_pose_rotation(idx).slerp(q, wk).normalized())
	if cw > 0.001:
		for f in _feet:
			var fpar: int = f["parent"]
			var fpg := _skel.get_bone_global_pose(fpar).basis.orthonormalized()
			var fq := (fpg.inverse() * (s2m_inv * (f["rest"] as Basis))).orthonormalized().get_rotation_quaternion()
			var fidx: int = f["idx"]
			_skel.set_bone_pose_rotation(fidx, _skel.get_bone_pose_rotation(fidx).slerp(fq, cw).normalized())
	var wp := maxf(cw, _pos_w)
	if wp > 0.001:
		var bi: int = _bone["body"]["idx"]
		var par2: int = _bone["body"]["parent"]
		var pgt := _skel.get_bone_global_pose(par2) if par2 >= 0 else Transform3D.IDENTITY
		var cur: Vector3 = _s2m * (pgt * _skel.get_bone_pose_position(bi))
		var tgt := body.position + _body_c
		var want := Vector3(cur.x + body.position.x * wp, lerpf(cur.y, tgt.y, wp), cur.z)
		_skel.set_bone_pose_position(bi, pgt.affine_inverse() * (_s2m.affine_inverse() * want))


## While seated the hips are pinned over the seat's floor point and lowered / raised to the seat height
## (the GLB sit clips were authored for one chair; the original rig adapted to every seat height).
func _update_seat_offset(delta: float) -> void:
	_sit_w = lerpf(_sit_w, 1.0 if _sitting_in else 0.0, 1.0 - exp(-9.0 * delta))
	var bi: int = _bone["body"]["idx"]
	var hips: Vector3 = _s2m * _skel.get_bone_global_pose(bi).origin
	var tgt_y := sit_height / maxf(scale.y, 0.01) + 0.12 - float(_rig["sit_hip_y"])
	_offset.position = Vector3(-hips.x * _sit_w, tgt_y * _sit_w, -(hips.z - _body_c.z - _hip_z) * _sit_w)


func _update_anchors() -> void:
	if _props == null:
		return
	_anchor(_head_anchor, _head_idx, Vector3(0.0, float(_rig["head_y"]), float(_rig["head_dz"])))
	_anchor(_torso_anchor, _torso_idx, Vector3.ZERO)


## Anchor frame = bone origin (+ rest-pose offset) with the bone's rotation relative to its rest pose, so props are
## authored in plain model axes whatever the bone's own axes are.
func _anchor(a: Node3D, idx: int, rest_off: Vector3) -> void:
	var pose := _s2m * _skel.get_bone_global_pose(idx)
	var rest := _s2m * _skel.get_bone_global_rest(idx)
	var rot := pose.basis.orthonormalized() * rest.basis.orthonormalized().inverse()
	var off := Vector3.ZERO
	if rest_off != Vector3.ZERO:
		off = Vector3(0.0, rest_off.y - rest.origin.y, rest_off.z)
	a.transform = Transform3D(rot, pose.origin + rot * off)


## One footstep per foot plant of whatever clip is playing (the GLB clips have their own gait).
func _detect_steps() -> void:
	for i in 2:
		var h: float = (_s2m * _skel.get_bone_global_pose(_foot_idx[i]).origin).y - _ground_ref
		if h > 0.06:
			_foot_up[i] = true
		elif h < 0.03 and _foot_up[i]:
			_foot_up[i] = false
			if _speed_in > 0.5 and not _sitting_in:
				step_pending = true


## speed = horizontal speed in m/s. Parameters are smoothed, so state changes blend.
func animate(delta: float, speed: float, crouching: bool, sitting: bool = false) -> void:
	_t += delta
	_speed_in = speed
	_sitting_in = sitting
	var seat_h := sit_height
	var moving := clampf(speed / 2.0, 0.0, 1.0)
	var k := 1.0 - exp(-10.0 * delta)
	_run = lerpf(_run, clampf((speed - 3.2) / 2.4, 0.0, 1.0), k)
	_crouch = lerpf(_crouch, 1.0 if crouching else 0.0, k)
	var amp_target := moving * lerpf(0.5, 0.85, _run) * lerpf(1.0, 0.5, _crouch)
	_amp = lerpf(_amp, amp_target, k)
	_phase += delta * speed * 2.3

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
	body.position.z = _hip_z
	for hn in [_hip_l, _hip_r]:
		hn.rotation.y = 0.0
		hn.rotation.z = 0.0
	_sh_l.rotation.y = 0.0
	_sh_r.rotation.y = 0.0
	_apply_emote(delta)
	_sh_r_z_written = _sh_r.rotation.z


func _apply_emote(delta: float) -> void:
	_touched.clear()
	_pos_w = 0.0
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
		_pos_w = maxf(_pos_w, w)
	if p.has("body_y"):
		body.position.y += float(p["body_y"]) * w
		_pos_w = maxf(_pos_w, w)
	if p.has("ground"):
		_ground_fix(w)
		_pos_w = maxf(_pos_w, w)
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
## (per model: see _build_driver, `_lips`)
const COFFEE_GRIP := Vector3(0.0, -0.03, 0.0)      ## where the hand holds the mug, relative to its origin: under the base


## Arm angles [shoulder x, y, z, elbow x] that put the near edge of the mug rim on the lips at the full sip.
## Two-bone IK in body space, so it holds for every arm length: the elbow stays low and out to the side.
func _coffee_sip_arm() -> Array:
	var tip := Basis(Vector3.RIGHT, COFFEE_TILT) * Vector3(0.0, 0.05, 0.048)       # near rim edge, relative to the mug origin
	var target := _lips - tip + Basis(Vector3.RIGHT, COFFEE_TILT) * COFFEE_GRIP   # where the hand has to be
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
			_hi.position.y = _hi_y + floorf(sin(_pt * 6.0) * 2.0) * 0.012    # steps up and down (retro, not smooth)


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
	sp.position = Vector3(0, _hi_y, 0)
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
	var jk := _node_key(n)
	_touched[jk] = maxf(float(_touched.get(jk, 0.0)), w)
	match axis:
		"x":
			n.rotation.x = lerpf(n.rotation.x, float(p[key]), w)
		"y":
			n.rotation.y = lerpf(n.rotation.y, float(p[key]), w)
		_:
			n.rotation.z = lerpf(n.rotation.z, float(p[key]), w)
