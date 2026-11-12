class_name AvatarKit
extends RefCounted
## Procedural face parts, hair styles and head accessories for the two GLB characters.
##
## Everything is authored in HEAD-BONE space: origin = the origin of the Head bone, axes = the model's plain axes
## (+Y up, -Z = front, +X = the character's left). CharacterModel keeps the head anchor glued to the bone, so all of
## this follows the head exactly. The numbers in FACE were measured on the skinned GLB meshes (metres); change them
## here if a feature ever sits off the surface.
##
##   eye       : centre of the right eye (x is mirrored for the left), z = front surface of the eyeball at that x
##   brow_y/z  : eyebrow height and the forehead surface on the centre line there
##   nose      : tip of the nose (the surface the overlay nose sits on)
##   mouth     : centre of the lips and the face surface there
##   cheek     : centre of the right cheek, z = face surface at that x (blush / freckles)
##   jaw       : [half width, half depth, y] of the jaw line, used by beards
##   dome_*    : hair cap (centre, radii); back_*: the hair mass behind and beside the skull
##   curve     : how fast the face surface falls away sideways (z += curve * x * x)
const FACE := {
	"male": {
		"eye": Vector3(0.036, 0.092, -0.127), "brow_y": 0.126, "brow_z": -0.134,
		"nose": Vector3(0.0, 0.039, -0.150), "mouth": Vector3(0.0, -0.006, -0.139),
		"cheek": Vector3(0.062, 0.030, -0.112), "jaw": Vector2(0.085, 0.105), "jaw_y": -0.030, "curve": 9.0,
		"dome_c": Vector3(0.0, 0.144, -0.008), "dome_r": Vector3(0.115, 0.090, 0.114),
		"back_c": Vector3(0.0, 0.070, 0.012), "back_r": Vector3(0.112, 0.100, 0.115),
		"side_x": 0.113, "back_z": 0.150, "top": 0.171, "skull_rx": 0.106,
		"cap_c": Vector3(0.0, 0.140, -0.008), "cap_r": Vector3(0.126, 0.105, 0.124),
	},
	"female": {
		"eye": Vector3(0.047, 0.117, -0.113), "brow_y": 0.149, "brow_z": -0.118,
		"nose": Vector3(0.0, 0.050, -0.147), "mouth": Vector3(0.0, 0.012, -0.112),
		"cheek": Vector3(0.062, 0.050, -0.100), "jaw": Vector2(0.085, 0.100), "jaw_y": -0.010, "curve": 10.0,
		"dome_c": Vector3(0.0, 0.167, 0.010), "dome_r": Vector3(0.120, 0.090, 0.120),
		"back_c": Vector3(0.0, 0.095, 0.025), "back_r": Vector3(0.115, 0.105, 0.120),
		"side_x": 0.108, "back_z": 0.160, "top": 0.200, "skull_rx": 0.100,
		"cap_c": Vector3(0.0, 0.168, 0.010), "cap_r": Vector3(0.140, 0.105, 0.140),
	},
}

const LIP := Color(0.42, 0.16, 0.16)
const WHITE := Color(0.96, 0.96, 0.96)
const PINK := Color(0.96, 0.60, 0.60)
const FRECKLE := Color(0.55, 0.32, 0.20)

static var _dome_mesh: Mesh


# ---------------------------------------------------------------- small helpers

## Hemisphere (top half) of radius 1, scaled to `radii`.
static func _dome(parent: Node3D, radii: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	if _dome_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 1.0
		sm.is_hemisphere = true
		sm.radial_segments = 10
		sm.rings = 5
		_dome_mesh = LowPoly.flat(sm)
	var mi := MeshInstance3D.new()
	mi.mesh = _dome_mesh
	mi.material_override = LowPoly.material(color)
	mi.position = pos
	mi.scale = radii
	parent.add_child(mi)
	return mi


## Ellipsoid with the given radii.
static func _ell(parent: Node3D, radii: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := LowPoly.sphere(parent, 0.01, color, pos, 8, 5)
	mi.scale = radii / 0.01
	return mi


## A thin box running from point a to point b (frames, whiskers, hair strands...).
static func _bar(parent: Node3D, a: Vector3, b: Vector3, thick: float, color: Color) -> MeshInstance3D:
	var d := b - a
	var dist := maxf(d.length(), 0.001)
	var mi := LowPoly.box(parent, Vector3(thick, thick, dist), color, (a + b) * 0.5)
	var dir := d / dist
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	mi.basis = Basis.looking_at(dir, up)
	return mi


## z of the face surface at sideways offset x, given the surface z at the centre line.
static func _sz(g: Dictionary, z0: float, x: float) -> float:
	return z0 + float(g["curve"]) * x * x


## z of the cheek surface at sideways offset x (the cheek is measured at its own x).
static func _cz(g: Dictionary, x: float) -> float:
	var ck: Vector3 = g["cheek"]
	return ck.z + float(g["curve"]) * (x * x - ck.x * ck.x)


# ---------------------------------------------------------------- face

## Eyebrows, mouth, expression, nose, eye shape and face details. `a` is the appearance dictionary.
static func build_face(parent: Node3D, kind: String, a: Dictionary) -> void:
	var g: Dictionary = FACE[kind]
	var d := AppearanceData.default_for(kind)
	var skin: Color = AppearanceData.SKIN_TONES[int(a["skin_tone"])]
	var hair: Color = AppearanceData.HAIR_COLORS[int(a["hair_color"])]
	var eye_col: Color = AppearanceData.EYE_COLORS[int(a["eye_color"])]
	var expr := int(a["expression"])          # 0 Neutral, 1 Happy, 2 Serious, 3 Surprised
	var eye: Vector3 = g["eye"]

	# Eye shape: the model's own eyes are used for the default shape; any other shape is drawn over them.
	var shape := int(a["eye_shape"])
	if shape != int(d["eye_shape"]) or expr == 3:
		_eyes(parent, g, shape, eye_col, skin, 1.25 if expr == 3 else 1.0)

	# Eyebrows (3 = None)
	var brow := int(a["eyebrows"])
	if brow != 3:
		var raise := 0.0
		var tilt := 0.0
		match expr:
			1: raise = 0.006
			2: tilt = 0.30
			3: raise = 0.020; tilt = -0.10
		for side in [-1, 1]:
			var sd := float(side)
			var bx: float = eye.x * sd
			var by: float = float(g["brow_y"]) + raise
			var bz: float = _sz(g, float(g["brow_z"]), bx) - 0.004
			var ang := tilt * sd
			var w := 0.044
			var th := 0.007
			if brow == 1:
				th = 0.013
				w = 0.048
			elif brow == 2:
				ang += 0.38 * sd
			var mi := LowPoly.box(parent, Vector3(w, th, 0.008), hair, Vector3(bx, by, bz))
			mi.rotation.z = ang
			mi.rotation.y = -sd * 0.20       # follow the curve of the forehead

	# Mouth: the Open style, or an arc built from short segments
	var mouth := int(a["mouth"])
	if expr == 3:
		mouth = 2
	_mouth(parent, g, mouth, expr)

	# Nose: the model's own nose is kept for the default size; other sizes add a nose shape on top.
	var nose := int(a["nose"])
	if nose != int(d["nose"]):
		var n: Vector3 = g["nose"]
		var r := Vector3(0.012, 0.012, 0.012)
		match nose:
			0: r = Vector3(0.009, 0.010, 0.009)
			2: r = Vector3(0.012, 0.022, 0.012)
			3: r = Vector3(0.022, 0.012, 0.012)
		_ell(parent, r, skin.darkened(0.04), n + Vector3(0.0, 0.0, 0.0))

	# Face details (0 None, 1 Freckles, 2 Mustache, 3 Beard, 4 Blush)
	var detail := int(a["face_detail"])
	var ck: Vector3 = g["cheek"]
	var mo: Vector3 = g["mouth"]
	match detail:
		1:
			var spots := [Vector2(0.050, 0.044), Vector2(0.066, 0.036), Vector2(0.058, 0.026), Vector2(0.040, 0.034),
				Vector2(0.074, 0.046), Vector2(0.018, 0.058)]
			for s in spots:
				for side in [-1, 1]:
					var sx: float = s.x * float(side)
					if absf(sx) < 0.03 and side < 0:
						continue
					var sy: float = float(g["eye"].y) - 0.058 + (s.y - 0.040)
					_ell(parent, Vector3(0.004, 0.004, 0.002), FRECKLE, Vector3(sx, sy, _cz(g, sx) - 0.002))
		2:
			for side in [-1, 1]:
				var sd := float(side)
				_bar(parent, Vector3(0.004 * sd, mo.y + 0.020, _sz(g, mo.z, 0.004) - 0.006),
					Vector3(0.036 * sd, mo.y + 0.014, _sz(g, mo.z, 0.036) - 0.006), 0.010, hair)
		3:
			var jw: Vector2 = g["jaw"]
			var jy: float = float(g["jaw_y"])
			for i in 9:
				var ang := -1.25 + float(i) * 0.3125
				var px := jw.x * sin(ang)
				var pz := -jw.y * cos(ang) * 0.95
				var bi := LowPoly.box(parent, Vector3(0.034, 0.075, 0.014), hair, Vector3(px, jy - 0.012, pz - 0.005))
				bi.rotation.y = ang
			_ell(parent, Vector3(0.034, 0.030, 0.018), hair, Vector3(0.0, jy - 0.040, -jw.y * 0.95))
		4:
			for side in [-1, 1]:
				var sd := float(side)
				_ell(parent, Vector3(0.018, 0.011, 0.003), PINK, Vector3(ck.x * sd, ck.y + 0.012, ck.z - 0.002))


static func _eyes(parent: Node3D, g: Dictionary, shape: int, iris: Color, skin: Color, grow: float) -> void:
	var e: Vector3 = g["eye"]
	var rx := 0.021
	var ry := 0.021
	match shape:
		1: rx = 0.027; ry = 0.018      # Wide
		2: rx = 0.025; ry = 0.011      # Narrow
		3: rx = 0.022; ry = 0.017      # Sleepy
	rx *= grow
	ry *= grow
	for side in [-1, 1]:
		var sd := float(side)
		var x := e.x * sd
		var z: float = e.z - 0.006                       # e.z is already the eyeball surface at this x
		_ell(parent, Vector3(rx, ry, 0.004), WHITE, Vector3(x, e.y, z))
		var ir := minf(rx, ry) * 0.78
		_ell(parent, Vector3(ir, ir, 0.004), iris, Vector3(x, e.y, z - 0.003))
		_ell(parent, Vector3(ir * 0.45, ir * 0.45, 0.004), Color(0.05, 0.05, 0.06), Vector3(x, e.y, z - 0.005))
		if shape == 3:    # sleepy: the upper lid comes down over the top of the eye
			var lid := LowPoly.box(parent, Vector3(rx * 2.2, ry * 1.1, 0.006), skin, Vector3(x, e.y + ry * 0.55, z - 0.007))
			lid.rotation.z = 0.0


static func _mouth(parent: Node3D, g: Dictionary, mouth: int, expr: int) -> void:
	var m: Vector3 = g["mouth"]
	if mouth == 2:       # open
		_ell(parent, Vector3(0.019, 0.013, 0.004), LIP.darkened(0.45), Vector3(0.0, m.y - 0.002, _sz(g, m.z, 0.0) - 0.004))
		return
	var amp := 0.0
	var skew := 0.0
	match mouth:
		0: amp = 0.011
		3: amp = 0.012; skew = 1.0
	if expr == 1:
		amp += 0.007
	elif expr == 2:
		amp = 0.0
		skew = 0.0
	var half := 0.026
	var steps := 5
	var prev := Vector3.ZERO
	for i in steps + 1:
		var t := -1.0 + 2.0 * float(i) / float(steps)
		var lift := amp * t * t
		if skew > 0.5:                                   # smirk: only the right side lifts
			lift = amp * t * t if t > 0.0 else -0.002 * t * t
		var p := Vector3(half * t, m.y + lift, _sz(g, m.z, half * t) - 0.004)
		if i > 0:
			_bar(parent, prev, p, 0.0055, LIP)
		prev = p


# ---------------------------------------------------------------- hair

## Hair styles: 0 Short, 1 Long, 2 Curly, 3 Straight, 4 Spiky, 5 Medium, 6 Ponytail. Drawn in place of the model's own hair.
static func build_hair(parent: Node3D, kind: String, style: int, color: Color) -> void:
	var g: Dictionary = FACE[kind]
	var dc: Vector3 = g["dome_c"]
	var dr: Vector3 = g["dome_r"]
	var bc: Vector3 = g["back_c"]
	var br: Vector3 = g["back_r"]
	var sx: float = float(g["side_x"])
	var bz: float = float(g["back_z"])
	var dark := color.darkened(0.12)
	if style == 4:                                       # spiky: a smaller cap with spikes
		dr *= 0.96
	_dome(parent, dr, color, dc)
	_ell(parent, br * (0.94 if style == 4 else 1.0), color, bc)
	match style:
		0:   # Short: a few fringe tufts
			for fx in [-0.05, 0.0, 0.05]:
				LowPoly.box(parent, Vector3(0.05, 0.028, 0.02), dark, Vector3(fx, dc.y - 0.004, _sz(g, float(g["brow_z"]), fx) - 0.004))
		1:   # Long: curtain down the back, long side locks
			LowPoly.box(parent, Vector3(0.23, 0.34, 0.05), color, Vector3(0.0, -0.10, bz))
			for side in [-1, 1]:
				LowPoly.box(parent, Vector3(0.032, 0.30, 0.075), color, Vector3(sx * float(side), -0.08, 0.02))
			for fx in [-0.055, 0.0, 0.055]:
				LowPoly.box(parent, Vector3(0.06, 0.03, 0.02), dark, Vector3(fx, dc.y - 0.004, _sz(g, float(g["brow_z"]), fx) - 0.004))
		2:   # Curly: dome covered with curls
			for ring in 3:
				var el := 0.15 + 0.5 * float(ring)
				var count := 10 - ring * 3
				for i in count:
					var yaw := TAU * (float(i) + 0.5 * float(ring)) / float(count)
					var front := -cos(yaw)
					if front > 0.55 and el < 0.9:
						continue                              # keep the forehead clear
					var p := dc + Vector3(sin(yaw) * cos(el) * (dr.x + 0.006), sin(el) * (dr.y + 0.004), cos(yaw) * cos(el) * (dr.z + 0.006))
					_ell(parent, Vector3(0.034, 0.034, 0.034), color, p)
			for side in [-1, 1]:
				_ell(parent, Vector3(0.036, 0.045, 0.036), color, Vector3(sx * float(side), 0.01, 0.03))
				_ell(parent, Vector3(0.040, 0.040, 0.040), color, Vector3(0.05 * float(side), -0.01, bz - 0.03))
		3:   # Straight: bob to the jaw with a straight fringe
			LowPoly.box(parent, Vector3(0.23, 0.17, 0.05), color, Vector3(0.0, 0.0, bz - 0.01))
			for side in [-1, 1]:
				LowPoly.box(parent, Vector3(0.030, 0.19, 0.08), color, Vector3(sx * float(side), 0.0, 0.015))
			LowPoly.box(parent, Vector3(0.20, 0.032, 0.022), dark, Vector3(0.0, dc.y - 0.012, float(g["brow_z"]) - 0.004))
		4:   # Spiky
			var dirs := [Vector3(0, 1, 0), Vector3(0.7, 0.7, 0), Vector3(-0.7, 0.7, 0), Vector3(0, 0.7, 0.7), Vector3(0, 0.7, -0.45),
				Vector3(0.6, 0.55, 0.5), Vector3(-0.6, 0.55, 0.5), Vector3(0.65, 0.5, -0.4), Vector3(-0.65, 0.5, -0.4)]
			for dv in dirs:
				var dir: Vector3 = (dv as Vector3).normalized()
				var base := dc + Vector3(dir.x * dr.x * 0.9, dir.y * dr.y * 0.95, dir.z * dr.z * 0.9)
				var sp := LowPoly.cylinder(parent, 0.0, 0.028, 0.075, 5, color, base + dir * 0.025)
				sp.basis = Basis(Quaternion(Vector3.UP, dir))
		5:   # Medium: down to the neck
			LowPoly.box(parent, Vector3(0.23, 0.20, 0.05), color, Vector3(0.0, -0.03, bz - 0.005))
			for side in [-1, 1]:
				LowPoly.box(parent, Vector3(0.030, 0.17, 0.08), color, Vector3(sx * float(side), -0.01, 0.02))
			for fx in [-0.05, 0.0, 0.05]:
				LowPoly.box(parent, Vector3(0.055, 0.03, 0.02), dark, Vector3(fx, dc.y - 0.004, _sz(g, float(g["brow_z"]), fx) - 0.004))
		6:   # Ponytail
			_ell(parent, Vector3(0.024, 0.024, 0.024), dark, Vector3(0.0, 0.085, bz - 0.02))
			var tail := LowPoly.cylinder(parent, 0.034, 0.014, 0.21, 6, color, Vector3(0.0, -0.025, bz + 0.005))
			tail.rotation.x = -0.22
			for fx in [-0.05, 0.0, 0.05]:
				LowPoly.box(parent, Vector3(0.05, 0.028, 0.02), dark, Vector3(fx, dc.y - 0.004, _sz(g, float(g["brow_z"]), fx) - 0.004))


# ---------------------------------------------------------------- head accessories

## Glasses: frames built around the real eye positions of the model, with temples running back to the ears.
static func build_glasses(parent: Node3D, kind: String) -> void:
	var g: Dictionary = FACE[kind]
	var e: Vector3 = g["eye"]
	var frame := Color("#1d1d22")
	var hw := 0.030
	var hh := 0.024
	var cz: float = e.z - 0.016                                   # a little in front of the eyeball
	var bridge_z: float = minf(cz, e.z - float(g["curve"]) * e.x * e.x - 0.008)   # and clear of the nose bridge
	for side in [-1, 1]:
		var sd := float(side)
		var cx := e.x * sd
		var tl := Vector3(cx - hw, e.y + hh, cz)
		var tr := Vector3(cx + hw, e.y + hh, cz)
		var bl := Vector3(cx - hw, e.y - hh, cz)
		var br := Vector3(cx + hw, e.y - hh, cz)
		_bar(parent, tl, tr, 0.006, frame)
		_bar(parent, bl, br, 0.006, frame)
		_bar(parent, tl, bl, 0.006, frame)
		_bar(parent, tr, br, 0.006, frame)
		var outer := Vector3(cx + hw * sd, e.y + hh * 0.6, cz)
		var hinge := Vector3(float(g["skull_rx"]) * 1.03 * sd, e.y + hh * 0.6, 0.0)
		_bar(parent, outer, hinge, 0.006, frame)
		_bar(parent, hinge, Vector3(hinge.x, hinge.y - 0.004, 0.035), 0.006, frame)
	_bar(parent, Vector3(-e.x + hw, e.y + 0.010, bridge_z), Vector3(e.x - hw, e.y + 0.010, bridge_z), 0.006, frame)


## Cap: a dome sized to sit over the model's hair, with a brim that follows the forehead.
static func build_cap(parent: Node3D, kind: String, color: Color) -> void:
	var g: Dictionary = FACE[kind]
	var cc: Vector3 = g["cap_c"]
	var cr: Vector3 = g["cap_r"]
	_dome(parent, cr, color, cc)
	var brim := LowPoly.box(parent, Vector3(cr.x * 1.2, 0.012, 0.085), color.darkened(0.15),
		Vector3(0.0, cc.y - 0.004, cc.z - cr.z - 0.035))
	brim.rotation.x = 0.12


# ---------------------------------------------------------------- clothing / limb helpers

## A tapered round tube from point a (radius r0) to point b (radius r1); the points are in the parent's space.
static func tube(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, color: Color) -> MeshInstance3D:
	var d := b - a
	var dist := maxf(d.length(), 0.002)
	var mi := LowPoly.cylinder(parent, r1, r0, dist, 8, color, (a + b) * 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, d / dist))
	return mi


## Radius at height y from a table of [y, radius] rows sorted from the top down.
static func radius_at(table: Array, y: float) -> float:
	if y >= float(table[0][0]):
		return float(table[0][1])
	for i in range(1, table.size()):
		var y1: float = table[i][0]
		if y >= y1:
			var y0: float = table[i - 1][0]
			var t := (y0 - y) / maxf(y0 - y1, 0.0001)
			return lerpf(float(table[i - 1][1]), float(table[i][1]), t)
	return float(table[table.size() - 1][1])
