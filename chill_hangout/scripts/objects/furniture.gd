class_name Furniture
extends RefCounted
## Procedural low-poly furniture with collision. Conventions: the object's FRONT faces local -Z
## (seats face -Z). To make something at position p face point t, use yaw_toward(p, t).

const WOOD := Color("#8b5e3c")
const DARK := Color("#3b3f4a")


## Yaw (degrees) that makes an object's -Z front face from `from` toward `to` (XZ plane).
static func yaw_toward(from: Vector3, to: Vector3) -> float:
	var d := from - to
	return rad_to_deg(atan2(d.x, d.z))


static func _root(parent: Node3D, pos: Vector3, yaw_deg: float) -> Node3D:
	var r := Node3D.new()
	r.position = pos
	r.rotation_degrees.y = yaw_deg
	parent.add_child(r)
	return r


static func _body(parent: Node3D) -> StaticBody3D:
	var b := StaticBody3D.new()
	parent.add_child(b)
	return b


static func _box_col(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	body.add_child(cs)


static func _cyl_col(body: StaticBody3D, radius: float, height: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	cs.shape = s
	cs.position = pos
	body.add_child(cs)


static func _glow(mi: MeshInstance3D, color: Color, energy: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _seat(root: Node3D, local_pos: Vector3, height: float) -> Seat:
	var s := Seat.new()
	s.position = local_pos
	s.seat_height = height
	root.add_child(s)
	return s


static func chair(parent: Node3D, pos: Vector3, yaw_deg: float, color: Color) -> Node3D:
	var root := _root(parent, pos, yaw_deg)
	LowPoly.box(root, Vector3(0.5, 0.06, 0.5), color, Vector3(0, 0.42, 0))
	for x in [-0.21, 0.21]:
		for z in [-0.21, 0.21]:
			LowPoly.box(root, Vector3(0.05, 0.39, 0.05), WOOD, Vector3(x, 0.195, z))
	LowPoly.box(root, Vector3(0.5, 0.45, 0.05), color, Vector3(0, 0.68, 0.225))
	var body := _body(root)
	_box_col(body, Vector3(0.5, 0.45, 0.5), Vector3(0, 0.225, 0))
	_box_col(body, Vector3(0.5, 0.5, 0.06), Vector3(0, 0.7, 0.225))
	_seat(root, Vector3(0, 0, 0.05), 0.45)
	return root


static func stool(parent: Node3D, pos: Vector3, yaw_deg: float, color: Color) -> Node3D:
	var root := _root(parent, pos, yaw_deg)
	LowPoly.cylinder(root, 0.22, 0.22, 0.06, 8, color, Vector3(0, 0.62, 0))
	LowPoly.cylinder(root, 0.04, 0.04, 0.6, 6, DARK, Vector3(0, 0.3, 0))
	LowPoly.cylinder(root, 0.2, 0.2, 0.04, 8, DARK, Vector3(0, 0.02, 0))
	var body := _body(root)
	_box_col(body, Vector3(0.44, 0.65, 0.44), Vector3(0, 0.325, 0))
	_seat(root, Vector3(0, 0, 0), 0.65)
	return root


## seats = 1 gives an armchair, 2-3 a sofa. One Seat per cushion.
static func sofa(parent: Node3D, pos: Vector3, yaw_deg: float, color: Color, seats: int = 3) -> Node3D:
	var root := _root(parent, pos, yaw_deg)
	var w := 0.4 + 0.8 * seats
	var dark := color.darkened(0.15)
	LowPoly.box(root, Vector3(w, 0.3, 0.9), dark, Vector3(0, 0.15, 0))
	for i in seats:
		var x := (i - (seats - 1) * 0.5) * 0.8
		LowPoly.box(root, Vector3(0.78, 0.15, 0.7), color, Vector3(x, 0.375, -0.05))
		_seat(root, Vector3(x, 0, 0.1), 0.45)
	LowPoly.box(root, Vector3(w, 0.55, 0.2), color, Vector3(0, 0.575, 0.35))
	for sx in [-1.0, 1.0]:
		LowPoly.box(root, Vector3(0.2, 0.55, 0.9), dark, Vector3(sx * (w / 2.0 - 0.1), 0.275, 0))
	var body := _body(root)
	_box_col(body, Vector3(w, 0.45, 0.9), Vector3(0, 0.225, 0))
	_box_col(body, Vector3(w, 0.6, 0.2), Vector3(0, 0.6, 0.35))
	return root


static func bench(parent: Node3D, pos: Vector3, yaw_deg: float, color: Color, seats: int = 2) -> Node3D:
	var root := _root(parent, pos, yaw_deg)
	var w := 0.8 * seats
	LowPoly.box(root, Vector3(w, 0.08, 0.5), color, Vector3(0, 0.41, 0))
	for sx in [-1.0, 1.0]:
		LowPoly.box(root, Vector3(0.08, 0.37, 0.44), WOOD, Vector3(sx * (w / 2.0 - 0.1), 0.185, 0))
	var body := _body(root)
	_box_col(body, Vector3(w, 0.45, 0.5), Vector3(0, 0.225, 0))
	for i in seats:
		_seat(root, Vector3((i - (seats - 1) * 0.5) * 0.8, 0, 0), 0.45)
	return root


static func round_table(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color) -> Node3D:
	var root := _root(parent, pos, 0.0)
	LowPoly.cylinder(root, radius, radius, 0.06, 8, color, Vector3(0, height - 0.03, 0))
	LowPoly.cylinder(root, 0.05, 0.07, height - 0.06, 6, DARK, Vector3(0, (height - 0.06) / 2.0, 0))
	LowPoly.cylinder(root, radius * 0.45, radius * 0.45, 0.04, 8, DARK, Vector3(0, 0.02, 0))
	var body := _body(root)
	_cyl_col(body, radius, height, Vector3(0, height / 2.0, 0))
	return root


static func plant(parent: Node3D, pos: Vector3, s: float = 1.0) -> Node3D:
	var root := _root(parent, pos, 0.0)
	LowPoly.cylinder(root, 0.26 * s, 0.2 * s, 0.4 * s, 7, Color("#c8704a"), Vector3(0, 0.2 * s, 0))
	LowPoly.cylinder(root, 0.24 * s, 0.24 * s, 0.04, 7, Color("#4a3a2a"), Vector3(0, 0.4 * s, 0))
	for i in 6:
		var a := i * TAU / 6.0
		var green := Color("#4f9d69").lerp(Color("#7fc47a"), i / 5.0)
		var leaf := LowPoly.cylinder(root, 0.0, 0.13 * s, 0.9 * s, 4, green, Vector3(cos(a) * 0.12 * s, 0.85 * s, sin(a) * 0.12 * s))
		leaf.rotation.z = -cos(a) * 0.4
		leaf.rotation.x = sin(a) * 0.4
	var body := _body(root)
	_cyl_col(body, 0.3 * s, 1.0 * s, Vector3(0, 0.5 * s, 0))
	return root


static func tree_planter(parent: Node3D, pos: Vector3, radius: float = 1.4) -> Node3D:
	var root := _root(parent, pos, 0.0)
	LowPoly.cylinder(root, radius, radius + 0.1, 0.5, 10, Color("#9aa0a6"), Vector3(0, 0.25, 0))
	LowPoly.cylinder(root, radius - 0.1, radius - 0.1, 0.04, 10, Color("#5a4632"), Vector3(0, 0.5, 0))
	LowPoly.cylinder(root, 0.18, 0.28, 2.6, 6, WOOD, Vector3(0, 1.8, 0))
	LowPoly.sphere(root, 1.4, Color("#5aab6e"), Vector3(0, 3.7, 0), 7, 4)
	LowPoly.sphere(root, 1.0, Color("#6dbb78"), Vector3(0.9, 3.0, 0.3), 6, 3)
	LowPoly.sphere(root, 0.9, Color("#4f9d69"), Vector3(-0.8, 3.1, -0.4), 6, 3)
	var body := _body(root)
	_cyl_col(body, radius, 0.6, Vector3(0, 0.3, 0))
	_cyl_col(body, 0.3, 3.0, Vector3(0, 1.5, 0))
	return root


static func floor_lamp(parent: Node3D, pos: Vector3) -> Node3D:
	var root := _root(parent, pos, 0.0)
	LowPoly.cylinder(root, 0.03, 0.03, 1.6, 6, DARK, Vector3(0, 0.8, 0))
	LowPoly.cylinder(root, 0.18, 0.18, 0.04, 8, DARK, Vector3(0, 0.02, 0))
	var shade := LowPoly.cylinder(root, 0.15, 0.3, 0.35, 8, Color("#ffe6a0"), Vector3(0, 1.75, 0))
	_glow(shade, Color("#ffe6a0"), 1.5)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.8, 0)
	light.light_color = Color("#ffd98a")
	light.light_energy = 0.9
	light.omni_range = 6.0
	root.add_child(light)
	var body := _body(root)
	_cyl_col(body, 0.2, 1.9, Vector3(0, 0.95, 0))
	return root


static func bookshelf(parent: Node3D, pos: Vector3, yaw_deg: float, seed_val: int = 1) -> Node3D:
	var root := _root(parent, pos, yaw_deg)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for sx in [-0.97, 0.97]:
		LowPoly.box(root, Vector3(0.06, 2.2, 0.4), WOOD, Vector3(sx, 1.1, 0))
	LowPoly.box(root, Vector3(2.0, 2.2, 0.04), WOOD.darkened(0.2), Vector3(0, 1.1, 0.18))
	var palette: Array[Color] = [Color("#e0605a"), Color("#4a7fc1"), Color("#e6cf6a"), Color("#6fb26c"), Color("#7e62c1"), Color("#f4f1ea")]
	for i in 5:
		var y := 0.05 + i * 0.5
		LowPoly.box(root, Vector3(1.9, 0.04, 0.38), WOOD, Vector3(0, y, 0))
		if i == 4:
			continue
		var x := -0.88
		while x < 0.82:
			var bw := rng.randf_range(0.05, 0.1)
			var bh := rng.randf_range(0.26, 0.4)
			if rng.randf() < 0.85:
				LowPoly.box(root, Vector3(bw, bh, 0.26), palette[rng.randi() % palette.size()], Vector3(x + bw / 2.0, y + 0.02 + bh / 2.0, 0.02))
			x += bw + 0.01
	var body := _body(root)
	_box_col(body, Vector3(2.0, 2.2, 0.4), Vector3(0, 1.1, 0))
	return root


static func rug_round(parent: Node3D, pos: Vector3, radius: float, color: Color, color2: Color) -> void:
	LowPoly.cylinder(parent, radius, radius, 0.02, 12, color, pos + Vector3(0, 0.01, 0))
	LowPoly.cylinder(parent, radius * 0.7, radius * 0.7, 0.022, 12, color2, pos + Vector3(0, 0.011, 0))


static func rug_rect(parent: Node3D, pos: Vector3, size: Vector2, color: Color, border: Color) -> void:
	LowPoly.box(parent, Vector3(size.x, 0.02, size.y), border, pos + Vector3(0, 0.01, 0))
	LowPoly.box(parent, Vector3(size.x - 0.5, 0.022, size.y - 0.5), color, pos + Vector3(0, 0.011, 0))


static func pillar(parent: Node3D, pos: Vector3, height: float, color: Color) -> Node3D:
	var root := _root(parent, pos, 0.0)
	LowPoly.cylinder(root, 0.35, 0.38, height, 8, color, Vector3(0, height / 2.0, 0))
	LowPoly.cylinder(root, 0.45, 0.45, 0.2, 8, color.darkened(0.15), Vector3(0, 0.1, 0))
	var body := _body(root)
	_cyl_col(body, 0.4, height, Vector3(0, height / 2.0, 0))
	return root


## Front faces -Z. Mount with the back against a wall.
static func wall_art(parent: Node3D, pos: Vector3, yaw_deg: float, variant: int) -> Node3D:
	var root := _root(parent, pos, yaw_deg)
	var sets: Array = [
		[Color("#f6d6a8"), Color("#e0605a"), Color("#4a7fc1")],
		[Color("#cfe8e4"), Color("#4dd0c4"), Color("#e6cf6a")],
		[Color("#e9dcf5"), Color("#7e62c1"), Color("#d65fa0")],
	]
	var c: Array = sets[variant % sets.size()]
	LowPoly.box(root, Vector3(1.4, 1.0, 0.06), WOOD.darkened(0.25), Vector3(0, 0, -0.03))
	LowPoly.box(root, Vector3(1.24, 0.84, 0.07), c[0], Vector3(0, 0, -0.035))
	LowPoly.sphere(root, 0.2, c[1], Vector3(-0.25, 0.12, -0.07), 6, 3)
	LowPoly.box(root, Vector3(0.7, 0.12, 0.02), c[2], Vector3(0.1, -0.2, -0.075))
	LowPoly.box(root, Vector3(0.12, 0.4, 0.02), c[1], Vector3(0.4, 0.1, -0.075))
	return root


static func counter(parent: Node3D, pos: Vector3, yaw_deg: float, length: float, height: float, top_color: Color, body_color: Color) -> Node3D:
	var root := _root(parent, pos, yaw_deg)
	LowPoly.box(root, Vector3(length, height, 0.7), body_color, Vector3(0, height / 2.0, 0))
	LowPoly.box(root, Vector3(length + 0.2, 0.08, 1.0), top_color, Vector3(0, height + 0.04, 0))
	var body := _body(root)
	_box_col(body, Vector3(length + 0.2, height + 0.08, 1.0), Vector3(0, (height + 0.08) / 2.0, 0))
	return root


static func outdoor_tree(parent: Node3D, pos: Vector3, s: float, green: Color) -> void:
	var root := _root(parent, pos, 0.0)
	root.scale = Vector3.ONE * s
	LowPoly.cylinder(root, 0.18, 0.24, 1.2, 6, Color("#7a5a3a"), Vector3(0, 0.6, 0))
	LowPoly.cylinder(root, 0.0, 1.2, 1.8, 6, green, Vector3(0, 2.0, 0))
	LowPoly.cylinder(root, 0.0, 0.9, 1.5, 6, green.lightened(0.08), Vector3(0, 3.0, 0))
