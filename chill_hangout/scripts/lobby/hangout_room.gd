class_name HangoutRoom
extends Node3D
## The "Chill Hangout" map, built procedurally: 40 x 30 m room, 6 m high.
## Zones (south = entrance): reception, central gathering ring, west lounge, north-east cafe tables,
## north bar with stools. Adds Marker3Ds in group "spawn_points" near the entrance.

const HALF_X := 20.0
const HALF_Z := 15.0
const HEIGHT := 6.0
const WALL_T := 0.4

const WALL_CREAM := Color("#f3e6d0")
const WALL_TEAL := Color("#6bb7b0")
const WALL_CORAL := Color("#e99a82")
const CEILING := Color("#faf3e6")

var _sofa_colors: Array[Color] = [Color("#e0605a"), Color("#4a7fc1"), Color("#7e62c1"), Color("#4dd0c4")]


func _ready() -> void:
	_build_environment()
	_build_shell()
	_build_reception()
	_build_center()
	_build_lounge()
	_build_cafe()
	_build_bar()
	_build_decor()
	_build_lights()
	_build_outdoors()
	_build_spawns()


# ---------------------------------------------------------------- environment & shell

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#6fa8dc")
	sky_mat.sky_horizon_color = Color("#f6d6a8")
	sky_mat.ground_horizon_color = Color("#f6d6a8")
	sky_mat.ground_bottom_color = Color("#8fb98b")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ffeedd")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Low afternoon sun that streams in through the windows.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-22, 150, 0)
	sun.light_color = Color("#fff0d6")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)


func _floor_material() -> StandardMaterial3D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var c := Color("#c9a37a") if ((x >> 3) + (y >> 3)) % 2 == 0 else Color("#b88f66")
			if x % 8 == 0 or y % 8 == 0:
				c = c.darkened(0.12)
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(HALF_X + 0.4, HALF_Z + 0.4, 1)
	m.roughness = 0.9
	return m


func _static_box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = pos
	add_child(b)
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	b.add_child(cs)
	return b


func _build_shell() -> void:
	var fsize := Vector3(HALF_X * 2.0 + 0.8, 0.4, HALF_Z * 2.0 + 0.8)
	var floor_body := _static_box(fsize, Vector3(0, -0.2, 0))
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = fsize
	fm.mesh = bm
	fm.material_override = _floor_material()
	floor_body.add_child(fm)

	var ceil_body := _static_box(Vector3(fsize.x, 0.3, fsize.z), Vector3(0, HEIGHT + 0.15, 0))
	LowPoly.box(ceil_body, Vector3(fsize.x, 0.3, fsize.z), CEILING)
	for x in [-15.0, -7.5, 0.0, 7.5, 15.0]:
		LowPoly.box(self, Vector3(0.35, 0.4, HALF_Z * 2.0), Furniture.WOOD.darkened(0.3), Vector3(x, HEIGHT - 0.2, 0))

	var win := {"w": 4.0, "y0": 1.0, "y1": 3.4}
	# North (teal accent wall) - three big windows.
	_wall(Vector3(0, 0, -HALF_Z - WALL_T / 2.0), HALF_X * 2.0 + 0.8, 0.0, WALL_TEAL,
		[_open(-12.0, win), _open(0.0, win), _open(12.0, win)])
	# South (entrance wall): glass door + two windows.
	_wall(Vector3(0, 0, HALF_Z + WALL_T / 2.0), HALF_X * 2.0 + 0.8, 0.0, WALL_CORAL,
		[_open(0.0, {"w": 3.0, "y0": 0.0, "y1": 3.0}), _open(-12.0, {"w": 3.0, "y0": 1.0, "y1": 3.4}), _open(12.0, {"w": 3.0, "y0": 1.0, "y1": 3.4})])
	# West and east.
	_wall(Vector3(-HALF_X - WALL_T / 2.0, 0, 0), HALF_Z * 2.0, 90.0, WALL_CREAM, [_open(-7.0, win), _open(7.0, win)])
	_wall(Vector3(HALF_X + WALL_T / 2.0, 0, 0), HALF_Z * 2.0, 90.0, WALL_CREAM, [_open(-7.0, win), _open(7.0, win)])

	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Furniture.pillar(self, Vector3(sx * 7.5, 0, sz * 7.0), HEIGHT, Color("#e6d9c0"))


func _open(center: float, d: Dictionary) -> Dictionary:
	return {"c": center, "w": d["w"], "y0": d["y0"], "y1": d["y1"]}


## Wall running along local X (rotated by yaw), with rectangular openings filled by glass.
func _wall(center: Vector3, length: float, yaw_deg: float, color: Color, openings: Array) -> void:
	var root := Node3D.new()
	root.position = center
	root.rotation_degrees.y = yaw_deg
	add_child(root)
	var body := StaticBody3D.new()
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, HEIGHT, WALL_T)
	cs.shape = shape
	cs.position = Vector3(0, HEIGHT / 2.0, 0)
	body.add_child(cs)

	var cursor := -length / 2.0
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.88, 1.0, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	for o in openings:
		var left: float = o["c"] - o["w"] / 2.0
		var right: float = o["c"] + o["w"] / 2.0
		_wall_piece(root, cursor, left, 0.0, HEIGHT, color)
		_wall_piece(root, left, right, 0.0, o["y0"], color)
		_wall_piece(root, left, right, o["y1"], HEIGHT, color)
		var gh: float = o["y1"] - o["y0"]
		var gy: float = o["y0"] + gh / 2.0
		var pane := LowPoly.box(root, Vector3(o["w"], gh, 0.04), Color.WHITE, Vector3(o["c"], gy, 0))
		pane.material_override = glass
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var frame := Furniture.WOOD.darkened(0.3)
		LowPoly.box(root, Vector3(o["w"] + 0.16, 0.08, WALL_T + 0.06), frame, Vector3(o["c"], o["y0"], 0))
		LowPoly.box(root, Vector3(o["w"] + 0.16, 0.08, WALL_T + 0.06), frame, Vector3(o["c"], o["y1"], 0))
		LowPoly.box(root, Vector3(0.08, gh, WALL_T + 0.06), frame, Vector3(left, gy, 0))
		LowPoly.box(root, Vector3(0.08, gh, WALL_T + 0.06), frame, Vector3(right, gy, 0))
		LowPoly.box(root, Vector3(0.05, gh, WALL_T + 0.04), frame, Vector3(o["c"], gy, 0))
		cursor = right
	_wall_piece(root, cursor, length / 2.0, 0.0, HEIGHT, color)
	LowPoly.box(root, Vector3(length, 0.12, WALL_T + 0.04), Furniture.WOOD.darkened(0.2), Vector3(0, 0.06, 0))


func _wall_piece(root: Node3D, a: float, b: float, y0: float, y1: float, color: Color) -> void:
	if b - a < 0.01 or y1 - y0 < 0.01:
		return
	LowPoly.box(root, Vector3(b - a, y1 - y0, WALL_T), color, Vector3((a + b) / 2.0, (y0 + y1) / 2.0, 0))


# ---------------------------------------------------------------- zones

func _build_reception() -> void:
	Furniture.rug_rect(self, Vector3(0, 0, 13.6), Vector2(3.6, 1.8), Color("#3b4780"), Color("#2b3363"))
	Furniture.counter(self, Vector3(0, 0, 8.2), 180.0, 4.6, 1.0, Furniture.WOOD, Color("#e0d3bd"))
	LowPoly.box(self, Vector3(0.6, 1.0, 2.2), Color("#e0d3bd"), Vector3(-2.6, 0.5, 7.2))
	var sider := Furniture._body(self)
	Furniture._box_col(sider, Vector3(0.6, 1.0, 2.2), Vector3(-2.6, 0.5, 7.2))
	LowPoly.box(self, Vector3(0.4, 0.3, 0.05), Color("#2e2e38"), Vector3(0.8, 1.23, 8.0))
	LowPoly.sphere(self, 0.07, Color("#e6cf6a"), Vector3(-0.8, 1.12, 8.4), 6, 3)
	Furniture.plant(self, Vector3(-3.5, 0, 12.8), 1.5)
	Furniture.plant(self, Vector3(3.5, 0, 12.8), 1.5)
	var sign := Label3D.new()
	sign.text = "CHILL HANGOUT"
	sign.font_size = 96
	sign.pixel_size = 0.01
	sign.outline_size = 16
	sign.modulate = Color("#fff3d6")
	sign.outline_modulate = Color("#3b4780")
	sign.position = Vector3(0, 3.9, HALF_Z - 0.06)
	sign.rotation_degrees.y = 180.0
	add_child(sign)
	# Glass door details.
	var door := Furniture.WOOD.darkened(0.3)
	for hx in [-0.25, 0.25]:
		LowPoly.box(self, Vector3(0.05, 0.4, 0.06), door, Vector3(hx, 1.2, HALF_Z - 0.12))


func _build_center() -> void:
	Furniture.rug_round(self, Vector3(0, 0, 0), 5.8, Color("#f4e9d2"), Color("#e8c9a0"))
	Furniture.tree_planter(self, Vector3(0, 0, 0))
	for a in [45.0, 135.0, 225.0, 315.0]:
		var p := Vector3(sin(deg_to_rad(a)), 0, cos(deg_to_rad(a))) * 3.7
		Furniture.bench(self, p, Furniture.yaw_toward(p, Vector3.ZERO), Color("#4a7fc1") if int(a) % 90 == 45 and a < 200.0 else Color("#e0605a"), 2)


func _build_lounge() -> void:
	var c := Vector3(-13, 0, -2)
	Furniture.rug_rect(self, c, Vector2(8.0, 7.0), Color("#7c9aa8"), Color("#4a6070"))
	Furniture.round_table(self, c, 0.7, 0.45, Furniture.WOOD)
	Furniture.sofa(self, c + Vector3(0, 0, -2.2), 180.0, _sofa_colors[1], 3)
	Furniture.sofa(self, c + Vector3(0, 0, 2.2), 0.0, _sofa_colors[0], 3)
	Furniture.sofa(self, c + Vector3(-3.3, 0, 0), -90.0, _sofa_colors[2], 1)
	Furniture.sofa(self, c + Vector3(3.3, 0, 0), 90.0, _sofa_colors[3], 1)
	Furniture.bookshelf(self, Vector3(-19.75, 0, -2.0), -90.0, 3)
	Furniture.floor_lamp(self, Vector3(-17.8, 0, -5.8))
	Furniture.floor_lamp(self, Vector3(-17.8, 0, 2.0))
	Furniture.plant(self, Vector3(-18.6, 0, -13.5), 1.6)
	Furniture.plant(self, Vector3(-18.6, 0, 13.5), 1.6)


func _build_cafe() -> void:
	var chair_colors: Array[Color] = [Color("#e6cf6a"), Color("#4dd0c4"), Color("#e8894a")]
	var tables: Array[Vector3] = [Vector3(9, 0, -9), Vector3(14.5, 0, -9), Vector3(12, 0, -3.5)]
	for i in tables.size():
		var t := tables[i]
		Furniture.round_table(self, t, 0.6, 0.75, Color("#f4f1ea"))
		for off in [Vector3(0, 0, -1.0), Vector3(0, 0, 1.0), Vector3(1.0, 0, 0), Vector3(-1.0, 0, 0)]:
			var p: Vector3 = t + off
			Furniture.chair(self, p, Furniture.yaw_toward(p, t), chair_colors[i])
	Furniture.bench(self, Vector3(19.3, 0, 3.5), 90.0, Color("#7e62c1"), 3)
	Furniture.bench(self, Vector3(19.3, 0, 8.5), 90.0, Color("#7e62c1"), 3)
	Furniture.plant(self, Vector3(18.6, 0, -13.5), 1.6)
	Furniture.plant(self, Vector3(18.6, 0, 13.5), 1.6)
	Furniture.plant(self, Vector3(18.6, 0, 6.0), 1.2)


func _build_bar() -> void:
	Furniture.counter(self, Vector3(0, 0, -12.9), 0.0, 10.0, 0.95, Furniture.WOOD.darkened(0.1), Color("#3b4780"))
	for x in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		Furniture.stool(self, Vector3(x, 0, -11.5), 0.0, Color("#e0605a"))
	for x in [-4.0, 0.0, 4.0]:
		var bulb := LowPoly.sphere(self, 0.18, Color("#ffe6a0"), Vector3(x, 4.2, -12.9), 6, 3)
		Furniture._glow(bulb, Color("#ffe6a0"), 2.0)
		LowPoly.cylinder(self, 0.02, 0.02, 1.4, 4, Furniture.DARK, Vector3(x, 5.0, -12.9))
		var l := OmniLight3D.new()
		l.position = Vector3(x, 4.0, -12.4)
		l.light_color = Color("#ffd98a")
		l.light_energy = 0.8
		l.omni_range = 6.0
		add_child(l)


func _build_decor() -> void:
	var v := 0
	for x in [-6.0, 6.0]:
		Furniture.wall_art(self, Vector3(x, 2.4, -HALF_Z), 180.0, v)
		Furniture.wall_art(self, Vector3(x, 2.4, HALF_Z), 0.0, v + 1)
		v += 1
	for z in [-12.0, 2.5, 12.0]:
		Furniture.wall_art(self, Vector3(-HALF_X, 2.4, z), -90.0, v)
		v += 1
	for z in [-12.0, 0.0, 12.0]:
		Furniture.wall_art(self, Vector3(HALF_X, 2.4, z), 90.0, v)
		v += 1


func _build_lights() -> void:
	for x in [-13.0, 0.0, 13.0]:
		for z in [-9.0, 0.0, 9.0]:
			var disc := LowPoly.cylinder(self, 0.6, 0.6, 0.08, 8, Color("#fff3d6"), Vector3(x, HEIGHT - 0.04, z))
			Furniture._glow(disc, Color("#fff3d6"), 2.5)
			var l := OmniLight3D.new()
			l.position = Vector3(x, HEIGHT - 0.8, z)
			l.light_color = Color("#fff0d6")
			l.light_energy = 0.9
			l.omni_range = 13.0
			add_child(l)


func _build_outdoors() -> void:
	LowPoly.cylinder(self, 150.0, 150.0, 0.4, 16, Color("#6fb26c"), Vector3(0, -0.45, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 40:
		var a := rng.randf() * TAU
		var d := rng.randf_range(26.0, 60.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if absf(p.x) < HALF_X + 3.0 and absf(p.z) < HALF_Z + 3.0:
			continue
		Furniture.outdoor_tree(self, p, rng.randf_range(1.0, 2.0), Color("#4f9d69").lerp(Color("#7fc47a"), rng.randf()))


func _build_spawns() -> void:
	for i in 6:
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = Vector3(-2.5 + i, 0.1, 12.0)
		add_child(m)
		m.add_to_group("spawn_points")
