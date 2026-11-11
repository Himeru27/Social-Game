class_name LowPoly
extends RefCounted
## Helpers for building flat-shaded, low-poly meshes from primitives in code.
## Meshes and materials are cached and SHARED - never modify a returned mesh/material.

static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}


static func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic_specular = 0.0
	_mat_cache[key] = m
	return m


## Converts any primitive mesh into a faceted (flat-normal) mesh.
static func flat(src: Mesh) -> Mesh:
	if src.get_surface_count() == 0:
		return src
	var arr := src.surface_get_arrays(0)
	if arr.is_empty():
		return src
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i in verts.size():
			idx.append(i)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var i := 0
	while i + 2 < idx.size():
		var a := verts[idx[i]]
		var b := verts[idx[i + 1]]
		var c := verts[idx[i + 2]]
		if (b - a).cross(c - a).length_squared() > 0.000001:
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
		i += 3
	st.generate_normals()
	return st.commit()


static func _instance(parent: Node, mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func box(parent: Node, size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var key := "b%s" % size
	var m: Mesh = _mesh_cache.get(key)
	if m == null:
		var bm := BoxMesh.new()
		bm.size = size
		m = bm
		_mesh_cache[key] = m
	return _instance(parent, m, color, pos)


static func cylinder(parent: Node, top_r: float, bottom_r: float, height: float, segments: int, color: Color, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var key := "c%s_%s_%s_%d" % [top_r, bottom_r, height, segments]
	var m: Mesh = _mesh_cache.get(key)
	if m == null:
		var cm := CylinderMesh.new()
		cm.top_radius = top_r
		cm.bottom_radius = bottom_r
		cm.height = height
		cm.radial_segments = segments
		cm.rings = 1
		m = flat(cm)
		_mesh_cache[key] = m
	return _instance(parent, m, color, pos)


static func sphere(parent: Node, radius: float, color: Color, pos: Vector3 = Vector3.ZERO, segments: int = 7, rings: int = 4) -> MeshInstance3D:
	var key := "s%s_%d_%d" % [radius, segments, rings]
	var m: Mesh = _mesh_cache.get(key)
	if m == null:
		var sm := SphereMesh.new()
		sm.radius = radius
		sm.height = radius * 2.0
		sm.radial_segments = segments
		sm.rings = rings
		m = flat(sm)
		_mesh_cache[key] = m
	return _instance(parent, m, color, pos)


## Adds the shared soft sky, fog and a shadow-casting sun to `parent`.
static func add_sky_and_sun(parent: Node) -> void:
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
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#f2d9b5")
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color("#fff0d6")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	parent.add_child(sun)
