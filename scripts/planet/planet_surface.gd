extends Node3D
## Высадка на планету в духе No Man's Sky: рельеф, трава на ветру, флора по биому,
## ходьба от первого лица, реактивный ранец, мультитул, ресурсы и животные.
## Всё строится процедурно из сида планеты, поэтому одна и та же планета выглядит одинаково.

const SIZE := 320 ## сторона участка поверхности в метрах (1 клетка = 1 м)
const SPAWN := Vector2(4, 6)
const WALK := 7.0
const RUN := 13.0
const GRAVITY := 16.0
const JET_MAX := 1.6
const TAKEOFF_DIST := 14.0

var planet: Dictionary
var B: Dictionary
var rng := RandomNumberGenerator.new()
var heights := PackedFloat32Array()
var level := -1.0e9
var water: Dictionary

var player: CharacterBody3D
var cam: Camera3D
var tool: Node3D
var tool_tip: Node3D
var ship: Node3D
var yaw := 2.4
var pitch := -0.05
var jet := JET_MAX
var hp := 100.0
var recoil := 0.0
var bob := 0.0
var shot_cd := 0.0
var beam: MeshInstance3D
var beam_life := 0.0
var items: Array[Dictionary] = []
var beasts: Array[Dictionary] = []
var trip := {"ore": 0, "samples": 0}
var leaving := false

var _hp_bar: ProgressBar
var _jet_bar: ProgressBar
var _info: Label
var _prompt: Label
var _time: Label
var _n_terrain := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_grass := FastNoiseLite.new()
var _n_forest := FastNoiseLite.new()


func _ready() -> void:
	planet = GameState.current_planet
	if planet.is_empty():
		planet = {"name": "Испытательная", "biome": "jungle", "seed": 12345}
	B = Biomes.DATA[planet.biome]
	water = B.water
	rng.seed = planet.seed
	_setup_noise()
	_build_heights()
	_build_environment()
	_build_terrain()
	_build_water()
	_build_grass()
	_build_rocks()
	_build_flora()
	_build_items()
	_build_creatures()
	_build_ship()
	_build_player()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------- Рельеф ----------

func _setup_noise() -> void:
	var s: int = planet.seed
	_n_terrain.seed = s
	_n_terrain.frequency = 0.0068
	_n_terrain.fractal_octaves = 5
	_n_ridge.seed = s + 50
	_n_ridge.frequency = 0.017
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.fractal_octaves = 4
	_n_detail.seed = s + 9
	_n_detail.frequency = 0.09
	_n_detail.fractal_octaves = 3
	_n_grass.seed = s + 300
	_n_grass.frequency = 0.028
	_n_grass.fractal_octaves = 3
	_n_forest.seed = s + 77
	_n_forest.frequency = 0.02
	_n_forest.fractal_octaves = 3


func _raw_height(x: float, z: float) -> float:
	var amp: float = B.amp
	var h := _n_terrain.get_noise_2d(x, z) * amp
	var r := _n_ridge.get_noise_2d(x, z) * 0.5 + 0.5
	h += r * r * amp * 0.5
	h += _n_detail.get_noise_2d(x, z) * 0.8
	return h


func _build_heights() -> void:
	var h0 := _raw_height(SPAWN.x, SPAWN.y)
	var n := SIZE + 1
	heights.resize(n * n)
	for iz in n:
		for ix in n:
			var x := ix - SIZE / 2.0
			var z := iz - SIZE / 2.0
			var h := _raw_height(x, z)
			var d := Vector2(x, z).distance_to(SPAWN)
			if d < 22.0:
				var k := smoothstep(0.0, 22.0, d)
				h = h * k + h0 * (1.0 - k)
			heights[iz * n + ix] = h
	if not water.is_empty():
		level = min(float(water.level), h0 - 3.0)


## Высота поверхности в точке, точно по треугольникам сетки.
func ground(x: float, z: float) -> float:
	var n := SIZE + 1
	var gx: float = clamp(x + SIZE / 2.0, 0.0, SIZE - 0.001)
	var gz: float = clamp(z + SIZE / 2.0, 0.0, SIZE - 0.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var a := heights[iz * n + ix]
	var b := heights[iz * n + ix + 1]
	var c := heights[(iz + 1) * n + ix]
	var d := heights[(iz + 1) * n + ix + 1]
	if fx + fz < 1.0:
		return a + (b - a) * fx + (c - a) * fz
	return d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fz)


func _normal_at(x: float, z: float) -> Vector3:
	return Vector3(ground(x - 1, z) - ground(x + 1, z), 2.0, ground(x, z - 1) - ground(x, z + 1)).normalized()


func _build_terrain() -> void:
	var n := SIZE + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	uvs.resize(n * n)
	var amp: float = B.amp
	var sand := Color("#120c0a") if planet.biome == "volcano" else Color("#a89a78")
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			var x := ix - SIZE / 2.0
			var z := iz - SIZE / 2.0
			var y := heights[i]
			verts[i] = Vector3(x, y, z)
			var nr := _normal_at(x, z)
			normals[i] = nr
			uvs[i] = Vector2(x, z) * 0.25
			var k: float = clamp((y + amp * 0.6) / (amp * 1.7), 0.0, 1.0)
			var col: Color = B.low.lerp(B.high, k)
			var gm := smoothstep(-0.12, 0.12, _n_grass.get_noise_2d(x, z)) * smoothstep(0.82, 0.94, nr.y) * float(B.grass_cover)
			col = col.lerp(B.grass * 0.8, gm)
			col = col.lerp(B.rock, 1.0 - smoothstep(0.62, 0.82, nr.y))
			if not water.is_empty():
				col = col.lerp(sand, 1.0 - smoothstep(level + 0.4, level + 2.2, y))
			colors[i] = col * (1.0 + _n_detail.get_noise_2d(x * 2.0, z * 2.0) * 0.12)
	var idx := PackedInt32Array()
	for iz in SIZE:
		for ix in SIZE:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = _grain_texture()
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	hm.map_data = heights
	shape.shape = hm
	body.add_child(shape)
	add_child(body)


func _grain_texture() -> NoiseTexture2D:
	var nz := FastNoiseLite.new()
	nz.seed = int(planet.seed) + 3
	nz.frequency = 0.05
	nz.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = nz
	t.color_ramp = ShipBuilder.gradient([[0.0, Color(0.7, 0.7, 0.7)], [1.0, Color(1, 1, 1)]])
	return t


# ---------- Небо, свет, вода ----------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = B.sky_top
	sky_mat.sky_horizon_color = B.sky_hor
	sky_mat.ground_horizon_color = B.sky_hor
	sky_mat.ground_bottom_color = B.low
	sky_mat.sun_angle_max = 6.0
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = B.sky_hor
	env.fog_density = 0.008 if planet.biome == "volcano" else 0.005
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = B.sun
	sun.light_energy = 1.3 if planet.biome == "volcano" else 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-140), 0)
	add_child(sun)


func _build_water() -> void:
	if water.is_empty():
		return
	var col: Color = water.color
	var lava: bool = water.get("lava", false)
	var ice: bool = water.get("ice", false)
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE * 2, SIZE * 2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col, 1.0 if lava else (0.94 if ice else 0.82))
	mat.roughness = 0.7 if lava else (0.18 if ice else 0.05)
	mat.metallic = 0.0 if lava else 0.3
	if not lava:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 2.5
	pm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position.y = level
	add_child(mi)
	if ice:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = WorldBoundaryShape3D.new()
		body.add_child(shape)
		body.position.y = level
		add_child(body)


# ---------- Трава и флора ----------

func _spot(radius: float, min_ny: float, mask: Callable = Callable(), tries: int = 30) -> Variant:
	for t in tries:
		var x := rng.randf_range(-radius, radius)
		var z := rng.randf_range(-radius, radius)
		var y := ground(x, z)
		if y < level + 0.5:
			continue
		if _normal_at(x, z).y < min_ny:
			continue
		if mask.is_valid() and not mask.call(x, z):
			continue
		if Vector2(x, z).distance_to(SPAWN) < 16.0:
			continue
		return Vector3(x, y, z)
	return null


func _multimesh(mesh: Mesh, list: Array, mat: Material, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var o: Dictionary = list[i]
		mm.set_instance_transform(i, o.t)
		mm.set_instance_color(i, o.get("c", Color.WHITE))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _xf(pos: Vector3, rot: Vector3, scl: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)


func _tint(c: Color, v: float) -> Color:
	return c * (1.0 + rng.randf_range(-v, v))


func _vc_material(roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = roughness
	return m


func _build_grass() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-0.04, 0, 0), Vector3(0.04, 0, 0), Vector3(-0.026, 0.5, 0.02), Vector3(0.026, 0.5, 0.02), Vector3(0, 1, 0.06)]
	for tri in [[0, 2, 1], [1, 2, 3], [2, 4, 3]]:
		for k in tri:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0, pts[k].y))
			st.add_vertex(pts[k])
	var blade := st.commit()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
varying float h;
void vertex() {
	h = VERTEX.y;
	float ph = MODEL_MATRIX[3].x * 0.21 + MODEL_MATRIX[3].z * 0.17;
	VERTEX.x += sin(TIME * 1.7 + ph) * h * h * 0.22;
	VERTEX.z += cos(TIME * 1.3 + ph) * h * h * 0.12;
}
void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = c * mix(0.35, 1.1, h);
	ROUGHNESS = 0.85;
	BACKLIGHT = c * 0.4;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var list := []
	var count := int(30000 * float(B.grass_cover))
	var tries := 0
	while list.size() < count and tries < count * 3:
		tries += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 115.0
		var x := SPAWN.x + cos(a) * r
		var z := SPAWN.y + sin(a) * r
		if _n_grass.get_noise_2d(x, z) < -0.05:
			continue
		var y := ground(x, z)
		if y < level + 0.4 or _normal_at(x, z).y < 0.84:
			continue
		var s := rng.randf_range(0.7, 1.6) * float(B.grass_h)
		list.append({"t": _xf(Vector3(x, y - 0.05, z), Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2)), Vector3(rng.randf_range(1.0, 1.8), s, 1.0)),
			"c": B.grass * rng.randf_range(0.75, 1.25)})
	_multimesh(blade, list, mat, false)


func _build_rocks() -> void:
	var list := []
	for i in 240:
		var p = _spot(150.0, 0.55)
		if p == null:
			continue
		var s := 0.3 + pow(rng.randf(), 2.5) * 3.2
		list.append({"t": _xf(p - Vector3(0, s * 0.25, 0), Vector3(rng.randf() * 0.5, rng.randf() * TAU, 0), Vector3(s * rng.randf_range(1.0, 1.6), s, s * rng.randf_range(1.0, 1.6))), "c": _tint(B.rock, 0.4)})
	_multimesh(ShipBuilder.blob_mesh(int(planet.seed) % 997, 16, 10, 0.45), list, _vc_material(0.92), true)


func _build_flora() -> void:
	match B.flora:
		"trees":
			var trunks := []
			var crowns := []
			var bushes := []
			var forest := func(x, z): return _n_forest.get_noise_2d(x, z) > -0.05
			for i in 150:
				var p = _spot(150.0, 0.8, forest)
				if p == null:
					continue
				var h := rng.randf_range(5.0, 13.0)
				var cs := rng.randf_range(2.4, 4.8)
				trunks.append({"t": _xf(p - Vector3(0, 0.3, 0), Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, 0), Vector3(1, h, 1) * Vector3(rng.randf_range(1, 1.4), 1, rng.randf_range(1, 1.4))), "c": _tint(Color("#5a4030"), 0.3)})
				var hue: Color = [Color("#2f8a4a"), Color("#3aa070"), Color("#7a4ab0"), Color("#2a9a9a"), Color("#4a9a2a")][rng.randi() % 5]
				crowns.append({"t": _xf(p + Vector3(0, h, 0), Vector3(0, rng.randf() * TAU, 0), Vector3(cs * 1.2, cs * 0.8, cs * 1.2)), "c": _tint(hue, 0.3)})
			for i in 200:
				var p = _spot(150.0, 0.75)
				if p == null:
					continue
				var s := rng.randf_range(0.7, 1.9)
				bushes.append({"t": _xf(p + Vector3(0, s * 0.3, 0), Vector3(0, rng.randf() * TAU, 0), Vector3(s * 1.3, s * 0.8, s * 1.3)), "c": _tint(Color("#3a7a2a"), 0.3)})
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.22
			trunk.bottom_radius = 0.45
			trunk.height = 1.0
			_multimesh(_shifted(trunk), trunks, _vc_material(0.9), true)
			_multimesh(ShipBuilder.blob_mesh(int(planet.seed) % 311 + 5, 24, 14, 0.4), crowns, _vc_material(0.8), true)
			_multimesh(ShipBuilder.blob_mesh(int(planet.seed) % 211 + 9, 16, 10, 0.4), bushes, _vc_material(0.8), true)
		"shrooms":
			var stems := []
			var caps := []
			for i in 130:
				var p = _spot(150.0, 0.75)
				if p == null:
					continue
				var h := 1.5 + pow(rng.randf(), 2.0) * 9.0
				var cs := 1.0 + h * 0.45
				var w := 0.5 + h * 0.08
				stems.append({"t": _xf(p - Vector3(0, 0.2, 0), Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12)), Vector3(w, h, w)), "c": _tint(Color("#e8e0c8"), 0.2)})
				var cc: Color = [Color("#ff5ab0"), Color("#40e0ff"), Color("#ff9a30"), Color("#b070ff")][rng.randi() % 4]
				caps.append({"t": _xf(p + Vector3(0, h - 0.3, 0), Vector3(0, rng.randf() * TAU, 0), Vector3(cs, cs * 0.55, cs)), "c": _tint(cc, 0.3)})
			var stem := CylinderMesh.new()
			stem.top_radius = 0.3
			stem.bottom_radius = 0.5
			stem.height = 1.0
			_multimesh(_shifted(stem), stems, _vc_material(0.8), true)
			var cap := SphereMesh.new()
			cap.is_hemisphere = true
			cap.radius = 1.0
			cap.height = 1.0
			var cm := _vc_material(0.5)
			cm.emission_enabled = true
			cm.emission = Color(0.5, 0.2, 0.4)
			cm.emission_energy_multiplier = 0.6
			_multimesh(cap, caps, cm, true)
		"spikes":
			var list := []
			for i in 180:
				var p = _spot(150.0, 0.6)
				if p == null:
					continue
				for k in rng.randi_range(1, 3):
					var h := rng.randf_range(3.0, 14.0)
					var w := rng.randf_range(0.6, 2.2)
					list.append({"t": _xf(p + Vector3(rng.randf_range(-2, 2), -0.5, rng.randf_range(-2, 2)), Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * TAU, rng.randf_range(-0.25, 0.25)), Vector3(w, h, w)), "c": _tint(Color("#cfe8ff"), 0.2)})
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 1.0
			cone.height = 1.0
			cone.radial_segments = 7
			var m := _vc_material(0.12)
			m.metallic = 0.1
			_multimesh(_shifted(cone), list, m, true)
		"pillars":
			var list := []
			var cacti := []
			for i in 70:
				var p = _spot(150.0, 0.7)
				if p == null:
					continue
				var h := rng.randf_range(6.0, 22.0)
				var w := rng.randf_range(2.0, 5.0)
				list.append({"t": _xf(p - Vector3(0, 1, 0), Vector3(0, rng.randf() * TAU, 0), Vector3(w, h, w * rng.randf_range(0.8, 1.2))), "c": _tint(Color("#b8743c"), 0.3)})
			for i in 120:
				var p = _spot(150.0, 0.8)
				if p == null:
					continue
				var h := rng.randf_range(1.5, 5.0)
				cacti.append({"t": _xf(p - Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(0.5, h, 0.5)), "c": _tint(Color("#4f8a3a"), 0.3)})
			var pillar := ShipBuilder.blob_mesh(int(planet.seed) % 401 + 3, 16, 12, 0.5)
			_multimesh(_shifted(pillar), list, _vc_material(0.95), true)
			var cact := CapsuleMesh.new()
			cact.radius = 0.5
			cact.height = 2.0
			_multimesh(_shifted(cact), cacti, _vc_material(0.7), true)
		"basalt":
			var list := []
			for i in 44:
				var p = _spot(150.0, 0.7)
				if p == null:
					continue
				for k in rng.randi_range(5, 13):
					var h := rng.randf_range(1.5, 9.0)
					list.append({"t": _xf(p + Vector3(rng.randf_range(-4, 4), -1, rng.randf_range(-4, 4)), Vector3(0, rng.randf(), 0), Vector3(rng.randf_range(0.8, 1.4), h, rng.randf_range(0.8, 1.4))), "c": _tint(Color("#2a2426"), 0.4)})
			var col := CylinderMesh.new()
			col.top_radius = 1.0
			col.bottom_radius = 1.0
			col.height = 1.0
			col.radial_segments = 6
			_multimesh(_shifted(col), list, _vc_material(0.85), true)


## Переносит основание меши в y = 0, чтобы растение «росло» из земли.
func _shifted(m: Mesh) -> ArrayMesh:
	var arrays: Array = m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var aabb := m.get_aabb()
	for i in verts.size():
		verts[i] = Vector3(verts[i].x, (verts[i].y - aabb.position.y) / max(aabb.size.y, 0.001), verts[i].z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


# ---------- Ресурсы и животные ----------

func _build_items() -> void:
	var crystal := StandardMaterial3D.new()
	crystal.albedo_color = Color("#5fe0ff")
	crystal.emission_enabled = true
	crystal.emission = Color("#38c8ff")
	crystal.emission_energy_multiplier = 1.6
	crystal.roughness = 0.15
	var octa := SphereMesh.new()
	octa.radial_segments = 4
	octa.rings = 2
	octa.radius = 0.5
	octa.height = 1.0
	octa.material = crystal
	for i in 26:
		var p = _spot(140.0, 0.6)
		if p == null:
			continue
		var g := Node3D.new()
		for k in 4:
			var m := MeshInstance3D.new()
			m.mesh = octa
			m.scale = Vector3(rng.randf_range(0.6, 1.0), rng.randf_range(1.6, 3.4), rng.randf_range(0.6, 1.0))
			m.position = Vector3(rng.randf_range(-0.6, 0.6), 0.4, rng.randf_range(-0.6, 0.6))
			m.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * 3.0, rng.randf_range(-0.4, 0.4))
			g.add_child(m)
		g.position = p
		add_child(g)
		items.append({"node": g, "type": "ore"})

	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color("#a0ff80")
	bulb.emission_enabled = true
	bulb.emission = Color("#60ff50")
	bulb.emission_energy_multiplier = 2.0
	var stem := ShipBuilder.metal(Color("#3a6a2a"), 0.0, 0.8)
	for i in 16:
		var p = _spot(140.0, 0.7)
		if p == null:
			continue
		var g := Node3D.new()
		var st := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.08
		cm.height = 1.2
		cm.material = stem
		st.mesh = cm
		st.position.y = 0.6
		g.add_child(st)
		var bb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.64
		sm.material = bulb
		bb.mesh = sm
		bb.position.y = 1.3
		g.add_child(bb)
		g.position = p
		add_child(g)
		items.append({"node": g, "type": "samples"})


func _make_creature(col: Color) -> Dictionary:
	var g := Node3D.new()
	var mat := ShipBuilder.metal(col, 0.05, 0.55)
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.material = mat
	body.mesh = bm
	body.scale = Vector3(1.6, 1.24, 2.5) * 0.5
	body.position.y = 1.55
	g.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.5
	hm.height = 1.0
	hm.material = mat
	head.mesh = hm
	head.position = Vector3(0, 1.95, -1.2)
	head.scale = Vector3(1, 0.9, 1.2)
	g.add_child(head)
	var eye_mat := ShipBuilder.unshaded(Color(3.5, 2.2, 0.5))
	for s in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.08
		em.height = 0.16
		em.material = eye_mat
		e.mesh = em
		e.position = Vector3(s * 0.22, 2.05, -1.68)
		g.add_child(e)
	var legs: Array[Node3D] = []
	for lp in [Vector2(-0.5, -0.6), Vector2(0.5, -0.6), Vector2(-0.5, 0.6), Vector2(0.5, 0.6)]:
		var pivot := Node3D.new()
		pivot.position = Vector3(lp.x, 1.3, lp.y)
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.13
		lm.bottom_radius = 0.08
		lm.height = 1.3
		lm.material = mat
		leg.mesh = lm
		leg.position.y = -0.65
		pivot.add_child(leg)
		g.add_child(pivot)
		legs.append(pivot)
	g.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
	return {"node": g, "legs": legs}


func _build_creatures() -> void:
	var count := int(round(4.0 * float(B.danger))) + 1
	for i in count:
		var p = _spot(140.0, 0.6)
		if p == null:
			continue
		var c := _make_creature(B.creature)
		c.node.position = p
		add_child(c.node)
		c["home"] = p
		c["hp"] = 3
		c["phase"] = rng.randf() * TAU
		beasts.append(c)


func _build_ship() -> void:
	var made := ShipBuilder.make_ship(Color("#dfe4ec"), Color("#2f5fb0"), Color("#7fd8ff"))
	ship = made.node
	for g in made.glows:
		g.visible = false  # двигатели выключены после посадки
	var leg_mat := ShipBuilder.metal(Color("#5a606c"), 0.8, 0.4)
	for lp in [Vector2(-1.6, 1.6), Vector2(1.6, 1.6), Vector2(0, -2.2)]:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.08
		lm.bottom_radius = 0.1
		lm.height = 2.2
		lm.material = leg_mat
		leg.mesh = lm
		leg.position = Vector3(lp.x, -1.3, lp.y)
		ship.add_child(leg)
		var foot := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.35
		fm.bottom_radius = 0.4
		fm.height = 0.1
		fm.material = leg_mat
		foot.mesh = fm
		foot.position = Vector3(lp.x, -2.4, lp.y)
		ship.add_child(foot)
	ship.scale = Vector3.ONE * 1.05
	ship.position = Vector3(SPAWN.x + 8, ground(SPAWN.x + 8, SPAWN.y + 8) + 2.4, SPAWN.y + 8)
	ship.rotation.y = 2.3
	add_child(ship)


# ---------- Игрок ----------

func _build_player() -> void:
	player = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	player.add_child(shape)
	cam = Camera3D.new()
	cam.position.y = 0.7
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 1500.0
	player.add_child(cam)
	player.position = Vector3(SPAWN.x, ground(SPAWN.x, SPAWN.y) + 1.2, SPAWN.y)
	yaw = atan2(-8.0, -8.0) + 0.55
	add_child(player)

	tool = Node3D.new()
	var body_mat := ShipBuilder.metal(Color("#d8dce4"), 0.85, 0.28)
	var acc := ShipBuilder.metal(Color("#e07a20"), 0.4, 0.4)
	_box(tool, Vector3(0.09, 0.1, 0.36), Vector3.ZERO, body_mat)
	_box(tool, Vector3(0.06, 0.16, 0.07), Vector3(0, -0.1, 0.08), acc).rotation.x = 0.3
	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.022
	bm.bottom_radius = 0.03
	bm.height = 0.22
	bm.material = acc
	barrel.mesh = bm
	barrel.rotation.x = PI / 2.0
	barrel.position = Vector3(0, 0.01, -0.27)
	tool.add_child(barrel)
	_box(tool, Vector3(0.092, 0.012, 0.2), Vector3(0, 0.052, -0.02), ShipBuilder.unshaded(Color(0.4, 2.0, 3.4)))
	tool_tip = Node3D.new()
	tool_tip.position = Vector3(0, 0.01, -0.4)
	tool.add_child(tool_tip)
	tool.scale = Vector3.ONE * 0.42
	tool.position = Vector3(0.19, -0.15, -0.36)
	cam.add_child(tool)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0025
		pitch = clamp(pitch - event.relative.y * 0.0025, -1.3, 1.3)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_E:
			_try_takeoff()


func _physics_process(delta: float) -> void:
	if leaving:
		return
	player.rotation.y = yaw
	cam.rotation.x = pitch
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input.y -= 1
	if Input.is_key_pressed(KEY_S): input.y += 1
	if Input.is_key_pressed(KEY_A): input.x -= 1
	if Input.is_key_pressed(KEY_D): input.x += 1
	var run := Input.is_key_pressed(KEY_SHIFT)
	var in_liquid: bool = not water.is_empty() and player.position.y < level + 0.2 and not water.get("ice", false)
	var speed := (RUN if run else WALK) * (0.55 if in_liquid and not water.get("lava", false) else 1.0)
	var dir := (player.transform.basis * Vector3(input.x, 0, input.y)).normalized()
	player.velocity.x = dir.x * speed
	player.velocity.z = dir.z * speed
	if Input.is_key_pressed(KEY_SPACE) and jet > 0.0:
		player.velocity.y = min(player.velocity.y + 30.0 * delta, 9.0)
		jet = max(0.0, jet - delta)
	elif player.is_on_floor():
		jet = min(JET_MAX, jet + delta * 0.8)
	player.velocity.y -= GRAVITY * delta
	if in_liquid and not water.get("lava", false):
		player.velocity.y = max(player.velocity.y, 0.0) if player.position.y < level - 0.6 else player.velocity.y
	player.move_and_slide()
	player.position.x = clamp(player.position.x, -SIZE / 2.0 + 4, SIZE / 2.0 - 4)
	player.position.z = clamp(player.position.z, -SIZE / 2.0 + 4, SIZE / 2.0 - 4)
	if in_liquid and water.get("lava", false):
		hp -= 30.0 * delta
	var walking := input != Vector2.ZERO and player.is_on_floor()
	if walking:
		bob += delta * (11.0 if run else 7.0)
	cam.position.y = 0.7 + sin(bob) * 0.05


func _process(delta: float) -> void:
	if leaving:
		return
	var me := cam.global_position
	for it in items.duplicate():
		var n: Node3D = it.node
		n.rotation.y += delta * 0.8
		if n.global_position.distance_to(player.global_position) < 2.8:
			trip[it.type] += 1
			n.queue_free()
			items.erase(it)
	for b in beasts:
		var n: Node3D = b.node
		var d := n.position.distance_to(player.position)
		var chase := d < 26.0 * float(B.danger)
		var tgt: Vector3 = player.position if chase else b.home
		var to := Vector3(tgt.x - n.position.x, 0, tgt.z - n.position.z)
		var moving := to.length() > 1.6
		if moving:
			n.position += to.normalized() * (6.5 if chase else 2.0) * delta
			n.rotation.y = atan2(-to.x, -to.z)
			b.phase += delta * (12.0 if chase else 6.0)
		n.position.y = ground(n.position.x, n.position.z)
		for i in b.legs.size():
			b.legs[i].rotation.x = sin(b.phase + (0.0 if i == 0 or i == 3 else PI)) * 0.55
		if d < 2.6:
			hp -= 12.0 * delta
	shot_cd -= delta
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and shot_cd <= 0.0:
		shot_cd = 0.3
		_shoot()
	if Input.is_key_pressed(KEY_F) and shot_cd <= 0.0:
		shot_cd = 0.3
		_shoot()
	if beam:
		beam_life -= delta
		if beam_life <= 0.0:
			beam.queue_free()
			beam = null
	recoil = max(0.0, recoil - delta * 0.6)
	tool.position = Vector3(0.19 + cos(bob * 0.5) * 0.006, -0.15 + abs(sin(bob * 0.5)) * 0.008, -0.36 + recoil)
	hp = min(100.0, hp + 0.4 * delta)
	if hp <= 0.0:
		print("Капитан тяжело ранен, экипаж эвакуировал его на корабль. Собранное потеряно.")
		trip = {"ore": 0, "samples": 0}
		_leave()
		return
	var to_ship := ship.global_position.distance_to(player.global_position)
	_hp_bar.value = hp
	_jet_bar.value = jet / JET_MAX * 100.0
	_info.text = "Руда: %d   Образцы: %d   До корабля: %d м" % [trip.ore, trip.samples, int(to_ship)]
	_prompt.text = "Нажмите E, чтобы взлететь" if to_ship < TAKEOFF_DIST else ""
	_time.text = GameState.time_text()


func _shoot() -> void:
	var dir := -cam.global_transform.basis.z
	var best = null
	var best_d := 50.0
	for b in beasts:
		var c: Vector3 = b.node.global_position + Vector3(0, 1.5, 0)
		var to := c - cam.global_position
		var d := to.length()
		if d < best_d and to.normalized().dot(dir) > 0.982:
			best_d = d
			best = b
	var from := tool_tip.global_position
	var end := cam.global_position + dir * best_d
	if beam:
		beam.queue_free()
	beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var blen := from.distance_to(end)
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = blen
	cm.material = ShipBuilder.unshaded(Color(0.6, 2.8, 4.5))
	beam.mesh = cm
	add_child(beam)
	beam.global_position = (from + end) / 2.0
	beam.look_at(end, Vector3.UP)
	beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	beam_life = 0.1
	recoil = 0.035
	if best != null:
		best.hp -= 1
		if best.hp <= 0:
			best.node.queue_free()
			beasts.erase(best)
			if rng.randf() < 0.6:
				trip.samples += 1


func _try_takeoff() -> void:
	if ship.global_position.distance_to(player.global_position) < TAKEOFF_DIST:
		_leave()


func _leave() -> void:
	leaving = true
	GameState.cargo.ore += trip.ore
	GameState.cargo.samples += trip.samples
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/system/star_system.tscn")


# ---------- Интерфейс ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme := Theme.new()
	theme.default_font_size = 20
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.086, 0.188, 0.353, 0.85)
	style.border_color = Color("#4a78bc")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)

	var top := PanelContainer.new()
	top.theme = theme
	top.add_theme_stylebox_override("panel", style)
	top.position = Vector2(16, 16)
	layer.add_child(top)
	var col := VBoxContainer.new()
	top.add_child(col)
	var title := Label.new()
	title.text = "%s · %s" % [planet.name, B.name]
	title.add_theme_color_override("font_color", Color("#ffbf55"))
	col.add_child(title)
	_time = Label.new()
	col.add_child(_time)
	_hp_bar = _bar(col, "Здоровье", Color("#76e8a0"))
	_jet_bar = _bar(col, "Ранец", Color("#ffbf55"))
	_info = Label.new()
	col.add_child(_info)

	var help := Label.new()
	help.theme = theme
	help.text = "WASD: идти, Shift: бег, пробел: ранец\nМышь: обзор, ЛКМ или F: выстрел\nE у корабля: взлететь, Esc: освободить курсор"
	help.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	help.anchor_left = 1.0
	help.anchor_right = 1.0
	help.offset_left = -560
	help.offset_right = -16
	help.offset_top = 16
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(help)

	var cross := Label.new()
	cross.theme = theme
	cross.text = "+"
	cross.add_theme_color_override("font_color", Color("#6fdcff"))
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -6
	cross.offset_top = -14
	layer.add_child(cross)

	_prompt = Label.new()
	_prompt.theme = theme
	_prompt.add_theme_color_override("font_color", Color("#ffbf55"))
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = -80
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_prompt)


func _bar(parent: Control, text: String, c: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 18)
	bar.show_percentage = false
	bar.value = 100
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	parent.add_child(row)
	return bar
