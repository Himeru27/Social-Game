class_name CharacterModel
extends Node3D
## Low-poly human with real joints, built from an appearance Dictionary (see AppearanceData).
## Faces -Z, origin at the feet. Call rebuild(app) to change look, animate() every frame.
## Procedural animation blends idle -> walk -> run/sprint -> crouch -> crouch-walk.

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
	return _sh_r


func rebuild(app: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_app = AppearanceData.sanitize(app)
	_build(_app)


func _b(parent: Node, size: Vector3, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := LowPoly.box(parent, size, color, pos)
	mi.rotation_degrees = rot_deg
	return mi


func _build(a: Dictionary) -> void:
	var male: bool = a["gender"] == "male"
	var skin: Color = AppearanceData.SKIN_TONES[int(a["skin_tone"])]
	var hair_col: Color = AppearanceData.HAIR_COLORS[int(a["hair_color"])]
	var shirt: Color = AppearanceData.CLOTH_COLORS[int(a["shirt_color"])]
	var pants: Color = AppearanceData.CLOTH_COLORS[int(a["pants_color"])]
	var shoes: Color = AppearanceData.CLOTH_COLORS[int(a["shoes_color"])]
	var leg_k: float = a["leg_length"]
	var arm_k: float = a["arm_length"]
	_thigh = 0.4 * leg_k
	_shin = 0.4 * leg_k
	var ua := 0.3 * arm_k
	var fa := 0.3 * arm_k
	scale = Vector3(a["width"], a["height"], a["thickness"])

	body = Node3D.new()
	body.position.y = _thigh + _shin + SOLE
	add_child(body)

	var tw := 0.5 if male else 0.45
	var hip_x := 0.13 if male else 0.12
	var sh_x := tw / 2.0 + 0.09
	_b(body, Vector3(tw, 0.62, 0.28), shirt, Vector3(0, 0.31, 0))
	_b(body, Vector3(tw + 0.01, 0.1, 0.285), pants, Vector3(0, 0.05, 0))

	var pants_style := int(a["pants_style"])
	var shoe_style := int(a["shoes_style"])
	var shirt_style := int(a["shirt_style"])

	for side in [-1, 1]:
		# ---- leg
		var hip := Node3D.new()
		hip.position = Vector3(hip_x * side, 0, 0)
		body.add_child(hip)
		_b(hip, Vector3(0.22, _thigh, 0.24), pants, Vector3(0, -_thigh / 2.0, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, -_thigh, 0)
		hip.add_child(knee)
		match pants_style:
			0:
				_b(knee, Vector3(0.18, _shin, 0.2), pants, Vector3(0, -_shin / 2.0, 0))
			1:
				_b(knee, Vector3(0.17, _shin, 0.19), skin, Vector3(0, -_shin / 2.0, 0))
			_:
				_b(knee, Vector3(0.17, _shin, 0.19), skin, Vector3(0, -_shin / 2.0, 0))
				_b(knee, Vector3(0.18, _shin * 0.55, 0.2), pants, Vector3(0, -_shin * 0.275, 0))
		match shoe_style:
			0:
				_b(knee, Vector3(0.2, 0.1, 0.3), shoes, Vector3(0, -_shin + 0.03, -0.04))
			1:
				_b(knee, Vector3(0.2, 0.1, 0.3), shoes, Vector3(0, -_shin + 0.03, -0.04))
				_b(knee, Vector3(0.2, 0.16, 0.21), shoes, Vector3(0, -_shin + 0.12, 0.0))
			_:
				_b(knee, Vector3(0.2, 0.03, 0.3), shoes, Vector3(0, -_shin - 0.005, -0.04))
				_b(knee, Vector3(0.16, 0.05, 0.26), skin, Vector3(0, -_shin + 0.035, -0.04))

		# ---- arm
		var sh := Node3D.new()
		sh.position = Vector3(sh_x * side, 0.56, 0)
		body.add_child(sh)
		_b(sh, Vector3(0.14, ua, 0.15), skin, Vector3(0, 0.02 - ua / 2.0, 0))
		_fore = fa
		var elb := Node3D.new()
		elb.position = Vector3(0, 0.02 - ua, 0)
		sh.add_child(elb)
		_b(elb, Vector3(0.12, fa, 0.13), skin, Vector3(0, -fa / 2.0, 0))
		match shirt_style:
			0:
				var sl := ua * 0.55
				_b(sh, Vector3(0.16, sl, 0.17), shirt, Vector3(0, 0.02 - sl / 2.0, 0))
			1:
				_b(sh, Vector3(0.16, ua, 0.17), shirt, Vector3(0, 0.02 - ua / 2.0, 0))
				var fl := fa - 0.07
				_b(elb, Vector3(0.14, fl, 0.15), shirt, Vector3(0, -fl / 2.0, 0))

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

	_b(body, Vector3(0.1, 0.1, 0.1), skin, Vector3(0, 0.67, 0))
	_b(body, Vector3(0.3, 0.34, 0.3), skin, Vector3(0, 0.9, 0))
	_build_face(a, skin, hair_col)
	_build_hair(int(a["hair_style"]), hair_col)
	_build_accessories(int(a["accessories"]), AppearanceData.CLOTH_COLORS[int(a["accessory_color"])])


func _build_face(a: Dictionary, skin: Color, hair_col: Color) -> void:
	var dark := Color("#2a2420")
	var eye_col: Color = AppearanceData.EYE_COLORS[int(a["eye_color"])]
	var ew := 0.05
	var eh := 0.05
	var ey := 0.92
	match int(a["eye_shape"]):
		1:
			ew = 0.07
		2:
			ew = 0.07
			eh = 0.025
		3:
			ew = 0.06
			eh = 0.03
			ey = 0.915
	var expr := int(a["expression"])
	if expr == 3:
		eh *= 1.35

	var brow_style := int(a["eyebrows"])
	var brow_size := Vector3(0.075, 0.012, 0.012)
	var inner_low := 0.0
	match brow_style:
		1:
			brow_size = Vector3(0.08, 0.026, 0.012)
		2:
			brow_size = Vector3(0.075, 0.016, 0.012)
			inner_low = 0.25
	var raise := 0.0
	match expr:
		1:
			raise = 0.012
		2:
			raise = -0.008
			inner_low += 0.28
		3:
			raise = 0.03

	for side in [-1, 1]:
		var ex: float = 0.075 * side
		_b(body, Vector3(ew + 0.012, eh + 0.012, 0.01), Color.WHITE, Vector3(ex, ey, -0.1505))
		_b(body, Vector3(ew * 0.55, eh * 0.95, 0.012), eye_col, Vector3(ex, ey, -0.1512))
		_b(body, Vector3(ew * 0.25, eh * 0.5, 0.013), dark, Vector3(ex, ey, -0.1518))
		if brow_style != 3:
			_b(body, brow_size, hair_col.darkened(0.1), Vector3(ex, 0.985 + raise, -0.153), Vector3(0, 0, rad_to_deg(inner_low * side)))

	var nose_col := skin.darkened(0.08)
	match int(a["nose"]):
		0:
			_b(body, Vector3(0.04, 0.05, 0.04), nose_col, Vector3(0, 0.87, -0.16))
		1:
			_b(body, Vector3(0.05, 0.07, 0.06), nose_col, Vector3(0, 0.87, -0.165))
		2:
			_b(body, Vector3(0.045, 0.1, 0.07), nose_col, Vector3(0, 0.86, -0.17))
		_:
			_b(body, Vector3(0.09, 0.04, 0.04), nose_col, Vector3(0, 0.86, -0.16))

	var lip := Color("#7a3b3b")
	match int(a["mouth"]):
		0:
			_b(body, Vector3(0.07, 0.014, 0.01), lip, Vector3(0, 0.805, -0.1525))
			_b(body, Vector3(0.02, 0.014, 0.01), lip, Vector3(-0.045, 0.82, -0.1525))
			_b(body, Vector3(0.02, 0.014, 0.01), lip, Vector3(0.045, 0.82, -0.1525))
		1:
			_b(body, Vector3(0.08, 0.014, 0.01), lip, Vector3(0, 0.81, -0.1525))
		2:
			_b(body, Vector3(0.06, 0.04, 0.01), dark, Vector3(0, 0.805, -0.1525))
			_b(body, Vector3(0.04, 0.015, 0.011), Color("#c4574f"), Vector3(0, 0.795, -0.1528))
		_:
			_b(body, Vector3(0.06, 0.014, 0.01), lip, Vector3(-0.01, 0.81, -0.1525))
			_b(body, Vector3(0.02, 0.014, 0.01), lip, Vector3(0.05, 0.825, -0.1525))

	match int(a["face_detail"]):
		1:
			var fk := skin.darkened(0.28)
			for p in [Vector2(-0.1, 0.87), Vector2(-0.075, 0.855), Vector2(-0.055, 0.875), Vector2(0.1, 0.87), Vector2(0.075, 0.855), Vector2(0.055, 0.875)]:
				_b(body, Vector3(0.014, 0.014, 0.01), fk, Vector3(p.x, p.y, -0.1505))
		2:
			_b(body, Vector3(0.11, 0.022, 0.02), hair_col, Vector3(0, 0.845, -0.158))
		3:
			_b(body, Vector3(0.32, 0.08, 0.32), hair_col, Vector3(0, 0.77, 0.0))
		4:
			for sx in [-0.09, 0.09]:
				_b(body, Vector3(0.055, 0.03, 0.01), Color("#f08a8a"), Vector3(sx, 0.86, -0.1505))


func _build_hair(style: int, c: Color) -> void:
	var top := Vector3(0.34, 0.1, 0.34)
	match style:
		0: # short
			_b(body, top, c, Vector3(0, 1.08, 0))
			_b(body, Vector3(0.34, 0.08, 0.06), c, Vector3(0, 1.02, -0.14))
			_b(body, Vector3(0.34, 0.2, 0.1), c, Vector3(0, 0.95, 0.13))
		1: # long
			_b(body, top, c, Vector3(0, 1.08, 0))
			_b(body, Vector3(0.34, 0.08, 0.06), c, Vector3(0, 1.02, -0.14))
			_b(body, Vector3(0.36, 0.55, 0.1), c, Vector3(0, 0.72, 0.15))
			_b(body, Vector3(0.06, 0.4, 0.28), c, Vector3(-0.17, 0.8, 0.02))
			_b(body, Vector3(0.06, 0.4, 0.28), c, Vector3(0.17, 0.8, 0.02))
		2: # curly
			for p in [Vector3(0, 1.12, 0), Vector3(-0.14, 1.06, 0), Vector3(0.14, 1.06, 0), Vector3(-0.17, 0.95, 0.06),
					Vector3(0.17, 0.95, 0.06), Vector3(0, 1.05, 0.15), Vector3(-0.09, 1.04, 0.12), Vector3(0.09, 1.04, 0.12),
					Vector3(0, 1.06, -0.13), Vector3(-0.1, 1.07, -0.1), Vector3(0.1, 1.07, -0.1)]:
				LowPoly.sphere(body, 0.1, c, p, 6, 3)
		3: # straight
			_b(body, top, c, Vector3(0, 1.08, 0))
			_b(body, Vector3(0.34, 0.14, 0.06), c, Vector3(0, 0.99, -0.14))
			_b(body, Vector3(0.05, 0.3, 0.3), c, Vector3(-0.175, 0.88, 0.0))
			_b(body, Vector3(0.05, 0.3, 0.3), c, Vector3(0.175, 0.88, 0.0))
			_b(body, Vector3(0.36, 0.34, 0.08), c, Vector3(0, 0.88, 0.16))
		4: # spiky
			_b(body, Vector3(0.34, 0.06, 0.34), c, Vector3(0, 1.06, 0))
			_b(body, Vector3(0.34, 0.16, 0.08), c, Vector3(0, 0.97, 0.14))
			for p in [Vector3(0, 1.17, 0), Vector3(-0.1, 1.15, -0.08), Vector3(0.1, 1.15, -0.08), Vector3(-0.11, 1.15, 0.08),
					Vector3(0.11, 1.15, 0.08), Vector3(0, 1.14, -0.13), Vector3(0, 1.14, 0.13)]:
				LowPoly.cylinder(body, 0.0, 0.07, 0.2, 5, c, p)
		5: # medium
			_b(body, top, c, Vector3(0, 1.08, 0))
			_b(body, Vector3(0.34, 0.08, 0.06), c, Vector3(0, 1.02, -0.14))
			_b(body, Vector3(0.36, 0.34, 0.1), c, Vector3(0, 0.86, 0.15))
			_b(body, Vector3(0.05, 0.2, 0.26), c, Vector3(-0.175, 0.93, 0.02))
			_b(body, Vector3(0.05, 0.2, 0.26), c, Vector3(0.175, 0.93, 0.02))
		_: # ponytail
			_b(body, top, c, Vector3(0, 1.08, 0))
			_b(body, Vector3(0.34, 0.08, 0.06), c, Vector3(0, 1.02, -0.14))
			_b(body, Vector3(0.34, 0.25, 0.1), c, Vector3(0, 0.93, 0.13))
			_b(body, Vector3(0.1, 0.32, 0.1), c, Vector3(0, 0.82, 0.24), Vector3(20, 0, 0))
			_b(body, Vector3(0.12, 0.04, 0.12), c.darkened(0.3), Vector3(0, 0.97, 0.2))


func _build_accessories(bits: int, col: Color) -> void:
	if bits & 1: # glasses
		var frame := Color("#1d1d22")
		for side in [-1, 1]:
			var gx: float = 0.075 * side
			_b(body, Vector3(0.1, 0.012, 0.012), frame, Vector3(gx, 0.955, -0.158))
			_b(body, Vector3(0.1, 0.012, 0.012), frame, Vector3(gx, 0.885, -0.158))
			_b(body, Vector3(0.012, 0.07, 0.012), frame, Vector3(gx - 0.05, 0.92, -0.158))
			_b(body, Vector3(0.012, 0.07, 0.012), frame, Vector3(gx + 0.05, 0.92, -0.158))
		_b(body, Vector3(0.03, 0.012, 0.012), frame, Vector3(0, 0.935, -0.158))
	if bits & 2: # cap
		_b(body, Vector3(0.37, 0.1, 0.37), col, Vector3(0, 1.12, 0))
		_b(body, Vector3(0.3, 0.02, 0.18), col.darkened(0.15), Vector3(0, 1.07, -0.24))
	if bits & 4: # backpack
		_b(body, Vector3(0.34, 0.4, 0.14), col, Vector3(0, 0.35, 0.21))
		for sx in [-0.14, 0.14]:
			_b(body, Vector3(0.05, 0.5, 0.02), col.darkened(0.2), Vector3(sx, 0.33, -0.15))
	if bits & 8: # scarf
		_b(body, Vector3(0.34, 0.1, 0.34), col, Vector3(0, 0.62, 0))
		_b(body, Vector3(0.1, 0.28, 0.05), col, Vector3(0.1, 0.45, -0.16))


## speed = horizontal speed in m/s. Parameters are smoothed, so state changes blend.
func animate(delta: float, speed: float, crouching: bool, sitting: bool = false) -> void:
	_t += delta
	var seat_h := sit_height
	if _emote == NetProtocol.EMOTE_SIT:
		sitting = true
		seat_h = 0.04          # sit on the floor
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
	_apply_emote(delta)


func _apply_emote(delta: float) -> void:
	_pt += delta
	if _emote >= 0:
		var e: Dictionary = NetProtocol.EMOTES[_emote]
		if not e["loop"] and _pt >= float(e["dur"]):
			_emote = -1
			emote_ended.emit()
	_ew = move_toward(_ew, 1.0 if _emote >= 0 else 0.0, delta * 5.0)
	if _ew <= 0.0 or _pose < 0:
		return
	var w := smoothstep(0.0, 1.0, _ew)
	var t := _pt
	var p := {}
	match _pose:
		NetProtocol.EMOTE_WAVE:
			p = {"shr_z": 2.75, "shr_x": 0.0, "elr_z": sin(t * 9.0) * 0.55, "elr_x": 0.15}
		NetProtocol.EMOTE_DANCE:
			var s := sin(t * 5.5)
			p = {"body_y": absf(s) * 0.06, "body_z": s * 0.1, "shl_z": -(1.9 + 0.5 * s), "shr_z": 1.9 - 0.5 * s,
				"shl_x": 0.0, "shr_x": 0.0, "ell_x": 0.6, "elr_x": 0.6, "hipl_x": s * 0.45, "hipr_x": -s * 0.45,
				"kneel_x": -maxf(0.0, s) * 0.7, "kneer_x": -maxf(0.0, -s) * 0.7}
		NetProtocol.EMOTE_SIT:
			p = {"body_z": sin(t * 1.2) * 0.02}
		NetProtocol.EMOTE_LAUGH:
			p = {"body_x": 0.12, "body_y": absf(sin(t * 22.0)) * 0.025, "body_z": sin(t * 18.0) * 0.04,
				"shl_x": 0.8, "ell_x": 1.5, "shr_x": 0.5, "shr_z": 0.4, "elr_x": 1.2}
		NetProtocol.EMOTE_GREETING:
			var dur := float(NetProtocol.EMOTES[NetProtocol.EMOTE_GREETING]["dur"])
			var bow := sin(clampf(t / dur, 0.0, 1.0) * PI)
			p = {"shl_z": -1.1, "shr_z": 1.1, "shl_x": 0.5, "shr_x": 0.5, "ell_x": 0.5 + sin(t * 4.0) * 0.1,
				"elr_x": 0.5 + sin(t * 4.0) * 0.1, "body_x": -0.3 * bow}
	_mix(_sh_l, "x", p, "shl_x", w)
	_mix(_sh_l, "z", p, "shl_z", w)
	_mix(_sh_r, "x", p, "shr_x", w)
	_mix(_sh_r, "z", p, "shr_z", w)
	_mix(_elb_l, "x", p, "ell_x", w)
	_mix(_elb_r, "x", p, "elr_x", w)
	_mix(_elb_r, "z", p, "elr_z", w)
	_mix(body, "x", p, "body_x", w)
	_mix(body, "z", p, "body_z", w)
	_mix(_hip_l, "x", p, "hipl_x", w)
	_mix(_hip_r, "x", p, "hipr_x", w)
	_mix(_knee_l, "x", p, "kneel_x", w)
	_mix(_knee_r, "x", p, "kneer_x", w)
	if p.has("body_y"):
		body.position.y += float(p["body_y"]) * w


func _mix(n: Node3D, axis: String, p: Dictionary, key: String, w: float) -> void:
	if not p.has(key):
		return
	var cur: float = n.rotation.x if axis == "x" else n.rotation.z
	var v := lerpf(cur, float(p[key]), w)
	if axis == "x":
		n.rotation.x = v
	else:
		n.rotation.z = v
