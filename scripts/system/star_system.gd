extends Node3D
## Звёздная система: вид сверху, как в «Космических рейнджерах».
## Клик по планете, станции или пустому месту задаёт курс. Колесо мыши меняет масштаб.
## Пока всё строится из кода и процедурных текстур; модели из Blender заменят заготовки позже.

const STAR_COLORS := ["#ffd27a", "#ffe9c4", "#a8c8ff", "#ff9a6a", "#fff4e8"]
const SYLLABLES := ["ка", "ре", "то", "ми", "ан", "ве", "ло", "ри", "за", "ну", "эл", "ор", "си", "та", "гра", "ксе"]
const SHIP_SPEED := 30.0
const BOUNDS := 260.0

var rng := RandomNumberGenerator.new()
var system_name := ""
var planets: Array[Dictionary] = []
var station: Node3D
var station_pos := Vector3.ZERO
var ship: Node3D
var star: MeshInstance3D
var ship_glows: Array[MeshInstance3D] = []
var npcs: Array[Dictionary] = []
var camera: Camera3D
var cam_pos := Vector3.ZERO
var zoom := 1.0
var heading := 0.0
var target: Dictionary = {}
var near := ""

var _time_label: Label
var _money_label: Label
var _status_label: Label
var _cargo_label: Label
var _land_button: Button
var _target_marker: MeshInstance3D
var _glow_tex: GradientTexture2D


func _ready() -> void:
	rng.seed = GameState.galaxy_seed
	_generate()
	_build_environment()
	_build_star()
	_build_planets()
	_build_station()
	_build_ship()
	_build_traffic()
	_build_camera()
	_restore_state()
	_build_ui()
	_update_camera(1.0, true)
	_set_status()


# ---------- Генерация ----------

func _generate() -> void:
	system_name = ""
	for i in rng.randi_range(2, 3):
		system_name += SYLLABLES[rng.randi() % SYLLABLES.size()]
	system_name = system_name.capitalize()
	var keys := Biomes.DATA.keys()
	for i in rng.randi_range(2, 3):
		planets.append({
			"name": "%s %s" % [system_name, ["I", "II", "III"][i]],
			"biome": keys[rng.randi() % keys.size()],
			"seed": rng.randi(),
			"size": rng.randf_range(7.0, 13.0),
			"orbit": 80.0 + i * 50.0 + rng.randf() * 8.0,
			"phase": rng.randf() * TAU,
			"speed": 0.03 / (1.0 + i * 0.6),
		})


# ---------- Окружение ----------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = _nebula_texture()
	sky.sky_material = pano
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.36, 0.5)
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Звёзды фона: светящиеся точки далеко под плоскостью системы
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.8
	dot.height = 1.6
	dot.radial_segments = 6
	dot.rings = 3
	dot.material = _unshaded(Color(1.6, 1.6, 1.8))
	mm.mesh = dot
	mm.instance_count = 1500
	for i in mm.instance_count:
		var p := Vector3(rng.randf_range(-1800, 1800), rng.randf_range(-900, -350), rng.randf_range(-1800, 1800))
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.6)), p))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	add_child(stars)


func _nebula_texture() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.0025
	n.fractal_octaves = 7
	n.domain_warp_enabled = true
	n.domain_warp_amplitude = 60.0
	var t := NoiseTexture2D.new()
	t.width = 2048
	t.height = 1024
	t.seamless = true
	t.noise = n
	t.color_ramp = _gradient([[0.0, Color(0.004, 0.006, 0.016)], [0.45, Color(0.01, 0.012, 0.04)],
		[0.6, Color(0.16, 0.06, 0.3)], [0.72, Color(0.12, 0.22, 0.55)], [0.86, Color(0.55, 0.3, 0.7)], [1.0, Color(0.95, 0.7, 0.9)]])
	return t


func _build_star() -> void:
	var col := Color(STAR_COLORS[rng.randi() % STAR_COLORS.size()])
	var mesh := SphereMesh.new()
	mesh.radius = 10.0
	mesh.height = 20.0
	mesh.radial_segments = 64
	mesh.rings = 32
	# Поверхность звезды: зернистая плазма с тёмными пятнами и яркими вспышками.
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.02
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	n.domain_warp_enabled = true
	n.domain_warp_amplitude = 25.0
	var ramp := _gradient([[0.0, col.darkened(0.55)], [0.35, col.darkened(0.15)], [0.7, col], [1.0, col.lerp(Color.WHITE, 0.7)]])
	var mat := _unshaded(Color.WHITE)
	mat.albedo_texture = _noise_texture(n, 1024, 512, ramp, false)
	mat.emission_enabled = true
	mat.emission_texture = mat.albedo_texture
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 2.2
	mesh.material = mat
	star = MeshInstance3D.new()
	star.mesh = mesh
	add_child(star)
	add_child(_glow(col, 46.0, 1.4))
	add_child(_glow(col, 120.0, 0.35))
	var light := OmniLight3D.new()
	light.light_color = col.lerp(Color.WHITE, 0.5)
	light.light_energy = 4.0
	light.omni_range = 1000.0
	light.omni_attenuation = 0.4
	add_child(light)


func _build_planets() -> void:
	for p in planets:
		var b: Dictionary = Biomes.DATA[p.biome]
		var body := Node3D.new()
		add_child(body)
		var sphere := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = p.size
		sm.height = p.size * 2.0
		sm.radial_segments = 64
		sm.rings = 32
		var mat := StandardMaterial3D.new()
		var surf := _planet_noise(p.seed)
		mat.albedo_texture = _noise_texture(surf, 1024, 512, _gradient_hex(b.stops), false)
		mat.normal_enabled = true
		mat.normal_texture = _noise_texture(surf, 1024, 512, null, true)
		mat.normal_scale = 0.6
		mat.roughness = 0.9
		if p.biome == "volcano":
			mat.emission_enabled = true
			mat.emission_texture = mat.albedo_texture
			mat.emission = Color(1.0, 0.35, 0.1)
			mat.emission_energy_multiplier = 0.6
		sm.material = mat
		sphere.mesh = sm
		body.add_child(sphere)

		var clouds := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = p.size * 1.025
		cm.height = p.size * 2.05
		cm.radial_segments = 64
		cm.rings = 32
		var cmat := StandardMaterial3D.new()
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c: Color = b.cloud
		var cn := _planet_noise(p.seed + 77)
		cn.domain_warp_enabled = true
		cn.domain_warp_amplitude = 40.0
		cmat.albedo_texture = _noise_texture(cn, 1024, 512, _gradient([[0.0, Color(c, 0)], [0.55, Color(c, 0)], [0.8, Color(c, 0.85)], [1.0, Color(c, 1)]]), false)
		cmat.roughness = 1.0
		cm.material = cmat
		clouds.mesh = cm
		body.add_child(clouds)
		body.add_child(_glow(b.atmo, p.size * 2.4, 0.45))

		var label := _label3d(p.name, Color(0.9, 0.93, 1.0))
		add_child(label)
		_add_orbit(p.orbit)
		p["node"] = body
		p["sphere"] = sphere
		p["clouds"] = clouds
		p["label"] = label


func _build_station() -> void:
	var a := rng.randf() * TAU
	station_pos = Vector3(cos(a), 0, sin(a)) * 48.0
	station = Node3D.new()
	station.position = station_pos
	add_child(station)
	var metal := _metal(Color("#b8c0cc"), 0.85, 0.32)
	var dark := _metal(Color("#3a404c"), 0.7, 0.45)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 5.0
	tm.outer_radius = 6.4
	tm.rings = 64
	tm.ring_segments = 16
	tm.material = metal
	ring.mesh = tm
	station.add_child(ring)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 1.6
	hm.bottom_radius = 1.6
	hm.height = 4.0
	hm.material = dark
	hub.mesh = hm
	station.add_child(hub)
	for i in 4:
		var spoke := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(11.4, 0.3, 0.4)
		bm.material = dark
		spoke.mesh = bm
		spoke.rotation.y = i * PI / 4.0
		station.add_child(spoke)
	for i in 10:
		var la := i / 10.0 * TAU
		var l := _glow(Color("#6fb7ff"), 1.4, 2.0)
		l.position = Vector3(cos(la) * 5.7, 0.7, sin(la) * 5.7)
		station.add_child(l)
	var lbl := _label3d("Станция", Color("#6fb7ff"))
	lbl.position = Vector3(0, 0, 10)
	station.add_child(lbl)


func _build_ship() -> void:
	var made := _make_ship(Color("#dfe4ec"), Color("#2f5fb0"), Color("#7fd8ff"))
	ship = made.node
	ship_glows = made.glows
	ship.scale = Vector3.ONE * 0.75
	ship.position = station_pos + Vector3(8, 0, 8)
	add_child(ship)
	target = {"type": "station"}
	near = "station"
	_target_marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.6
	tm.outer_radius = 2.0
	tm.material = _unshaded(Color(1.6, 1.1, 0.4))
	_target_marker.mesh = tm
	_target_marker.visible = false
	add_child(_target_marker)


func _build_traffic() -> void:
	var palettes := [[Color("#e2e2e2"), Color("#b02a2a"), Color("#ff7060")], [Color("#9aa8b0"), Color("#2ab0a0"), Color("#60ffe8")], [Color("#7a5a40"), Color("#d08030"), Color("#ff8a30")]]
	for i in 3:
		var pal: Array = palettes[i]
		var made := _make_ship(pal[0], pal[1], pal[2])
		var n: Node3D = made.node
		n.scale = Vector3.ONE * 0.6
		n.position = _random_point(40, 170)
		add_child(n)
		npcs.append({"node": n, "to": _random_point(30, 180), "speed": rng.randf_range(9, 15)})


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 4000.0
	add_child(camera)


# ---------- Модели ----------

func _make_ship(hull_col: Color, accent_col: Color, glow_col: Color) -> Dictionary:
	# Нос корабля смотрит в -Z, как принято в Godot.
	var root := Node3D.new()
	var hull := _metal(hull_col, 0.8, 0.3)
	var accent := _metal(accent_col, 0.55, 0.4)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.95
	cap.height = 6.0
	cap.material = hull
	body.mesh = cap
	body.rotation.x = PI / 2.0
	body.scale = Vector3(1, 1, 0.72)
	root.add_child(body)
	var canopy := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 0.5
	cs.height = 1.0
	var glass := _metal(Color("#1a2a40"), 1.0, 0.05)
	cs.material = glass
	canopy.mesh = cs
	canopy.scale = Vector3(0.85, 0.55, 1.5)
	canopy.position = Vector3(0, 0.55, -1.1)
	root.add_child(canopy)
	var glows: Array[MeshInstance3D] = []
	for s in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(3.6, 3.0, 0.14)
		pm.left_to_right = 0.0 if s > 0 else 1.0
		pm.material = hull
		wing.mesh = pm
		wing.rotation.x = -PI / 2.0
		wing.position = Vector3(s * 2.4, 0, 0.9)
		root.add_child(wing)
		var tip := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.18, 0.22, 1.3)
		tb.material = accent
		tip.mesh = tb
		tip.position = Vector3(s * 4.2, 0, 1.6)
		root.add_child(tip)
		var g := _glow(glow_col, 2.4, 2.5)
		g.position = Vector3(s * 0.6, -0.1, 3.3)
		root.add_child(g)
		glows.append(g)
	var fin := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.1, 1.0, 1.4)
	fb.material = accent
	fin.mesh = fb
	fin.position = Vector3(0, 0.75, 1.8)
	fin.rotation.x = 0.35
	root.add_child(fin)
	return {"node": root, "glows": glows}


# ---------- Вспомогательное ----------

func _planet_noise(seed_value: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.006
	n.fractal_octaves = 6
	return n


func _noise_texture(n: FastNoiseLite, w: int, h: int, ramp: Gradient, normal: bool) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = w
	t.height = h
	t.seamless = true
	t.noise = n
	if normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	elif ramp:
		t.color_ramp = ramp
	return t


func _gradient(stops: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	return g


func _gradient_hex(stops: Array) -> Gradient:
	var conv := []
	for s in stops:
		conv.append([s[0], Color(s[1])])
	return _gradient(conv)


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _metal(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m


func _glow(c: Color, size: float, strength: float) -> MeshInstance3D:
	if _glow_tex == null:
		_glow_tex = GradientTexture2D.new()
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.gradient = _gradient([[0.0, Color(1, 1, 1, 1)], [0.15, Color(1, 1, 1, 0.6)], [0.4, Color(1, 1, 1, 0.15)], [1.0, Color(1, 1, 1, 0)]])
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _glow_tex
	m.albedo_color = Color(c.r * strength, c.g * strength, c.b * strength, 1.0)
	m.no_depth_test = false
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _label3d(text: String, c: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.modulate = c
	l.font_size = 30
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0008
	return l


func _add_orbit(r: float) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _unshaded(Color(0.37, 0.56, 0.85, 0.45)))
	for i in 161:
		var a := i / 160.0 * TAU
		im.surface_add_vertex(Vector3(cos(a) * r, 0, sin(a) * r))
	im.surface_end()
	var mat: StandardMaterial3D = im.surface_get_material(0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = im
	add_child(mi)


func _random_point(rmin: float, rmax: float) -> Vector3:
	var a := rng.randf() * TAU
	return Vector3(cos(a), 0, sin(a)) * rng.randf_range(rmin, rmax)


func _planet_pos(p: Dictionary) -> Vector3:
	var a: float = p.phase + GameState.hours * p.speed
	return Vector3(cos(a), 0, sin(a)) * p.orbit


# ---------- Каждый кадр ----------

func _process(delta: float) -> void:
	for p in planets:
		var pos := _planet_pos(p)
		p.node.position = pos
		p.sphere.rotation.y += delta * 0.12
		p.clouds.rotation.y += delta * 0.16
		p.label.position = pos + Vector3(0, 0, p.size + 5.0)
	station.rotation.y += delta * 0.25
	star.rotation.y += delta * 0.03
	_move_ship(delta)
	for n in npcs:
		var node: Node3D = n.node
		var to: Vector3 = n.to
		var d := to - node.position
		if d.length() < 2.0:
			n.to = _random_point(30, 180)
		else:
			node.position += d.normalized() * float(n.speed) * delta
			node.look_at(node.position + d, Vector3.UP)
	_update_camera(delta, false)
	_time_label.text = GameState.time_text()
	_money_label.text = "ПОТОМ: %d" % GameState.money
	_cargo_label.text = "Трюм: руда %d, образцы %d" % [GameState.cargo.ore, GameState.cargo.samples]


func _target_info() -> Dictionary:
	match target.get("type", ""):
		"planet":
			var p: Dictionary = planets[target.index]
			return {"pos": _planet_pos(p), "stop": float(p.size) + 5.0, "key": "planet%d" % target.index}
		"station":
			return {"pos": station_pos, "stop": 8.0, "key": "station"}
		"point":
			return {"pos": target.pos, "stop": 0.4, "key": ""}
	return {}


func _move_ship(delta: float) -> void:
	var info := _target_info()
	var moving := false
	if not info.is_empty():
		var to: Vector3 = info.pos - ship.position
		to.y = 0
		var d := to.length()
		if d > info.stop + 0.05:
			var step: float = min(d - info.stop, SHIP_SPEED * delta)
			ship.position += to / d * step
			moving = step > SHIP_SPEED * delta * 0.3
			var want := atan2(-to.x, -to.z)
			heading = lerp_angle(heading, want, min(1.0, delta * 5.0))
		elif info.key != "" and near != info.key:
			near = info.key
			_set_status()
		elif info.key == "":
			target = {}
			_target_marker.visible = false
	ship.position.x = clamp(ship.position.x, -BOUNDS, BOUNDS)
	ship.position.z = clamp(ship.position.z, -BOUNDS, BOUNDS)
	ship.rotation = Vector3(0, heading, sin(Time.get_ticks_msec() * 0.002) * 0.05 if moving else 0.0)
	for g in ship_glows:
		var s: float = 1.0 + randf() * 0.25 if moving else 0.45
		g.scale = Vector3.ONE * s


func _update_camera(delta: float, snap: bool) -> void:
	var want := ship.position + Vector3(0, 115.0 * zoom, 85.0 * zoom)
	cam_pos = want if snap else cam_pos.lerp(want, min(1.0, delta * 3.0))
	camera.position = cam_pos
	camera.look_at(cam_pos + Vector3(0, -115.0, -85.0), Vector3.UP)


# ---------- Ввод ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		_land()
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_click(event.position)
			MOUSE_BUTTON_WHEEL_UP:
				zoom = clamp(zoom / 1.12, 0.35, 2.6)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom = clamp(zoom * 1.12, 0.35, 2.6)


func _click(screen: Vector2) -> void:
	var best := {}
	var best_d := INF
	for i in planets.size():
		var p: Dictionary = planets[i]
		var pos: Vector3 = p.node.position
		if camera.is_position_behind(pos):
			continue
		var c := camera.unproject_position(pos)
		var edge := camera.unproject_position(pos + camera.global_transform.basis.x * float(p.size))
		var r: float = max(18.0, c.distance_to(edge)) + 6.0
		var d := c.distance_to(screen)
		if d < r and d < best_d:
			best_d = d
			best = {"type": "planet", "index": i}
	var sc := camera.unproject_position(station_pos)
	if sc.distance_to(screen) < 26.0 and sc.distance_to(screen) < best_d:
		best = {"type": "station"}
	if best.is_empty():
		var from := camera.project_ray_origin(screen)
		var dir := camera.project_ray_normal(screen)
		var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
		if hit == null:
			return
		var pt: Vector3 = hit
		pt.x = clamp(pt.x, -BOUNDS + 5, BOUNDS - 5)
		pt.z = clamp(pt.z, -BOUNDS + 5, BOUNDS - 5)
		best = {"type": "point", "pos": pt}
		_target_marker.position = pt
		_target_marker.visible = true
	else:
		_target_marker.visible = false
	if near == "station":
		print("Отстыковались от станции")
	target = best
	near = ""
	_set_status()


# ---------- Интерфейс ----------

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	# Корневой узел интерфейса с общей темой: крупный шрифт для всех надписей и кнопок.
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 20
	layer.theme = theme
	canvas.add_child(layer)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#16305a")
	style.border_color = Color("#4a78bc")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 6

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", style)
	top.position = Vector2(16, 16)
	layer.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	top.add_child(row)
	var title := Label.new()
	title.text = "СТРАННИКИ ГАЛАКТИКИ · Система %s" % system_name
	title.add_theme_color_override("font_color", Color("#ffbf55"))
	row.add_child(title)
	_time_label = Label.new()
	row.add_child(_time_label)
	_money_label = Label.new()
	row.add_child(_money_label)
	_cargo_label = Label.new()
	row.add_child(_cargo_label)

	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", style)
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -86
	bottom.offset_bottom = -16
	layer.add_child(bottom)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 14)
	bottom.add_child(brow)
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brow.add_child(_status_label)
	_land_button = Button.new()
	_land_button.text = "  Высадиться (L)  "
	_land_button.add_theme_color_override("font_color", Color("#ffbf55"))
	_land_button.pressed.connect(_land)
	brow.add_child(_land_button)
	for spec in [["−", 1.25], ["+", 1.0 / 1.25]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(48, 48)
		var k: float = spec[1]
		b.pressed.connect(func(): zoom = clamp(zoom * k, 0.35, 2.6))
		brow.add_child(b)

	var help := Label.new()
	help.text = "Клик по планете, станции или пустому месту: лететь туда.\nКолесо мыши: масштаб. У планеты: L или «Высадиться».\nВремя в галактике идёт постоянно."
	help.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	help.anchor_left = 1.0
	help.anchor_right = 1.0
	help.offset_left = -760
	help.offset_right = -16
	help.offset_top = 84
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(help)


func _set_status() -> void:
	if _status_label == null:
		return
	_land_button.visible = near.begins_with("planet")
	if near == "station":
		_status_label.text = "Пристыкованы к станции."
	elif near.begins_with("planet"):
		var p: Dictionary = planets[int(near.substr(6))]
		_status_label.text = "На орбите планеты %s (%s). Можно высаживаться." % [p.name, Biomes.DATA[p.biome].name]
	elif not target.is_empty():
		_status_label.text = "Летим…"
	else:
		_status_label.text = "Выберите цель."


# ---------- Высадка ----------

func _land() -> void:
	if not near.begins_with("planet"):
		return
	var i := int(near.substr(6))
	var p: Dictionary = planets[i]
	GameState.current_planet = {"name": p.name, "biome": p.biome, "seed": p.seed}
	GameState.system_state = {"planet": i}
	get_tree().change_scene_to_file("res://scenes/planet/planet_surface.tscn")


## После взлёта с планеты корабль появляется на её орбите.
## Планета за это время сдвинулась: время в галактике шло, пока мы гуляли.
func _restore_state() -> void:
	if GameState.system_state.is_empty():
		return
	var i: int = GameState.system_state.get("planet", -1)
	GameState.system_state = {}
	if i < 0 or i >= planets.size():
		return
	var p: Dictionary = planets[i]
	var pos := _planet_pos(p)
	var out := Vector3(pos.x, 0, pos.z).normalized()
	ship.position = pos + out * (float(p.size) + 5.0)
	heading = atan2(-out.x, -out.z)
	target = {"type": "planet", "index": i}
	near = "planet%d" % i
