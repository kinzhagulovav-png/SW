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
const CHUNK := 32 ## размер куска поверхности в клетках
const VEIN_LEVEL := 0.42
const REACH := 6.5 ## дальность лапатрона
const INTERIOR := Vector3(0, -420, 0) ## где стоит внутренность корабля (глубоко под землёй)

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
var jet_max := JET_MAX
var tool_index := 0
var _tools: Array[Node3D] = []
var _dirt_fx: CPUParticles3D
var _feed: VBoxContainer
var _feed_time := 0.0
var _tool_label: Label
var hp := 100.0
var recoil := 0.0
var bob := 0.0
var shot_cd := 0.0
var beam: MeshInstance3D
var beam_life := 0.0
var items: Array[Dictionary] = []
var beasts: Array[Dictionary] = []
var trip := {"minerals": {}, "samples": []}
var leaving := false
var profile: Dictionary   # Biomes.profile: радиация, кислород, минералы планеты
var inside := false       # игрок внутри корабля
var cover := false
var t_open := 0.0         # сколько секунд подряд на открытой местности
var t_bay := 0.0          # сколько секунд в отсеке ремонта
var _warned := {}
var _bay_ring: MeshInstance3D
var _bay_light: OmniLight3D
var _radar: Control
var _o2_bar: ProgressBar
var _rad_bar: ProgressBar
var _armor_bar: ProgressBar
var _env_label: Label
var _env: Environment
var _menu: ShipMenu
var _scientist: Node3D
var _lab_glow: Array[MeshInstance3D] = []
var _lab_time := 0.0

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
var _n_vein := FastNoiseLite.new()
var orig_heights := PackedFloat32Array()
var _chunks: Array[MeshInstance3D] = []
var _hmap: HeightMapShape3D
var _terrain_mat: StandardMaterial3D
var _sand: Color
var _dirt: Color
var _grass: MultiMesh
var _grass_cells := {}


func _ready() -> void:
	planet = GameState.current_planet
	if planet.is_empty():
		planet = {"name": "Испытательная", "biome": "jungle", "seed": 12345}
	B = Biomes.DATA[planet.biome]
	water = B.water
	rng.seed = planet.seed
	profile = Biomes.profile(planet)
	hp = GameState.health
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
	_build_interior()
	_build_player()
	_build_ui()
	jet_max = JET_MAX * (1.7 if GameState.has_device("jetpack2") else 1.0)
	jet = jet_max
	GameState.stats.landings += 1
	rng.randomize()  # планета уже построена, дальше добыча случайна
	_notify("Фон радиации: %s" % Biomes.rad_text(profile.rad), Color("#ffbf55"))
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
	_n_vein.seed = s + 555
	_n_vein.frequency = 0.035
	_n_vein.fractal_octaves = 2
	_sand = Color("#120c0a") if planet.biome == "volcano" else Color("#a89a78")
	_dirt = Color(B.low).lerp(Color("#7a5a40"), 0.55)


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
	orig_heights = heights.duplicate()
	_terrain_mat = StandardMaterial3D.new()
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.vertex_color_is_srgb = true
	_terrain_mat.albedo_texture = _grain_texture()
	_terrain_mat.roughness = 0.95
	_terrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Поверхность нарезана на куски, чтобы после копания перестраивать только нужные.
	var per_side := SIZE / CHUNK
	for cz in per_side:
		for cx in per_side:
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(cx, cz)
			add_child(mi)
			_chunks.append(mi)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	_hmap = HeightMapShape3D.new()
	_hmap.map_width = SIZE + 1
	_hmap.map_depth = SIZE + 1
	_hmap.map_data = heights
	shape.shape = _hmap
	body.add_child(shape)
	add_child(body)


func _vertex_color(ix: int, iz: int, nr: Vector3) -> Color:
	var n := SIZE + 1
	var x := ix - SIZE / 2.0
	var z := iz - SIZE / 2.0
	var y := heights[iz * n + ix]
	var amp: float = B.amp
	var k: float = clamp((y + amp * 0.6) / (amp * 1.7), 0.0, 1.0)
	var col: Color = B.low.lerp(B.high, k)
	var gm := smoothstep(-0.12, 0.12, _n_grass.get_noise_2d(x, z)) * smoothstep(0.82, 0.94, nr.y) * float(B.grass_cover)
	col = col.lerp(B.grass * 0.8, gm)
	col = col.lerp(B.rock, 1.0 - smoothstep(0.62, 0.82, nr.y))
	if not water.is_empty():
		col = col.lerp(_sand, 1.0 - smoothstep(level + 0.4, level + 2.2, y))
	# Раскопанная земля: темнее и с цветом недр.
	var dug := orig_heights[iz * n + ix] - y
	if dug > 0.02:
		col = col.lerp(_dirt, clamp(dug / 0.8, 0.0, 1.0))
		if _vein(x, z) > VEIN_LEVEL and dug > 0.5:
			col = col.lerp(Color("#d8a040"), 0.35)
	return col * (1.0 + _n_detail.get_noise_2d(x * 2.0, z * 2.0) * 0.12)


func _chunk_mesh(cx: int, cz: int) -> ArrayMesh:
	var n := SIZE + 1
	var m := CHUNK + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(m * m)
	normals.resize(m * m)
	colors.resize(m * m)
	uvs.resize(m * m)
	for lz in m:
		for lx in m:
			var ix := cx * CHUNK + lx
			var iz := cz * CHUNK + lz
			var i := lz * m + lx
			var x := ix - SIZE / 2.0
			var z := iz - SIZE / 2.0
			verts[i] = Vector3(x, heights[iz * n + ix], z)
			var nr := _normal_at(x, z)
			normals[i] = nr
			uvs[i] = Vector2(x, z) * 0.25
			colors[i] = _vertex_color(ix, iz, nr)
	var idx := PackedInt32Array()
	for lz in CHUNK:
		for lx in CHUNK:
			var a := lz * m + lx
			var b := a + 1
			var c := a + m
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
	mesh.surface_set_material(0, _terrain_mat)
	return mesh


## Залежи в недрах: где шум выше VEIN_LEVEL, там богатая жила.
func _vein(x: float, z: float) -> float:
	return _n_vein.get_noise_2d(x, z)


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
	_env = env
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
		var cell := Vector2i(floori(x / 4.0), floori(z / 4.0))
		if not _grass_cells.has(cell):
			_grass_cells[cell] = []
		_grass_cells[cell].append(list.size() - 1)
	_grass = _multimesh(blade, list, mat, false).multimesh


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
	var octa := SphereMesh.new()
	octa.radial_segments = 4
	octa.rings = 2
	octa.radius = 0.5
	octa.height = 1.0
	var mats := {}
	var allowed: Array = profile.minerals
	# Не на каждой планете есть минералы, и выходы на поверхность редки.
	for i in (rng.randi_range(6, 12) if not allowed.is_empty() else 0):
		var p = _spot(140.0, 0.6)
		if p == null:
			continue
		var mid := Items.roll_mineral(rng, planet.biome, 8.0, allowed)
		if mid == "":
			continue
		if not mats.has(mid):
			var c: Color = Items.MINERALS[mid].color
			var cm := StandardMaterial3D.new()
			cm.albedo_color = c
			cm.metallic = 0.3
			cm.roughness = 0.2
			cm.emission_enabled = true
			cm.emission = c
			cm.emission_energy_multiplier = 0.9
			mats[mid] = cm
		var g := Node3D.new()
		for k in 4:
			var m := MeshInstance3D.new()
			m.mesh = octa
			m.material_override = mats[mid]
			m.scale = Vector3(rng.randf_range(0.6, 1.0), rng.randf_range(1.6, 3.4), rng.randf_range(0.6, 1.0))
			m.position = Vector3(rng.randf_range(-0.6, 0.6), 0.4, rng.randf_range(-0.6, 0.6))
			m.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * 3.0, rng.randf_range(-0.4, 0.4))
			g.add_child(m)
		g.position = p
		add_child(g)
		items.append({"node": g, "type": "mineral", "mineral": mid, "amount": rng.randi_range(3, 6)})

	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color("#a0ff80")
	bulb.emission_enabled = true
	bulb.emission = Color("#60ff50")
	bulb.emission_energy_multiplier = 2.0
	var stem := ShipBuilder.metal(Color("#3a6a2a"), 0.0, 0.8)
	for i in 10:
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
		items.append({"node": g, "type": "sample"})


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
	_build_blaster()
	_build_lapatron()
	_select_tool(0)
	_dirt_fx = CPUParticles3D.new()
	_dirt_fx.emitting = false
	_dirt_fx.one_shot = true
	_dirt_fx.amount = 18
	_dirt_fx.lifetime = 0.7
	_dirt_fx.explosiveness = 0.95
	_dirt_fx.direction = Vector3.UP
	_dirt_fx.spread = 50.0
	_dirt_fx.initial_velocity_min = 2.0
	_dirt_fx.initial_velocity_max = 4.5
	_dirt_fx.gravity = Vector3(0, -14, 0)
	_dirt_fx.scale_amount_min = 0.6
	_dirt_fx.scale_amount_max = 1.4
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.09
	var dm := StandardMaterial3D.new()
	dm.albedo_color = _dirt.lightened(0.15)
	bm.material = dm
	_dirt_fx.mesh = bm
	add_child(_dirt_fx)


## Бластер: оружие против животных.
func _build_blaster() -> void:
	var t := Node3D.new()
	var body_mat := ShipBuilder.metal(Color("#d8dce4"), 0.85, 0.28)
	var acc := ShipBuilder.metal(Color("#e07a20"), 0.4, 0.4)
	_box(t, Vector3(0.09, 0.1, 0.36), Vector3.ZERO, body_mat)
	_box(t, Vector3(0.06, 0.16, 0.07), Vector3(0, -0.1, 0.08), acc).rotation.x = 0.3
	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.022
	bm.bottom_radius = 0.03
	bm.height = 0.22
	bm.material = acc
	barrel.mesh = bm
	barrel.rotation.x = PI / 2.0
	barrel.position = Vector3(0, 0.01, -0.27)
	t.add_child(barrel)
	_box(t, Vector3(0.092, 0.012, 0.2), Vector3(0, 0.052, -0.02), ShipBuilder.unshaded(Color(0.4, 2.0, 3.4)))
	tool_tip = Node3D.new()
	tool_tip.position = Vector3(0, 0.01, -0.4)
	t.add_child(tool_tip)
	t.scale = Vector3.ONE * 0.42
	cam.add_child(t)
	_tools.append(t)


## Лапатрон: устройство в виде лопаты, копает землю и добывает минералы и образцы.
func _build_lapatron() -> void:
	var t := Node3D.new()
	var metal := ShipBuilder.metal(Color("#9aa4b4"), 0.9, 0.3)
	var grip := ShipBuilder.metal(Color("#2a2e36"), 0.2, 0.7)
	var glow := ShipBuilder.unshaded(Color(3.2, 1.6, 0.4))
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.025
	sm.bottom_radius = 0.025
	sm.height = 0.7
	sm.material = grip
	shaft.mesh = sm
	shaft.rotation.x = PI / 2.0
	shaft.position = Vector3(0, 0, 0.05)
	t.add_child(shaft)
	_box(t, Vector3(0.16, 0.035, 0.035), Vector3(0, 0, 0.4), grip)  # поперечная рукоять
	_box(t, Vector3(0.07, 0.07, 0.12), Vector3(0, 0, -0.26), metal)  # блок генератора
	_box(t, Vector3(0.075, 0.02, 0.06), Vector3(0, 0.04, -0.26), glow)
	var blade := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.26, 0.3, 0.025)
	pm.material = metal
	blade.mesh = pm
	blade.rotation = Vector3(-PI / 2.0, 0, PI)
	blade.position = Vector3(0, 0, -0.47)
	t.add_child(blade)
	_box(t, Vector3(0.22, 0.03, 0.012), Vector3(0, 0, -0.6), glow).rotation.x = PI / 2.0
	t.scale = Vector3.ONE * 0.55
	t.rotation = Vector3(0.25, 0.15, 0)
	cam.add_child(t)
	_tools.append(t)


func _select_tool(i: int) -> void:
	tool_index = i
	for k in _tools.size():
		_tools[k].visible = k == i and not inside
	tool = _tools[i]


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
	if leaving:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0025
		pitch = clamp(pitch - event.relative.y * 0.0025, -1.3, 1.3)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_tool(1 - tool_index)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_E:
				_interact()
			KEY_1:
				_select_tool(0)
			KEY_2:
				_select_tool(1)
			KEY_H:
				_use_medkit()


func _physics_process(delta: float) -> void:
	if leaving:
		return
	player.rotation.y = yaw
	cam.rotation.x = pitch
	var input := Vector2.ZERO
	if not _menu.visible:
		if Input.is_key_pressed(KEY_W): input.y -= 1
		if Input.is_key_pressed(KEY_S): input.y += 1
		if Input.is_key_pressed(KEY_A): input.x -= 1
		if Input.is_key_pressed(KEY_D): input.x += 1
	var run := Input.is_key_pressed(KEY_SHIFT)
	var in_liquid: bool = not inside and not water.is_empty() and player.position.y < level + 0.2 and not water.get("ice", false)
	var speed := (RUN if run else WALK) * (0.55 if in_liquid and not water.get("lava", false) else 1.0)
	var dir := (player.transform.basis * Vector3(input.x, 0, input.y)).normalized()
	player.velocity.x = dir.x * speed
	player.velocity.z = dir.z * speed
	if Input.is_key_pressed(KEY_SPACE) and jet > 0.0 and not _menu.visible:
		player.velocity.y = min(player.velocity.y + 30.0 * delta, 9.0)
		jet = max(0.0, jet - delta)
	elif player.is_on_floor():
		jet = min(jet_max, jet + delta * 0.8)
	player.velocity.y -= GRAVITY * delta
	if in_liquid and not water.get("lava", false):
		player.velocity.y = max(player.velocity.y, 0.0) if player.position.y < level - 0.6 else player.velocity.y
	player.move_and_slide()
	if not inside:
		player.position.x = clamp(player.position.x, -SIZE / 2.0 + 4, SIZE / 2.0 - 4)
		player.position.z = clamp(player.position.z, -SIZE / 2.0 + 4, SIZE / 2.0 - 4)
	if in_liquid and water.get("lava", false):
		_hurt(30.0 * delta)
	var walking := input != Vector2.ZERO and player.is_on_floor()
	if walking:
		bob += delta * (11.0 if run else 7.0)
	cam.position.y = 0.7 + sin(bob) * 0.05


func _use_medkit() -> void:
	if GameState.count("medkit") <= 0:
		_notify("Аптечек нет. Их делают на научной станции.", Color("#ff8a6a"))
		return
	if hp >= 100.0:
		return
	GameState.add_item("medkit", -1)
	hp = min(100.0, hp + 60.0)
	_notify("Аптечка: +60 здоровья", Color("#76e8a0"))


func _process(delta: float) -> void:
	if leaving:
		return
	for it in items:
		it.node.rotation.y += delta * 0.8
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
			_hurt(12.0 * delta)
	shot_cd -= delta
	var use := not inside and (Input.is_key_pressed(KEY_F) or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED))
	if use and shot_cd <= 0.0:
		if tool_index == 0:
			shot_cd = 0.2 if GameState.has_device("blaster2") else 0.3
			_shoot()
		else:
			shot_cd = 0.15 if GameState.has_device("lapatron2") else 0.3
			_use_lapatron()
	if beam:
		beam_life -= delta
		if beam_life <= 0.0:
			beam.queue_free()
			beam = null
	recoil = max(0.0, recoil - delta * 0.6)
	var base := Vector3(0.19, -0.15, -0.36) if tool_index == 0 else Vector3(0.24, -0.26, -0.5)
	tool.position = base + Vector3(cos(bob * 0.5) * 0.006, abs(sin(bob * 0.5)) * 0.008, recoil)
	if inside:
		_suit_inside(delta)
	else:
		_suit_outside(delta)
	if hp <= 0.0:
		_die()
		return
	var to_ship := ship.global_position.distance_to(player.global_position)
	_hp_bar.value = hp
	_jet_bar.value = jet / jet_max * 100.0
	_o2_bar.value = GameState.suit.oxygen
	_rad_bar.value = GameState.suit.rad
	_armor_bar.value = GameState.suit.armor
	if inside:
		_env_label.text = "На корабле" if _ship_zone() != "bay" else "Отсек ремонта: восстановление ×%.1f" % (1.0 + t_bay / 6.0)
		_env_label.add_theme_color_override("font_color", Color("#76e8a0"))
	else:
		_env_label.text = "Фон %s · %s" % [Biomes.rad_text(profile.rad), "укрытие" if cover else "открытая местность %d с" % int(t_open)]
		_env_label.add_theme_color_override("font_color", Color("#9ad8ff") if cover else Color("#ffbf55"))
	var found := 0
	for k in trip.minerals:
		found += int(trip.minerals[k])
	_info.text = "Минералы: %d   Образцы: %d" % [found, trip.samples.size()]
	if not inside:
		_info.text += "   До корабля: %d м" % int(to_ship)
	_tool_label.text = "[1] Бластер%s     [2] Лапатрон%s" % [
		" Мк-2" if GameState.has_device("blaster2") else "", " Мк-2" if GameState.has_device("lapatron2") else ""]
	_tool_label.add_theme_color_override("font_color", Color("#6fdcff") if tool_index == 0 else Color("#ffbf55"))
	var hint := ""
	if tool_index == 1:
		var hit = _aim_ground()
		if hit != null and (hit as Vector3).y < orig_heights_at(hit) - max_depth() + 0.05:
			hint = "Глубже лапатрон не берёт"
	if inside:
		hint = {"hatch": "E: выйти наружу", "cockpit": "E: взлететь", "lab": "E: научная работа (переработка, сборка, изучение образцов)", "bay": "Стойте в отсеке: радзащита и броня восстанавливаются"}.get(_ship_zone(), "")
	elif to_ship < TAKEOFF_DIST:
		hint = "E: подняться на корабль"
	_prompt.text = hint
	_time.text = GameState.time_text()
	_feed_time -= delta
	if _feed_time <= 0.0 and _feed.get_child_count() > 0:
		_feed.get_child(0).queue_free()
		_feed_time = 1.2


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
	_beam(from, end, Color(0.6, 2.8, 4.5))
	recoil = 0.035
	if best != null:
		best.hp -= 2 if GameState.has_device("blaster2") else 1
		if best.hp <= 0:
			best.node.queue_free()
			beasts.erase(best)
			GameState.stats.beasts += 1
			if rng.randf() < 0.5:
				_add_sample(0.0)


func _beam(from: Vector3, end: Vector3, col: Color) -> void:
	if beam:
		beam.queue_free()
	beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = max(0.05, from.distance_to(end))
	cm.material = ShipBuilder.unshaded(col)
	beam.mesh = cm
	add_child(beam)
	beam.global_position = (from + end) / 2.0
	if from.distance_to(end) > 0.01:
		beam.look_at(end, Vector3.UP if abs((end - from).normalized().y) < 0.99 else Vector3.RIGHT)
		beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	beam_life = 0.1


# ---------- Лапатрон: копание и добыча ----------

func max_depth() -> float:
	return 24.0 if GameState.has_device("lapatron2") else 12.0


func orig_heights_at(p: Vector3) -> float:
	var n := SIZE + 1
	var ix := clampi(roundi(p.x + SIZE / 2.0), 0, SIZE)
	var iz := clampi(roundi(p.z + SIZE / 2.0), 0, SIZE)
	return orig_heights[iz * n + ix]


## Точка на земле под прицелом (в пределах досягаемости) или null.
func _aim_ground() -> Variant:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var t := 0.3
	while t < REACH:
		var p := from + dir * t
		if p.y <= ground(p.x, p.z):
			return p
		t += 0.1
	return null


func _use_lapatron() -> void:
	recoil = 0.06
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	# Сначала кристаллы и образцы на поверхности.
	for it in items:
		var c: Vector3 = it.node.global_position + Vector3(0, 0.7, 0)
		var along := (c - from).dot(dir)
		if along < 0.0 or along > REACH + 1.0:
			continue
		if (from + dir * along).distance_to(c) < 1.1:
			_beam(tool.global_position + dir * 0.3, c, Color(3.2, 1.6, 0.4))
			_collect(it)
			return
	var hit = _aim_ground()
	if hit == null:
		return
	var p: Vector3 = hit
	if not water.is_empty() and p.y < level + 0.1 and not water.get("ice", false):
		_notify("Под жидкостью копать нельзя", Color("#ff8a6a"))
		return
	_beam(tool.global_position + dir * 0.3, p, Color(3.2, 1.6, 0.4))
	if _dig(p, 0.3 if GameState.has_device("lapatron2") else 0.22):
		_dirt_fx.global_position = p + Vector3(0, 0.1, 0)
		_dirt_fx.restart()
		_dirt_fx.emitting = true
		_dig_loot(p)


func _collect(it: Dictionary) -> void:
	items.erase(it)
	it.node.queue_free()
	if it.type == "mineral":
		_add_mineral(it.mineral, int(it.amount))
	else:
		_add_sample(0.0)


func _add_mineral(id: String, amount: int) -> void:
	trip.minerals[id] = int(trip.minerals.get(id, 0)) + amount
	var m: Dictionary = Items.MINERALS[id]
	_notify("+%d %s (%s)" % [amount, m.name, m.sym], m.color.lightened(0.3))


func _add_sample(depth: float) -> void:
	trip.samples.append(Items.make_sample(rng, planet.biome, planet.name, depth))
	_notify("Найден неизвестный образец! Изучите его в лаборатории корабля.", Color("#9aff6a"))


## Добыча из недр. Минералы лежат только в жилах (сканер недр их показывает),
## у каждой жилы свой главный минерал, а набор минералов у каждой планеты свой.
## Глубже попадаются редкие. Вне жил почти пусто.
func _dig_loot(p: Vector3) -> void:
	var depth: float = max(0.0, orig_heights_at(p) - ground(p.x, p.z))
	var allowed: Array = profile.minerals
	var rich := _vein(p.x, p.z) > VEIN_LEVEL
	if not allowed.is_empty():
		var chance: float = (0.45 + min(depth, 10.0) * 0.03) if rich else 0.03
		if rng.randf() < chance:
			var id := Items.roll_mineral(rng, planet.biome, depth, allowed, _vein_mineral(p))
			if id != "":
				_add_mineral(id, rng.randi_range(1, 3) if rich else 1)
	if depth > 1.5 and rng.randf() < min(0.015 + depth * 0.005, 0.08):
		_add_sample(depth)


## Главный минерал жилы: зависит от участка 24×24 м.
func _vein_mineral(p: Vector3) -> String:
	var allowed: Array = profile.minerals
	if allowed.is_empty():
		return ""
	var h := absi(hash(Vector2i(floori(p.x / 24.0), floori(p.z / 24.0))) + int(planet.seed))
	return allowed[h % allowed.size()]


## Опускает землю вокруг точки. Возвращает false, если копать больше некуда.
func _dig(p: Vector3, strength: float) -> bool:
	const R := 1.8
	var n := SIZE + 1
	var cx := p.x + SIZE / 2.0
	var cz := p.z + SIZE / 2.0
	var ix0 := clampi(floori(cx - R), 1, SIZE - 1)
	var ix1 := clampi(ceili(cx + R), 1, SIZE - 1)
	var iz0 := clampi(floori(cz - R), 1, SIZE - 1)
	var iz1 := clampi(ceili(cz + R), 1, SIZE - 1)
	var changed := false
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var d := Vector2(ix - cx, iz - cz).length()
			if d > R:
				continue
			var i := iz * n + ix
			var k := 1.0 - d / R
			var floor_h := orig_heights[i] - max_depth()
			var nh: float = max(floor_h, heights[i] - strength * k * k * 2.0)
			if nh < heights[i] - 0.001:
				heights[i] = nh
				changed = true
	if not changed:
		return false
	GameState.stats.dug += 1
	# Перестраиваем затронутые куски (с запасом в клетку для нормалей).
	var per_side := SIZE / CHUNK
	for chz in range(clampi((iz0 - 2) / CHUNK, 0, per_side - 1), clampi((iz1 + 2) / CHUNK, 0, per_side - 1) + 1):
		for chx in range(clampi((ix0 - 2) / CHUNK, 0, per_side - 1), clampi((ix1 + 2) / CHUNK, 0, per_side - 1) + 1):
			_chunks[chz * per_side + chx].mesh = _chunk_mesh(chx, chz)
	_hmap.map_data = heights
	# Трава в яме пропадает.
	for gz in range(floori((p.z - R) / 4.0), floori((p.z + R) / 4.0) + 1):
		for gx in range(floori((p.x - R) / 4.0), floori((p.x + R) / 4.0) + 1):
			for gi in _grass_cells.get(Vector2i(gx, gz), []):
				var t := _grass.get_instance_transform(gi)
				if Vector2(t.origin.x, t.origin.z).distance_to(Vector2(p.x, p.z)) < R:
					_grass.set_instance_transform(gi, Transform3D(Basis().scaled(Vector3.ZERO), t.origin))
	# Предметы и животные не должны висеть в воздухе.
	for it in items:
		var np: Vector3 = it.node.position
		it.node.position.y = min(np.y, ground(np.x, np.z))
	return true


func _interact() -> void:
	if inside:
		match _ship_zone():
			"hatch":
				_exit_ship()
			"cockpit":
				_leave()
			"lab":
				_open_lab()
	elif ship.global_position.distance_to(player.global_position) < TAKEOFF_DIST:
		_enter_ship()


func _leave() -> void:
	leaving = true
	GameState.health = hp
	for id in trip.minerals:
		GameState.add_item(id, int(trip.minerals[id]))
		GameState.stats.minerals += int(trip.minerals[id])
	for s in trip.samples:
		GameState.samples.append(s)
	GameState.stats.samples += trip.samples.size()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/system/star_system.tscn")


## Капитан погиб: конец игры, титры во славу исследователя.
func _die() -> void:
	leaving = true
	GameState.health = 100.0
	GameState.death = {"planet": planet.name, "biome": B.name}
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/credits.tscn")


func _notify(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_feed.add_child(l)
	_feed_time = 2.5
	while _feed.get_child_count() > 5:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()


# ---------- Скафандр ----------

## Укрытие от излучения: глубокая яма (вырытая лапатроном) или место под корпусом корабля.
func _in_cover() -> bool:
	var p := player.position
	var dug := orig_heights_at(p) - ground(p.x, p.z)
	if dug > 1.6 and p.y < orig_heights_at(p) + 0.5:
		return true
	return Vector2(p.x, p.z).distance_to(Vector2(ship.position.x, ship.position.z)) < 4.5


func _suit_outside(delta: float) -> void:
	var suit: Dictionary = GameState.suit
	var protect := 0.6 if GameState.has_device("suit") else 1.0
	# Кислород.
	suit.oxygen = max(0.0, suit.oxygen - 100.0 / 240.0 * float(profile.o2) * delta)
	if suit.oxygen <= 0.0:
		hp -= 4.0 * delta
	# Радиация: на открытой местности защита тает всё быстрее, в укрытии медленно.
	cover = _in_cover()
	var rad: float = profile.rad
	var rate: float
	if cover:
		t_open = max(0.0, t_open - delta * 3.0)
		rate = rad * 0.08
	else:
		t_open += delta
		rate = rad * 0.22 * (1.0 + t_open / 60.0)
	suit.rad = max(0.0, suit.rad - rate * protect * delta)
	if suit.rad <= 0.0:
		hp -= rad * 1.5 * delta
	for key in ["oxygen", "rad", "armor"]:
		var low: bool = suit[key] < 25.0
		if low and not _warned.get(key, false):
			_notify({"oxygen": "Мало кислорода! Вернитесь на корабль.",
				"rad": "Радзащита на исходе! Нужен отсек ремонта на корабле.",
				"armor": "Броня почти разбита!"}[key], Color("#ff6a4a"))
		_warned[key] = low


## Урон от животных и лавы: сначала его принимает броня скафандра.
func _hurt(amount: float) -> void:
	var a := amount * (0.6 if GameState.has_device("suit") else 1.0)
	var suit: Dictionary = GameState.suit
	if suit.armor > 0.0:
		suit.armor = max(0.0, suit.armor - a * 0.8)
		hp -= a * 0.25
	else:
		hp -= a


# ---------- Корабль изнутри ----------

func _solid(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = INTERIOR + pos
	add_child(mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = INTERIOR + pos
	add_child(body)


func _deco(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = INTERIOR + pos
	add_child(mi)
	return mi


func _sign(text: String, pos: Vector3, rot_y: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.003
	l.modulate = col
	l.outline_size = 8
	l.position = INTERIOR + pos
	l.rotation.y = rot_y
	add_child(l)


func _lamp(pos: Vector3, col: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.position = INTERIOR + pos
	add_child(l)


## Внутри корабля: коридор от шлюза к кабине, сбоку отсек ремонта оборудования.
## Отсек стоит глубоко под поверхностью, его не видно снаружи.
func _build_interior() -> void:
	var wall := ShipBuilder.metal(Color("#8a929e"), 0.5, 0.55)
	var dark := ShipBuilder.metal(Color("#3a404a"), 0.7, 0.5)
	var floor_m := ShipBuilder.metal(Color("#4a505c"), 0.8, 0.35)
	var strip := ShipBuilder.unshaded(Color(0.6, 1.6, 2.4))
	var warm := ShipBuilder.unshaded(Color(2.4, 1.5, 0.5))
	# Пол и потолок общие для всех помещений.
	_solid(Vector3(14, 0.3, 22), Vector3(0, -0.15, -2), floor_m)
	_solid(Vector3(14, 0.3, 22), Vector3(0, 3.0, -2), dark)
	# Коридор: x от -1.5 до 1.5, z от -6 до 7.
	_solid(Vector3(0.3, 3, 3), Vector3(-1.65, 1.5, -4.5), wall)       # левая стена до двери
	_solid(Vector3(0.3, 3, 8), Vector3(-1.65, 1.5, 3.0), wall)        # левая стена после двери
	_solid(Vector3(0.3, 0.6, 2.0), Vector3(-1.65, 2.7, -2.0), wall)   # над дверью
	_build_lab(wall, dark)
	_solid(Vector3(0.3, 3, 3), Vector3(1.65, 1.5, -4.5), wall)        # правая стена до двери
	_solid(Vector3(0.3, 3, 5), Vector3(1.65, 1.5, 4.5), wall)         # правая стена после двери
	_solid(Vector3(0.3, 0.6, 2.0), Vector3(1.65, 2.7, -2.0), wall)    # над дверью
	_solid(Vector3(3.6, 3, 0.3), Vector3(0, 1.5, 7.15), dark)          # шлюз (выход)
	_deco(Vector3(1.6, 2.3, 0.05), Vector3(0, 1.2, 6.98), warm)
	_sign("Шлюз · E: выйти наружу", Vector3(0, 2.6, 6.9), PI, Color("#ffbf55"))
	for z in [-4.0, -1.0, 2.0, 5.0]:
		_deco(Vector3(2.6, 0.04, 0.12), Vector3(0, 2.83, z), strip)
		_lamp(Vector3(0, 2.4, z), Color(0.75, 0.9, 1.0), 0.9, 6.0)
	# Отсек ремонта оборудования: x от 1.8 до 7, z от -3 до 3 (дверь в коридоре z от -3 до -1).
	_solid(Vector3(5.4, 3, 0.3), Vector3(4.5, 1.5, -3.15), wall)
	_solid(Vector3(5.4, 3, 0.3), Vector3(4.5, 1.5, 3.15), wall)
	_solid(Vector3(0.3, 3, 6.6), Vector3(7.15, 1.5, 0), wall)
	_sign("Отсек ремонта оборудования", Vector3(1.4, 2.55, -2.0), -PI / 2.0, Color("#6fdcff"))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0
	tm.outer_radius = 1.15
	tm.material = ShipBuilder.unshaded(Color(0.4, 2.6, 1.6))
	ring.mesh = tm
	ring.position = INTERIOR + Vector3(4.5, 0.03, 0)
	add_child(ring)
	_bay_ring = ring
	_deco(Vector3(0.6, 1.2, 2.2), Vector3(6.6, 0.6, 0), dark)          # верстак
	_deco(Vector3(0.05, 0.7, 1.6), Vector3(6.28, 1.6, 0), ShipBuilder.unshaded(Color(0.3, 1.2, 2.2)))
	_deco(Vector3(0.5, 1.9, 0.6), Vector3(6.6, 1.0, -2.3), ShipBuilder.metal(Color("#e8eaee"), 0.3, 0.5))  # стойка со скафандром
	_deco(Vector3(0.4, 0.4, 0.05), Vector3(6.6, 2.15, -2.0), ShipBuilder.unshaded(Color(1.4, 1.8, 2.4)))
	_lamp(Vector3(4.5, 2.5, 0), Color(0.6, 1.0, 0.85), 1.6, 7.0)
	_bay_light = OmniLight3D.new()
	_bay_light.light_color = Color(0.4, 1.0, 0.7)
	_bay_light.omni_range = 4.0
	_bay_light.light_energy = 0.0
	_bay_light.position = INTERIOR + Vector3(4.5, 0.6, 0)
	add_child(_bay_light)
	# Кабина: z от -6 до -10, шире коридора.
	_solid(Vector3(0.3, 3, 4.5), Vector3(-2.65, 1.5, -8.0), wall)
	_solid(Vector3(0.3, 3, 4.5), Vector3(2.65, 1.5, -8.0), wall)
	_solid(Vector3(1.2, 3, 0.3), Vector3(-2.1, 1.5, -5.85), wall)
	_solid(Vector3(1.2, 3, 0.3), Vector3(2.1, 1.5, -5.85), wall)
	_solid(Vector3(5.6, 3, 0.3), Vector3(0, 1.5, -10.25), dark)
	var view := ShipBuilder.unshaded(Color(B.sky_hor) * 1.1)
	_deco(Vector3(4.4, 1.3, 0.05), Vector3(0, 1.9, -10.08), view)      # обзорное окно
	_deco(Vector3(4.6, 0.9, 0.9), Vector3(0, 0.45, -9.4), dark)        # пульт
	for x in [-1.4, 0.0, 1.4]:
		_deco(Vector3(0.9, 0.04, 0.5), Vector3(x, 0.92, -9.3), ShipBuilder.unshaded(Color(0.4, 1.6, 2.6) if x != 0.0 else Color(2.4, 1.4, 0.4)))
	_deco(Vector3(0.8, 0.5, 0.8), Vector3(0, 0.45, -8.2), floor_m)      # кресло пилота
	_deco(Vector3(0.8, 1.0, 0.15), Vector3(0, 1.1, -7.8), floor_m)
	_sign("Кабина · E: взлететь", Vector3(0, 2.6, -6.05), 0.0, Color("#ffbf55"))
	_lamp(Vector3(0, 2.3, -8.5), Color(1.0, 0.85, 0.6), 1.2, 6.0)


## Научный отсек: слева от коридора, напротив отсека ремонта.
## Здесь стоит учёный (если он есть в экипаже), перерабатывают минералы и изучают образцы.
func _build_lab(wall: Material, dark: Material) -> void:
	_solid(Vector3(5.4, 3, 0.3), Vector3(-4.5, 1.5, -3.15), wall)
	_solid(Vector3(5.4, 3, 0.3), Vector3(-4.5, 1.5, 3.15), wall)
	_solid(Vector3(0.3, 3, 6.6), Vector3(-7.15, 1.5, 0), wall)
	_sign("Научный отсек", Vector3(-1.4, 2.55, -2.0), PI / 2.0, Color("#9aff6a"))
	var white := ShipBuilder.metal(Color("#e8ecf0"), 0.2, 0.35)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.9, 1.0, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	# Лабораторный стол вдоль дальней стены с микроскопом и контейнерами образцов.
	_deco(Vector3(0.9, 0.9, 4.0), Vector3(-6.5, 0.45, 0.4), white)
	_deco(Vector3(0.95, 0.05, 4.05), Vector3(-6.5, 0.92, 0.4), dark)
	_deco(Vector3(0.25, 0.1, 0.3), Vector3(-6.4, 1.0, -0.6), dark)                 # основание микроскопа
	_deco(Vector3(0.06, 0.4, 0.06), Vector3(-6.5, 1.2, -0.6), dark)
	_deco(Vector3(0.1, 0.1, 0.22), Vector3(-6.42, 1.4, -0.6), dark).rotation.z = 0.6
	_deco(Vector3(0.02, 0.5, 0.9), Vector3(-6.94, 1.6, 1.2), ShipBuilder.unshaded(Color(0.4, 2.2, 1.0)))  # экран анализа
	for i in 5:
		var jar := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.09
		cm.height = 0.28
		cm.material = glass
		jar.mesh = cm
		jar.position = INTERIOR + Vector3(-6.6, 1.09, 1.4 + i * 0.22)
		add_child(jar)
		var core := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		sm.material = ShipBuilder.unshaded(Color(0.6, 2.4, 0.8) if i % 2 == 0 else Color(1.8, 0.8, 2.4))
		core.mesh = sm
		core.position = jar.position
		add_child(core)
		_lab_glow.append(core)
	# Установка переработки минералов: печь с горячим окном и бункер.
	_solid(Vector3(1.4, 2.0, 1.2), Vector3(-5.2, 1.0, -2.3), dark)
	_deco(Vector3(0.7, 0.5, 0.05), Vector3(-5.2, 1.1, -1.68), ShipBuilder.unshaded(Color(3.0, 1.2, 0.3)))
	_deco(Vector3(0.9, 0.4, 0.9), Vector3(-5.2, 2.2, -2.3), white)
	_sign("Переработка минералов", Vector3(-5.2, 2.65, -1.65), 0.0, Color("#ffbf55"))
	_lamp(Vector3(-4.5, 2.5, 0.5), Color(0.85, 1.0, 0.9), 1.5, 7.0)
	_lamp(Vector3(-5.2, 1.0, -1.2), Color(1.0, 0.55, 0.2), 0.8, 3.0)
	# Учёный.
	var sci := GameState.best_scientist()
	if sci.is_empty():
		_sign("Место учёного свободно.\nНаймите учёного на научной станции.", Vector3(-5.5, 1.6, 2.4), PI, Color(0.8, 0.85, 0.95))
	else:
		_scientist = _make_scientist()
		_scientist.position = INTERIOR + Vector3(-5.7, 0, 0.6)
		_scientist.rotation.y = PI / 2.0
		add_child(_scientist)
		_sign("%s · учёный, навык %d" % [sci.name, sci.skill], Vector3(-5.7, 2.15, 0.6), PI / 2.0, Color("#9aff6a"))


func _make_scientist() -> Node3D:
	var g := Node3D.new()
	var coat := ShipBuilder.metal(Color("#f0f2f4"), 0.0, 0.7)
	var skin := ShipBuilder.metal(Color("#d8a888"), 0.0, 0.6)
	var dark := ShipBuilder.metal(Color("#2a3040"), 0.1, 0.6)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.24
	cm.height = 1.1
	cm.material = coat
	body.mesh = cm
	body.position.y = 1.05
	g.add_child(body)
	for s in [-0.12, 0.12]:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.08
		lm.bottom_radius = 0.07
		lm.height = 0.6
		lm.material = dark
		leg.mesh = lm
		leg.position = Vector3(s, 0.3, 0)
		g.add_child(leg)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.15
	hm.height = 0.3
	hm.material = skin
	head.mesh = hm
	head.position.y = 1.78
	head.name = "Head"
	g.add_child(head)
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.22, 0.05, 0.05)
	vm.material = ShipBuilder.unshaded(Color(0.4, 1.8, 2.6))
	visor.mesh = vm
	visor.position = Vector3(0, 0.02, -0.13)
	head.add_child(visor)
	for s in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var am := CapsuleMesh.new()
		am.radius = 0.06
		am.height = 0.6
		am.material = coat
		arm.mesh = am
		arm.position = Vector3(s * 0.3, 1.2, -0.12)
		arm.rotation.x = 0.7
		g.add_child(arm)
	return g


func _animate_lab(delta: float) -> void:
	_lab_time += delta
	for i in _lab_glow.size():
		var k := 1.0 + sin(_lab_time * 2.0 + i) * 0.25
		_lab_glow[i].scale = Vector3.ONE * k
	if _scientist:
		_scientist.position.y = INTERIOR.y + sin(_lab_time * 1.3) * 0.01
		var head: Node3D = _scientist.get_node("Head")
		# Учёный смотрит на капитана, если тот рядом, иначе в микроскоп.
		var to := player.position - _scientist.position
		var want := atan2(-to.x, -to.z) - _scientist.rotation.y if to.length() < 4.0 else sin(_lab_time * 0.5) * 0.3
		head.rotation.y = lerp_angle(head.rotation.y, clamp(wrapf(want, -PI, PI), -1.2, 1.2), min(1.0, delta * 3.0))


## Добыча с прогулки переходит в трюм, как только капитан поднялся на борт.
func _unload_trip() -> void:
	var count := 0
	for id in trip.minerals:
		GameState.add_item(id, int(trip.minerals[id]))
		GameState.stats.minerals += int(trip.minerals[id])
		count += int(trip.minerals[id])
	for s in trip.samples:
		GameState.samples.append(s)
	GameState.stats.samples += trip.samples.size()
	if count > 0 or not trip.samples.is_empty():
		_notify("В трюм: минералов %d, образцов %d" % [count, trip.samples.size()], Color("#ffbf55"))
	trip = {"minerals": {}, "samples": []}


func _open_lab() -> void:
	_menu.open("lab")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _enter_ship() -> void:
	inside = true
	player.position = INTERIOR + Vector3(0, 1.0, 5.2)
	player.velocity = Vector3.ZERO
	yaw = 0.0
	pitch = 0.0
	tool.visible = false
	_radar.visible = false
	_tool_label.visible = false
	# Внутри нет тумана атмосферы и неба, только свои лампы.
	_env.fog_enabled = false
	_env.ambient_light_energy = 0.3
	_notify("Вы на корабле. Кислород пополняется.", Color("#9ad8ff"))
	_unload_trip()


func _exit_ship() -> void:
	inside = false
	var out := ship.position + Vector3(3.5, 0, 3.5)
	player.position = Vector3(out.x, ground(out.x, out.z) + 1.2, out.z)
	player.velocity = Vector3.ZERO
	t_open = 0.0
	_select_tool(tool_index)
	_radar.visible = true
	_tool_label.visible = true
	_env.fog_enabled = true
	_env.ambient_light_energy = 0.9


## Где игрок внутри корабля: "bay" (отсек ремонта), "cockpit", "hatch" или "".
func _ship_zone() -> String:
	var p := player.position - INTERIOR
	if p.x > 1.8:
		return "bay"
	if p.x < -1.8:
		return "lab"
	if p.z < -6.2:
		return "cockpit"
	if p.z > 4.6:
		return "hatch"
	return ""


func _suit_inside(delta: float) -> void:
	var suit: Dictionary = GameState.suit
	suit.oxygen = min(100.0, suit.oxygen + 25.0 * delta)
	hp = min(100.0, hp + 1.0 * delta)
	var zone := _ship_zone()
	if zone == "bay":
		# Чем дольше в отсеке, тем быстрее идёт восстановление.
		t_bay += delta
		var rate := 1.5 * (1.0 + t_bay / 6.0)
		suit.rad = min(100.0, suit.rad + rate * delta)
		suit.armor = min(100.0, suit.armor + rate * delta)
	else:
		t_bay = 0.0
	_animate_lab(delta)
	_bay_ring.rotation.y += delta * (0.5 + t_bay * 0.3)
	_bay_light.light_energy = min(3.0, t_bay * 0.4) if zone == "bay" else 0.0
	for key in ["oxygen", "rad", "armor"]:
		_warned[key] = false


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
	_o2_bar = _bar(col, "Кислород", Color("#8ad0ff"))
	_rad_bar = _bar(col, "Радзащита", Color("#d0e040"))
	_armor_bar = _bar(col, "Броня", Color("#b0b8c8"))
	_env_label = Label.new()
	_env_label.add_theme_font_size_override("font_size", 17)
	col.add_child(_env_label)
	_info = Label.new()
	col.add_child(_info)

	var help := Label.new()
	help.theme = theme
	help.text = "WASD: идти, Shift: бег, пробел: ранец\nМышь: обзор, ЛКМ или F: применить инструмент\n1: бластер, 2: лапатрон (копать и добывать), колесо: сменить\nH: аптечка, E у корабля: подняться на борт, Esc: курсор\nЯмы и корпус корабля укрывают от излучения"
	help.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	help.anchor_left = 1.0
	help.anchor_right = 1.0
	help.offset_left = -760
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

	_tool_label = Label.new()
	_tool_label.theme = theme
	_tool_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_tool_label.anchor_left = 0.5
	_tool_label.anchor_right = 0.5
	_tool_label.anchor_top = 1.0
	_tool_label.anchor_bottom = 1.0
	_tool_label.offset_left = -300
	_tool_label.offset_right = 300
	_tool_label.offset_top = -44
	_tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_tool_label)

	_feed = VBoxContainer.new()
	_feed.theme = theme
	_feed.anchor_left = 1.0
	_feed.anchor_right = 1.0
	_feed.anchor_top = 1.0
	_feed.anchor_bottom = 1.0
	_feed.offset_left = -560
	_feed.offset_right = -20
	_feed.offset_top = -260
	_feed.offset_bottom = -20
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_feed)

	_menu = ShipMenu.new()
	_menu.theme = theme
	_menu.visibility_changed.connect(func():
		if not _menu.visible and not leaving:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	layer.add_child(_menu)

	var radar := PlanetRadar.new()
	_radar = radar
	radar.surface = self
	radar.anchor_top = 1.0
	radar.anchor_bottom = 1.0
	radar.offset_left = 16
	radar.offset_top = -270
	radar.offset_right = 246
	radar.offset_bottom = -16
	layer.add_child(radar)

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
	_prompt.offset_top = -84
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
