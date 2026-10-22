class_name ShipBuilder
extends RefCounted
## Сборка заготовок кораблей и светящихся спрайтов из примитивов.
## Нос корабля смотрит в -Z, как принято в Godot. Позже заменим на модели из Blender.


static func make_ship(hull_col: Color, accent_col: Color, glow_col: Color) -> Dictionary:
	var root := Node3D.new()
	var hull := metal(hull_col, 0.8, 0.3)
	var accent := metal(accent_col, 0.55, 0.4)
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
	cs.material = metal(Color("#1a2a40"), 1.0, 0.05)
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
		var g := glow(glow_col, 2.4, 2.5)
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


static func metal(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m


static func unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


static func gradient(stops: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1] if s[1] is Color else Color(s[1]))
	g.offsets = offs
	g.colors = cols
	return g


## Светящееся пятно, всегда повёрнутое к камере. strength > 1 даёт свечение (glow).
static func glow(c: Color, size: float, strength: float) -> MeshInstance3D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.gradient = gradient([[0.0, Color(1, 1, 1, 1)], [0.15, Color(1, 1, 1, 0.6)], [0.4, Color(1, 1, 1, 0.15)], [1.0, Color(1, 1, 1, 0)]])
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = tex
	m.albedo_color = Color(c.r * strength, c.g * strength, c.b * strength, 1.0)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Неровный «булыжник» из сферы: для камней, крон деревьев и кустов.
static func blob_mesh(seed_value: int, radial: int, rings: int, roughness: float) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radial_segments = radial
	sm.rings = rings
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 1.1
	n.fractal_octaves = 4
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + n.get_noise_3dv(v * 1.7) * roughness
		verts[i] = Vector3(v.x * k, v.y * k * 0.8, v.z * k)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.generate_normals()
	return st.commit()
