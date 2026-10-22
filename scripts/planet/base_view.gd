class_name BaseView
extends Node3D
## База на поверхности планеты: модули вокруг командного модуля, мастера и солдаты.
## Данные базы живут в GameState.bases (время галактики идёт и без капитана),
## здесь только то, что видно и с чем можно драться на месте.
## Мастера чинят модуль. Если напасть на них, они отбиваются, а их планета объявляет войну.
## Солдаты армии высаживаются при налёте и ломают модули; турели и экипаж отстреливаются.

const NPC_SPEED := 5.0
const SHOT_RANGE := 18.0
const TURRET_RANGE := 40.0

var surface: Node3D
var base: Dictionary = {}
var npcs: Array[Dictionary] = []
var _models := {}        # uid → {"node", "light", "tag", "spin"}
var _raid := {}          # {"faction", "left"} пока идёт бой на месте
var _turret_cd := {}
var _beams: Array[Dictionary] = []
var _t := 0.0
var _label_t := 0.0
var _flat := false
var _spawned_visit := -1.0  # для какого визита мастеров уже вывели NPC


func setup(s: Node3D) -> void:
	surface = s
	GameState.raid_started.connect(_on_raid)
	rebuild()


func key() -> String:
	return str(surface.planet.seed)


func center() -> Vector3:
	if base.is_empty():
		return Vector3.ZERO
	var c := Vector2(base.center[0], base.center[1])
	return Vector3(c.x, surface.ground(c.x, c.y), c.y)


## Новая база рядом с кораблём.
func found() -> void:
	var sp: Vector3 = surface.ship.position
	var c := Vector2(sp.x + 48.0, sp.z + 16.0)
	GameState.bases[key()] = BaseData.new_base(surface.planet, c)
	GameState.hero_xp("leadership", 3)
	surface._notify("База основана! Модули и оборудование заказывают на станции и в развитых колониях.", Color("#9aff6a"))
	rebuild()


func rebuild() -> void:
	for k in _models:
		_models[k].node.queue_free()
	_models.clear()
	base = GameState.bases.get(key(), {})
	if base.is_empty():
		return
	if not _flat:
		_flat = true
		surface.flatten(Vector2(base.center[0], base.center[1]), 33.0, 44.0)
	for m in base.modules:
		_add_model(m)


func _module_pos(m: Dictionary) -> Vector3:
	var o := BaseData.slot_offset(int(m.slot))
	var c := Vector2(base.center[0], base.center[1]) + o
	return Vector3(c.x, surface.ground(c.x, c.y), c.y)


# ---------- Модели модулей ----------

func _add_model(m: Dictionary) -> void:
	var g := Node3D.new()
	g.position = _module_pos(m)
	add_child(g)
	var white := ShipBuilder.metal(Color("#dfe4ec"), 0.6, 0.35)
	var grey := ShipBuilder.metal(Color("#6a7280"), 0.7, 0.45)
	var dark := ShipBuilder.metal(Color("#2a3040"), 0.5, 0.5)
	# Фундамент уходит в землю, чтобы на склонах не висеть в воздухе.
	_box(g, Vector3(9, 4, 9), Vector3(0, -1.6, 0), grey)
	var spin: Node3D = null
	match m.id:
		"core":
			_cyl(g, 4.2, 4.4, 2.0, Vector3(0, 1.4, 0), white)
			var dome := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 4.0
			sm.height = 4.0
			sm.is_hemisphere = true
			sm.material = white
			dome.mesh = sm
			dome.position.y = 2.4
			g.add_child(dome)
			_cyl(g, 0.08, 0.08, 4.0, Vector3(1.5, 6.0, 0), dark)
			spin = _box(g, Vector3(1.6, 0.1, 0.5), Vector3(1.5, 8.0, 0), white)
			_box(g, Vector3(1.6, 2.2, 0.3), Vector3(0, 1.5, 4.2), dark)
			_glow_box(g, Vector3(4.0, 0.25, 0.1), Vector3(0, 2.0, 4.3), Color(0.5, 1.6, 2.4))
		"habitat":
			var hab := _cyl(g, 2.0, 2.0, 7.5, Vector3(0, 2.3, 0), white)
			hab.rotation.z = PI / 2.0
			for x in [-2.4, 0.0, 2.4]:
				_glow_box(g, Vector3(0.9, 0.5, 0.05), Vector3(x, 2.6, 2.0), Color(2.2, 1.8, 1.0))
		"storage":
			_box(g, Vector3(7, 3.4, 5.5), Vector3(0, 1.9, 0), ShipBuilder.metal(Color("#b0875a"), 0.4, 0.6))
			for x in [-2.5, -0.8, 0.8, 2.5]:
				_box(g, Vector3(0.15, 3.5, 5.6), Vector3(x, 1.9, 0), dark)
		"workshop":
			_box(g, Vector3(7, 3.6, 6), Vector3(0, 2.0, 0), ShipBuilder.metal(Color("#c8a040"), 0.5, 0.5))
			_box(g, Vector3(3, 2.6, 0.2), Vector3(0, 1.5, 3.05), dark)
			_glow_box(g, Vector3(2.6, 0.2, 0.05), Vector3(0, 3.0, 3.1), Color(3.0, 1.4, 0.3))
			_cyl(g, 0.35, 0.35, 2.5, Vector3(2.4, 4.8, -1.5), dark)
		"solar":
			for i in 6:
				var x := -3.0 + (i % 3) * 3.0
				var z := -1.8 + (i / 3) * 3.6
				_cyl(g, 0.1, 0.1, 1.6, Vector3(x, 0.9, z), dark)
				var p := _box(g, Vector3(2.7, 0.08, 3.2), Vector3(x, 1.8, z), ShipBuilder.metal(Color("#1a3a7a"), 0.8, 0.15))
				p.rotation.x = -0.5
		"reactor":
			_cyl(g, 2.6, 3.4, 6.0, Vector3(0, 3.2, 0), white)
			_glow_box(g, Vector3(5.5, 0.35, 5.5), Vector3(0, 4.6, 0), Color(0.6, 2.6, 0.8))
			_cyl(g, 0.6, 0.6, 3.0, Vector3(3.2, 1.7, 2.0), dark)
		"drill":
			for lp in [Vector2(-1.6, -1.6), Vector2(1.6, -1.6), Vector2(-1.6, 1.6), Vector2(1.6, 1.6)]:
				var leg := _box(g, Vector3(0.25, 7.5, 0.25), Vector3(lp.x * 0.7, 3.8, lp.y * 0.7), ShipBuilder.metal(Color("#d07a30"), 0.6, 0.4))
				leg.rotation = Vector3(lp.y * 0.08, 0, -lp.x * 0.08)
			_box(g, Vector3(2.4, 0.6, 2.4), Vector3(0, 7.4, 0), dark)
			spin = _cyl(g, 0.45, 0.1, 6.0, Vector3(0, 3.2, 0), grey)
		"refinery":
			_cyl(g, 1.6, 1.6, 5.0, Vector3(-1.9, 2.7, 0), white)
			_cyl(g, 1.3, 1.3, 4.0, Vector3(1.9, 2.2, -0.5), white)
			var pipe := _cyl(g, 0.25, 0.25, 3.6, Vector3(0, 3.6, 0), dark)
			pipe.rotation.z = PI / 2.0
			_glow_box(g, Vector3(0.6, 0.6, 0.1), Vector3(-1.9, 2.0, 1.62), Color(3.0, 1.2, 0.3))
		"turret":
			_cyl(g, 1.4, 1.8, 1.8, Vector3(0, 1.1, 0), grey)
			spin = Node3D.new()
			spin.position.y = 2.4
			g.add_child(spin)
			_box(spin, Vector3(1.8, 1.0, 1.8), Vector3.ZERO, dark)
			_box(spin, Vector3(0.25, 0.25, 2.8), Vector3(0.35, 0.1, -1.8), grey)
			_box(spin, Vector3(0.25, 0.25, 2.8), Vector3(-0.35, 0.1, -1.8), grey)
	var light := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.3
	lm.height = 0.6
	light.mesh = lm
	light.position = Vector3(3.6, 0.9, 3.6)
	g.add_child(light)
	var tag := Label3D.new()
	tag.font_size = 44
	tag.pixel_size = 0.011
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 8
	tag.position.y = 8.5 if m.id in ["drill", "core"] else 6.5
	g.add_child(tag)
	_models[int(m.uid)] = {"node": g, "light": light, "tag": tag, "spin": spin}
	_refresh_model(m)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _glow_box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	return _box(parent, size, pos, ShipBuilder.unshaded(col))


func _cyl(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _refresh_model(m: Dictionary) -> void:
	var v: Dictionary = _models.get(int(m.uid), {})
	if v.is_empty():
		return
	var ratio: float = BaseData.energy(base).ratio
	var col := Color(0.4, 2.6, 0.6)
	if m.broken:
		col = Color(3.0, 0.3, 0.2)
	elif int(BaseData.MODULES[m.id].energy) < 0 and ratio < 1.0 or BaseData.cond(m) < 30.0:
		col = Color(3.0, 2.0, 0.2)
	(v.light as MeshInstance3D).material_override = ShipBuilder.unshaded(col)
	(v.tag as Label3D).text = "%s\n%s" % [BaseData.MODULES[m.id].name, BaseData.status_text(m)]
	(v.tag as Label3D).modulate = Color("#ff8a6a") if m.broken else Color("#e8f0ff")


# ---------- Каждый кадр ----------

func _process(delta: float) -> void:
	if surface == null or surface.leaving:
		return
	var now: Dictionary = GameState.bases.get(key(), {})
	if now.is_empty() != base.is_empty() or (not now.is_empty() and now.modules.size() != _models.size()):
		rebuild()  # доставили модуль или налёт уничтожил
	if base.is_empty():
		return
	_t += delta
	for i in range(_beams.size() - 1, -1, -1):
		_beams[i].life -= delta
		if _beams[i].life <= 0.0:
			_beams[i].node.queue_free()
			_beams.remove_at(i)
	var ratio: float = BaseData.energy(base).ratio
	for m in base.modules:
		var v: Dictionary = _models.get(int(m.uid), {})
		if v.is_empty() or v.spin == null or m.broken:
			continue
		if m.id == "drill" or m.id == "core":
			(v.spin as Node3D).rotation.y += delta * 3.0 * ratio
	_label_t -= delta
	if _label_t <= 0.0:
		_label_t = 1.0
		for m in base.modules:
			_refresh_model(m)
	_sync_masters()
	for n in npcs.duplicate():
		_update_npc(n, delta)
	_turrets(delta)


## Мастера на базе, пока длится их визит.
func _sync_masters() -> void:
	var masters := npcs.filter(func(n): return n.kind == "master")
	if base.visit.is_empty():
		for n in masters:
			n.node.queue_free()
			npcs.erase(n)
		return
	if masters.is_empty() and _spawned_visit != float(base.visit.until):
		_spawned_visit = float(base.visit.until)
		var m := BaseData.find(base, int(base.visit.uid))
		var at := _module_pos(m) if not m.is_empty() else center()
		for i in 2:
			_spawn("master", "Мастер «%s»" % base.visit.faction, at + Vector3(-4.0 + i * 8.0, 0, 5.5), 120.0, base.visit.hostile)


func _spawn(kind: String, title: String, at: Vector3, hp: float, hostile: bool) -> Dictionary:
	var role := "мастер" if kind == "master" else "солдат"
	var node: Node3D = surface.squad._make_body({"name": title, "role": role, "gear": {"weapon": {}}})
	node.position = Vector3(at.x, surface.ground(at.x, at.z), at.z)
	add_child(node)
	var bar := HealthBar.make(hp, Color("#ffb040") if kind == "master" else Color("#ff4a3a"))
	bar.position.y = 2.15
	node.add_child(bar)
	var n := {"node": node, "kind": kind, "hp": hp, "max": hp, "bar": bar, "hostile": hostile, "cd": randf_range(0.5, 1.5), "phase": 0.0, "home": node.position}
	npcs.append(n)
	return n


func _update_npc(n: Dictionary, delta: float) -> void:
	var node: Node3D = n.node
	n.cd = float(n.cd) - delta
	var dest: Vector3 = n.home
	var aim := {}
	if n.hostile:
		aim = _pick_victim(node.position, n.kind == "soldier")
		if not aim.is_empty():
			dest = aim.pos
	var to := Vector3(dest.x - node.position.x, 0, dest.z - node.position.z)
	var stop := SHOT_RANGE * 0.6 if n.hostile else 1.0
	if to.length() > stop:
		var step: Vector3 = to.normalized() * min(to.length(), NPC_SPEED * delta)
		node.position.x += step.x
		node.position.z += step.z
		n.phase = float(n.phase) + delta * 9.0
	else:
		n.phase = float(n.phase) + (delta * 2.0 if not n.hostile else 0.0)  # мастер за работой
	node.position.y = surface.ground(node.position.x, node.position.z)
	var face := (aim.pos as Vector3) if not aim.is_empty() else (dest if to.length() > 0.5 else center())
	var f := face - node.position
	if Vector2(f.x, f.z).length() > 0.1:
		node.rotation.y = lerp_angle(node.rotation.y, atan2(-f.x, -f.z), min(1.0, delta * 6.0))
	node.get_node("Leg0").rotation.x = sin(n.phase) * 0.5
	node.get_node("Leg1").rotation.x = -sin(n.phase) * 0.5
	if n.hostile and not aim.is_empty() and n.cd <= 0.0 and node.position.distance_to(aim.pos) < SHOT_RANGE:
		n.cd = 1.3 if n.kind == "soldier" else 1.0
		var from: Vector3 = node.position + Vector3(0, 1.2, 0)
		var hit := randf() < 0.6
		var end: Vector3 = (aim.pos as Vector3) + Vector3(0, 1.0, 0)
		if not hit:
			end += Vector3(randf_range(-2, 2), randf_range(0, 1.5), randf_range(-2, 2))
		_beam(from, end, Color(3.0, 0.4, 0.3))
		if hit:
			match aim.type:
				"player":
					surface._hurt(9.0)
				"crew":
					surface.squad.hurt(aim.m, 9.0)
				"module":
					_hit_module(aim.m)


## Кого атакует враг: капитана, экипаж или (солдаты) модули базы.
func _pick_victim(at: Vector3, modules_too: bool) -> Dictionary:
	var best := {}
	var bd := 1.0e9
	if not surface.inside:
		var d: float = at.distance_to(surface.player.position)
		if d < bd:
			bd = d
			best = {"type": "player", "pos": surface.player.position}
	var m: Dictionary = surface.squad.nearest(at)
	if not m.is_empty():
		var d: float = at.distance_to(m.node.position)
		if d < bd:
			bd = d
			best = {"type": "crew", "pos": m.node.position, "m": m}
	if modules_too:
		for mod in base.modules:
			var p := _module_pos(mod)
			# Солдаты идут ломать базу, если капитан далеко.
			var d := at.distance_to(p) * 0.7
			if d < bd:
				bd = d
				best = {"type": "module", "pos": p, "m": mod}
	return best


func _hit_module(m: Dictionary) -> void:
	m.worn = float(m.worn) + float(m.life) * 0.04
	if float(m.worn) >= float(m.life):
		if m.broken:
			m["wreck"] = int(m.get("wreck", 0)) + 1
			if int(m.wreck) >= 5:
				base.modules.erase(m)
				surface._notify("Солдаты уничтожили модуль «%s»!" % BaseData.MODULES[m.id].name, Color("#ff4a3a"))
				if base.modules.is_empty():
					GameState.bases.erase(key())
					GameState.say("Армия уничтожила вашу базу на %s!" % base.planet.name, Color("#ff4a3a"))
		else:
			m.broken = true
			surface._notify("Солдаты вывели из строя «%s»!" % BaseData.MODULES[m.id].name, Color("#ff6a4a"))


## Турели стреляют по враждебным, пока им хватает энергии.
func _turrets(delta: float) -> void:
	var ratio: float = BaseData.energy(base).ratio
	for m in base.modules:
		if m.id != "turret" or m.broken or ratio < 0.3:
			continue
		var v: Dictionary = _models.get(int(m.uid), {})
		if v.is_empty():
			continue
		var p := _module_pos(m) + Vector3(0, 2.6, 0)
		var foe := hostile_near(p, TURRET_RANGE)
		if foe.is_empty():
			continue
		var head: Node3D = v.spin
		var f: Vector3 = foe.node.position - p
		head.rotation.y = lerp_angle(head.rotation.y, atan2(-f.x, -f.z), min(1.0, delta * 5.0))
		_turret_cd[m.uid] = float(_turret_cd.get(m.uid, 0.0)) - delta
		if float(_turret_cd[m.uid]) <= 0.0:
			_turret_cd[m.uid] = 1.0
			_beam(p, foe.node.position + Vector3(0, 1.0, 0), Color(0.6, 2.4, 3.6))
			damage(foe, 14.0 * ratio, false)


func _beam(from: Vector3, end: Vector3, col: Color) -> void:
	var b := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.02
	cm.height = max(0.05, from.distance_to(end))
	cm.material = ShipBuilder.unshaded(col)
	b.mesh = cm
	add_child(b)
	b.position = (from + end) / 2.0
	if from.distance_to(end) > 0.01:
		b.look_at(end, Vector3.UP if abs((end - from).normalized().y) < 0.99 else Vector3.RIGHT)
		b.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	_beams.append({"node": b, "life": 0.1})


# ---------- Стрельба по NPC и последствия ----------

## Кто из NPC под прицелом капитана (ближе max_d).
func pick(from: Vector3, dir: Vector3, max_d: float, cone: float) -> Dictionary:
	var best := {}
	var bd := max_d
	for n in npcs:
		var c: Vector3 = n.node.position + Vector3(0, 1.1, 0)
		var to := c - from
		var d := to.length()
		if d < bd and to.normalized().dot(dir) > cone:
			bd = d
			best = {"t": n, "d": d}
	return best


func hostile_near(at: Vector3, radius: float) -> Dictionary:
	var best := {}
	var bd := radius
	for n in npcs:
		if not n.hostile:
			continue
		var d: float = at.distance_to(n.node.position)
		if d < bd:
			bd = d
			best = n
	return best


## by_player: стрелял капитан или его экипаж (тогда нападение на мастеров — война).
func damage(n: Dictionary, dmg: float, by_player: bool = true) -> void:
	if not npcs.has(n):
		return
	n.hp = float(n.hp) - dmg
	HealthBar.set_value(n.bar, n.hp, n.max)
	if n.kind == "master" and by_player and not n.hostile:
		# Напали на мастеров: они отбиваются, их планета объявляет войну.
		for o in npcs:
			if o.kind == "master":
				o.hostile = true
		base.visit.hostile = true
		GameState.declare_war(base.visit.from, base.visit.faction)
		surface._notify("Мастера отбиваются! «%s» объявляет вам войну." % base.visit.faction, Color("#ff4a3a"))
	if n.hp > 0.0:
		return
	n.node.queue_free()
	npcs.erase(n)
	if n.kind == "master":
		var pid := BaseData.part_id(base.visit.get("id", "core"))
		GameState.add_item(pid, int(base.visit.get("parts", 2)) / 2 + 1)
		surface._notify("Мастер повержен. Вы забрали его запчасти: %s." % BaseData.part_name(pid), Color("#ffbf55"))
		if npcs.filter(func(o): return o.kind == "master").is_empty():
			base.visit = {}
	else:
		GameState.stats["soldiers"] = int(GameState.stats.get("soldiers", 0)) + 1
		_raid.left = int(_raid.get("left", 1)) - 1
		if int(_raid.left) <= 0:
			GameState.say("Налёт армии «%s» отбит!" % _raid.faction, Color("#9aff6a"))
			GameState.hero_xp("leadership", 2)
			_raid = {}


func _on_raid(bkey: String, faction: String, strength: int) -> void:
	if bkey != key() or base.is_empty():
		return
	_raid = {"faction": faction, "left": strength}
	var c := center()
	var a := randf() * TAU
	for i in strength:
		var p := c + Vector3(cos(a + i * 0.25), 0, sin(a + i * 0.25)) * 60.0
		p.x = clamp(p.x, -surface.SIZE / 2.0 + 8, surface.SIZE / 2.0 - 8)
		p.z = clamp(p.z, -surface.SIZE / 2.0 + 8, surface.SIZE / 2.0 - 8)
		_spawn("soldier", "Солдат «%s»" % faction, p, 70.0, true)


## Капитан взлетает посреди налёта: оставшиеся солдаты доделывают своё без него.
func on_leave() -> void:
	if not _raid.is_empty() and not base.is_empty():
		GameState.resolve_raid(base, _raid.faction, int(_raid.left))


func near_core() -> bool:
	return not base.is_empty() and not surface.inside and surface.player.position.distance_to(center()) < 8.0
