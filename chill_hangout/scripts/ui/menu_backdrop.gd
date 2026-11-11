class_name MenuBackdrop
extends Node3D
## Bright low-poly backdrop for the main menu: sky, sun, grassy + rocky terrain,
## scattered rocks and drifting clouds. Built entirely in code (no assets).
## The origin is the character's feet. Trees are added by MainMenu itself.

const GRASS_A := Color("#6fcf4a")
const GRASS_B := Color("#9be35b")
const ROCK_A := Color("#8d9199")
const ROCK_B := Color("#b9bdc4")
const GRAVEL := Color("#a7a79b")
const HAZE := Color("#cfe9ff")

const TERRAIN_SIZE := 260.0
const CELL := 3.0
const CLEAR_RADIUS := 14.0     # flat ground around the character / camera orbit
const HILL_HEIGHT := 4.0       # kept low so hills never hide the sky from the low camera

## Rotate this around Y together with the camera so the visible side is always sunlit.
var sun_rig: Node3D

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _patch := FastNoiseLite.new()
var _clouds: Array[Node3D] = []


func _ready() -> void:
	_rng.seed = 1960
	_noise.seed = 7
	_noise.frequency = 0.022
	_noise.fractal_octaves = 3
	_patch.seed = 21
	_patch.frequency = 0.09
	_build_environment()
	_build_sun()
	_build_ground()
	_scatter_rocks()
	_build_clouds()


func _process(delta: float) -> void:
	for c in _clouds:
		c.position.x += float(c.get_meta("speed")) * delta
		if c.position.x > 160.0:
			c.position.x = -160.0


## Terrain height at a world x/z (flat near the origin). Used to plant trees.
func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var flat := smoothstep(CLEAR_RADIUS, CLEAR_RADIUS + 25.0, d)
	return (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * HILL_HEIGHT * flat


# ---------------------------------------------------------------- sky / light

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3d8bff")
	sky_mat.sky_horizon_color = HAZE
	sky_mat.ground_horizon_color = HAZE
	sky_mat.ground_bottom_color = HAZE
	sky_mat.sky_curve = 0.18
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = HAZE
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_sun() -> void:
	sun_rig = Node3D.new()
	add_child(sun_rig)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_color = Color("#fff1d6")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun_rig.add_child(sun)


# --------------------------------------------------------------------- ground

func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat shading = low-poly look
	var n := int(TERRAIN_SIZE / CELL)
	var half := TERRAIN_SIZE * 0.5
	for i in n:
		for j in n:
			var x0 := -half + i * CELL
			var z0 := -half + j * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			var p00 := Vector3(x0, height_at(x0, z0), z0)
			var p10 := Vector3(x1, height_at(x1, z0), z0)
			var p11 := Vector3(x1, height_at(x1, z1), z1)
			var p01 := Vector3(x0, height_at(x0, z1), z1)
			_add_tri(st, p00, p10, p11)
			_add_tri(st, p00, p11, p01)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (c - a).cross(b - a).normalized()
	var center := (a + b + c) / 3.0
	var grass := GRASS_A.lerp(GRASS_B, _rng.randf())
	var rock := ROCK_A.lerp(ROCK_B, _rng.randf())
	var col := grass
	# Stony patches on the flat ground plus rocky slopes on the hills.
	var patch := smoothstep(0.28, 0.42, _patch.get_noise_2d(center.x, center.z))
	var steep := smoothstep(0.08, 0.2, 1.0 - nrm.y)
	col = col.lerp(GRAVEL.lerp(rock, _rng.randf()), maxf(patch, steep))
	if _rng.randf() > 0.5:
		col = col.lightened(_rng.randf_range(0.0, 0.05))
	else:
		col = col.darkened(_rng.randf_range(0.0, 0.06))
	for v in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)


# ---------------------------------------------------------------------- rocks

func _rock_mesh() -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var base: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var verts: Array[Vector3] = []
	for v in base:
		verts.append(v.normalized() * _rng.randf_range(0.78, 1.15))
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for f in faces:
		# icosphere list is counter-clockwise; Godot front faces are clockwise
		st.add_vertex(verts[f[0]])
		st.add_vertex(verts[f[2]])
		st.add_vertex(verts[f[1]])
	st.generate_normals()
	return st.commit()


func _scatter_rocks() -> void:
	var variants: Array[ArrayMesh] = []
	for i in 4:
		variants.append(_rock_mesh())
	for i in 34:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(4.5, 45.0)
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		var s := _rng.randf_range(0.3, 1.5) if dist < 14.0 else _rng.randf_range(0.8, 2.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ROCK_A.lerp(ROCK_B, _rng.randf())
		mat.roughness = 1.0
		var mi := MeshInstance3D.new()
		mi.mesh = variants[_rng.randi() % variants.size()]
		mi.material_override = mat
		mi.position = Vector3(x, height_at(x, z) + s * 0.12, z)
		mi.rotation.y = _rng.randf() * TAU
		mi.scale = Vector3(s * _rng.randf_range(1.0, 1.6), s * _rng.randf_range(0.6, 1.0), s * _rng.randf_range(1.0, 1.6))
		add_child(mi)


# --------------------------------------------------------------------- clouds

func _build_clouds() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission = Color(0.88, 0.93, 1.0)
	mat.emission_energy_multiplier = 0.6
	for i in 18:
		var cloud := Node3D.new()
		var puffs := _rng.randi_range(4, 7)
		for p in puffs:
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 8
			sm.rings = 4
			var mi := MeshInstance3D.new()
			mi.mesh = sm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var s := _rng.randf_range(2.0, 3.6)
			mi.scale = Vector3(s * 1.3, s * 0.8, s)
			mi.position = Vector3(p * 3.0 - puffs * 1.5 + _rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.7, 0.7), _rng.randf_range(-1.5, 1.5))
			cloud.add_child(mi)
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(55.0, 140.0)
		cloud.position = Vector3(cos(ang) * dist, _rng.randf_range(24.0, 46.0), sin(ang) * dist)
		cloud.scale = Vector3.ONE * _rng.randf_range(2.0, 4.0)
		cloud.set_meta("speed", _rng.randf_range(0.6, 1.4))
		add_child(cloud)
		_clouds.append(cloud)
