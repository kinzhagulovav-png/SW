class_name CrewSquad
extends Node3D
## Члены экипажа на высадке: ходят с капитаном и выполняют его команды.
## Кто высаживается, выбирают в окне «Персонажи» (C) на корабле или в системе.
## Команды (Tab выбирает, кому: всем или одному):
##   G — за мной, T — ждать здесь, V — копать там, куда смотрит капитан,
##   B — атаковать зверя в прицеле (или ближайшего), X — вернуться к кораблю.
## Работают их навыки и снаряжение: бластер и Точность, лапатрон, рюкзак и Геология, броня.
## Раненый до нуля падает без сознания: капитан поднимает его аптечкой (E рядом).
## Если взлететь без него, он остаётся на планете навсегда.

const ORDERS := {"follow": "за мной", "wait": "ждёт", "dig": "копает", "attack": "атакует", "ship": "у корабля"}
const ROLE_COLORS := {"учёный": Color("#f0f2f4"), "второй пилот": Color("#3a6fd0"), "боец": Color("#b84a3a"), "механик": Color("#e0a030"),
	"мастер": Color("#e07a20"), "солдат": Color("#5a1a1a")}
const SPEED := 6.5
const SHOOT_RANGE := 22.0

var surface: Node3D
var members: Array[Dictionary] = []
var selected := -1  # -1 — все
var _panel: Label
var _beams: Array[Dictionary] = []


func setup(s: Node3D) -> void:
	surface = s
	var i := 0
	for c in GameState.crew:
		if not c.get("lands", true):
			continue
		var m := {"p": c, "hp": People.max_hp(c), "max": People.max_hp(c), "order": "follow", "spot": Vector3.ZERO, "target": {}, "cd": 0.0,
			"load": {"minerals": {}, "samples": []}, "down": false, "phase": 0.0, "slot": i, "endure": 0.0, "back_to": ""}
		m["node"] = _make_body(c)
		m["bar"] = HealthBar.make(m.max, Color("#7fe0ff"))
		m.bar.position.y = 2.15
		m.node.add_child(m.bar)
		var pp: Vector3 = surface.player.position
		var pos := pp + Vector3(-2.0 - i * 1.5, 0, 2.0 + i)
		m.node.position = Vector3(pos.x, surface.ground(pos.x, pos.z), pos.z)
		add_child(m.node)
		members.append(m)
		i += 1
	_build_panel()
	if not members.is_empty():
		var names := PackedStringArray()
		for m in members:
			names.append(m.p.name)
		surface._notify("С вами высадились: %s" % ", ".join(names), Color("#9ad8ff"))


# ---------- Модель ----------

func _make_body(c: Dictionary) -> Node3D:
	var g := Node3D.new()
	var col: Color = ROLE_COLORS.get(c.role, Color("#9aa4b4"))
	var suit_mat := ShipBuilder.metal(col, 0.2, 0.55)
	var dark := ShipBuilder.metal(Color("#2a3040"), 0.4, 0.5)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.26
	cm.height = 1.15
	cm.material = suit_mat
	body.mesh = cm
	body.position.y = 1.05
	body.name = "Body"
	g.add_child(body)
	for s in [-0.13, 0.13]:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.09
		lm.bottom_radius = 0.08
		lm.height = 0.62
		lm.material = dark
		leg.mesh = lm
		leg.position = Vector3(s, 0.31, 0)
		leg.name = "Leg%d" % (0 if s < 0 else 1)
		g.add_child(leg)
	# Шлем скафандра со светящимся визором.
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.2
	hm.height = 0.4
	hm.material = ShipBuilder.metal(Color("#dfe4ec"), 0.5, 0.25)
	head.mesh = hm
	head.position.y = 1.82
	g.add_child(head)
	var visor := MeshInstance3D.new()
	var vm := SphereMesh.new()
	vm.radius = 0.13
	vm.height = 0.18
	vm.material = ShipBuilder.unshaded(Color(0.5, 1.6, 2.4))
	visor.mesh = vm
	visor.position = Vector3(0, 0.0, -0.12)
	head.add_child(visor)
	var pack := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.4, 0.5, 0.2)
	pm.material = dark
	pack.mesh = pm
	pack.position = Vector3(0, 1.15, 0.3)
	g.add_child(pack)
	# В руке то, что есть в снаряжении: бластер или лапатрон.
	var held := MeshInstance3D.new()
	var tm := BoxMesh.new()
	var gear: Dictionary = c.get("gear", {})
	tm.size = Vector3(0.08, 0.1, 0.5) if gear.has("weapon") else Vector3(0.05, 0.05, 0.7)
	tm.material = ShipBuilder.metal(Color("#3a4250") if gear.has("weapon") else Color("#c08030"), 0.7, 0.35)
	held.mesh = tm
	held.position = Vector3(0.3, 1.05, -0.25)
	held.visible = gear.has("weapon") or gear.has("lapatron")
	g.add_child(held)
	var tag := Label3D.new()
	tag.text = "%s\n%s" % [c.name, c.role]
	tag.font_size = 32
	tag.pixel_size = 0.0035
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = col.lightened(0.3)
	tag.outline_size = 8
	tag.position.y = 2.5
	tag.name = "Tag"
	g.add_child(tag)
	return g


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = Label.new()
	_panel.position = Vector2(-520, 300)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.add_theme_font_size_override("font_size", 17)
	_panel.add_theme_color_override("font_color", Color("#cfe6ff"))
	_panel.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_panel.add_theme_constant_override("outline_size", 5)
	_panel.visible = not members.is_empty()
	layer.add_child(_panel)


# ---------- Команды ----------

func command(key: int) -> void:
	if members.is_empty():
		surface._notify("Экипаж не высадился. Кто идёт на высадку, выбирают в окне «Персонажи» (C).", Color("#ff8a6a"))
		return
	if key == KEY_TAB:
		selected += 1
		if selected >= members.size():
			selected = -1
		_update_panel()
		surface._notify("Команды получает: %s" % ("весь экипаж" if selected < 0 else members[selected].p.name), Color("#9ad8ff"))
		return
	var who: Array = members if selected < 0 else [members[selected]]
	var order := ""
	var spot := Vector3.ZERO
	var target := {}
	match key:
		KEY_G:
			order = "follow"
		KEY_T:
			order = "wait"
		KEY_X:
			order = "ship"
		KEY_V:
			var hit = surface._aim_ground()
			if hit == null:
				# Не достаёт до земли: копать прямо перед капитаном.
				var f: Vector3 = surface.player.position - surface.player.transform.basis.z * 5.0
				hit = Vector3(f.x, surface.ground(f.x, f.z), f.z)
			order = "dig"
			spot = hit
		KEY_B:
			target = surface._beast_in_sight()
			if target.is_empty():
				target = _nearest_beast(surface.player.position, 40.0)
			if target.is_empty():
				surface._notify("Рядом нет зверей для атаки.", Color("#ff8a6a"))
				return
			order = "attack"
	var names := PackedStringArray()
	for m in who:
		if m.down:
			continue
		if order == "dig" and not m.p.gear.has("lapatron"):
			surface._notify("%s: у меня нет лапатрона. Купите его на станции (Снаряжение)." % m.p.name, Color("#ff8a6a"))
			continue
		if order == "attack" and not m.p.gear.has("weapon"):
			surface._notify("%s: у меня нет бластера." % m.p.name, Color("#ff8a6a"))
			continue
		m.order = order
		m.target = target
		m.back_to = ""
		# Копают рядом друг с другом, а не в одной яме.
		m.spot = spot + Vector3(m.slot * 2.2 - 1.0, 0, 0) if order == "dig" else (m.node.position if order == "wait" else spot)
		names.append(m.p.name)
	if not names.is_empty():
		surface._notify("%s: %s" % [", ".join(names), {"follow": "иду за вами", "wait": "жду здесь", "dig": "копаю там", "attack": "атакую!", "ship": "возвращаюсь к кораблю"}[order]], Color("#9ad8ff"))


# ---------- Каждый кадр ----------

func _process(delta: float) -> void:
	if surface == null or surface.leaving:
		return
	for i in range(_beams.size() - 1, -1, -1):
		_beams[i].life -= delta
		if _beams[i].life <= 0.0:
			_beams[i].node.queue_free()
			_beams.remove_at(i)
	for m in members:
		_update(m, delta)
	_update_panel()


func _update(m: Dictionary, delta: float) -> void:
	var n: Node3D = m.node
	if m.down:
		n.rotation.x = lerp(n.rotation.x, -PI / 2.0, min(1.0, delta * 4.0))
		n.position.y = surface.ground(n.position.x, n.position.z) + 0.25
		return
	n.rotation.x = 0.0
	m.cd = max(0.0, m.cd - delta)
	_environment(m, delta)
	var dest := n.position
	var near := 0.6
	match m.order:
		"follow":
			if surface.inside:
				dest = _ship_spot(m)
			else:
				# Строй позади капитана.
				var yaw: float = surface.yaw
				var back := Vector3(sin(yaw), 0, cos(yaw))
				var side := Vector3(cos(yaw), 0, -sin(yaw))
				dest = surface.player.position + back * (2.5 + m.slot * 1.2) + side * (1.6 if m.slot % 2 == 0 else -1.6)
				near = 1.5
		"wait":
			dest = m.spot
		"ship":
			dest = _ship_spot(m)
		"dig":
			dest = m.spot
			near = 2.2
		"attack":
			if m.target.is_empty() or not (surface.beasts.has(m.target) or surface.base_view.npcs.has(m.target)):
				m.order = "follow"
				m.target = {}
				return
			dest = m.target.node.position
			near = SHOOT_RANGE * 0.7
	# Самозащита: с бластером стреляет в разозлённых зверей поблизости.
	var foe: Dictionary = m.target if m.order == "attack" else _angry_near(n.position)
	if not foe.is_empty() and m.p.gear.has("weapon") and n.position.distance_to(foe.node.position) < SHOOT_RANGE:
		_face(n, foe.node.position, delta)
		if m.cd <= 0.0:
			_shoot(m, foe)
	var moving := _walk(m, dest, near, delta)
	if m.order == "dig" and not moving:
		_dig(m)
	if m.order == "ship" or (m.order == "follow" and surface.inside):
		if n.position.distance_to(surface.ship.position) < surface.TAKEOFF_DIST:
			_unload(m)
	# Рюкзак полон: относит добычу на корабль и возвращается копать.
	if m.order == "ship" and m.back_to == "dig" and _load_size(m) == 0:
		m.order = "dig"
		m.back_to = ""


func _walk(m: Dictionary, dest: Vector3, near: float, delta: float) -> bool:
	var n: Node3D = m.node
	var to := Vector3(dest.x - n.position.x, 0, dest.z - n.position.z)
	var moving := to.length() > near
	if moving:
		var sp := SPEED * People.boots_mult(m.p.gear.get("boots", {})) * (1.6 if to.length() > 14.0 else 1.0)
		var step: Vector3 = to.normalized() * min(to.length(), sp * delta)
		var nx: float = clamp(n.position.x + step.x, -surface.SIZE / 2.0 + 5, surface.SIZE / 2.0 - 5)
		var nz: float = clamp(n.position.z + step.z, -surface.SIZE / 2.0 + 5, surface.SIZE / 2.0 - 5)
		# В жидкость и лаву не заходят.
		if surface.water.is_empty() or surface.water.get("ice", false) or surface.ground(nx, nz) > surface.level + 0.2:
			n.position.x = nx
			n.position.z = nz
		_face(n, dest, delta)
		m.phase += delta * 9.0
	else:
		m.phase = lerp(float(m.phase), 0.0, min(1.0, delta * 6.0))
	n.position.y = surface.ground(n.position.x, n.position.z)
	n.get_node("Leg0").rotation.x = sin(m.phase) * 0.5
	n.get_node("Leg1").rotation.x = -sin(m.phase) * 0.5
	n.get_node("Body").position.y = 1.05 + abs(sin(m.phase)) * 0.04
	return moving


func _face(n: Node3D, at: Vector3, delta: float) -> void:
	var to := at - n.position
	if Vector2(to.x, to.z).length() > 0.1:
		n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), min(1.0, delta * 8.0))


func _ship_spot(m: Dictionary) -> Vector3:
	var a := float(m.slot) * 0.9 + 0.6
	var sp: Vector3 = surface.ship.position
	return Vector3(sp.x + cos(a) * 6.0, 0, sp.z + sin(a) * 6.0)


## Радиация и опыт Выносливости. Без скафандра излучение бьёт по здоровью.
func _environment(m: Dictionary, delta: float) -> void:
	m.endure += delta
	if m.endure >= 25.0:
		m.endure = 0.0
		GameState.add_xp(m.p, "endurance", 1)
	if not m.p.gear.has("suit"):
		_damage(m, float(surface.profile.rad) * 0.3 * delta)


func _shoot(m: Dictionary, b: Dictionary) -> void:
	var w: Dictionary = m.p.gear.weapon
	m.cd = People.weapon_cooldown(w) * 1.6
	var acc := People.level(m.p, "accuracy")
	var from: Vector3 = m.node.position + Vector3(0, 1.2, 0)
	var to: Vector3 = b.node.position + Vector3(0, float(b.sp.size) if b.has("sp") else 1.1, 0)
	var hit: bool = surface.rng.randf() < 0.55 + 0.04 * acc
	if not hit:
		to += Vector3(surface.rng.randf_range(-2, 2), surface.rng.randf_range(0, 1.5), surface.rng.randf_range(-2, 2))
	_beam(from, to, Color(2.8, 0.9, 0.6))
	if hit:
		GameState.add_xp(m.p, "accuracy", 1)
		if not b.has("sp"):
			surface.base_view.damage(b, People.weapon_damage(w) * (1.0 + 0.08 * acc))
		elif surface.damage_beast(b, People.weapon_damage(w) * (1.0 + 0.08 * acc)):
			GameState.add_xp(m.p, "accuracy", 3)
			surface._notify("%s: зверь повержен!" % m.p.name, Color("#9ad8ff"))


func _beam(from: Vector3, end: Vector3, col: Color) -> void:
	var b := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.015
	cm.bottom_radius = 0.015
	cm.height = max(0.05, from.distance_to(end))
	cm.material = ShipBuilder.unshaded(col)
	b.mesh = cm
	add_child(b)
	b.position = (from + end) / 2.0
	if from.distance_to(end) > 0.01:
		b.look_at(end, Vector3.UP if abs((end - from).normalized().y) < 0.99 else Vector3.RIGHT)
		b.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	_beams.append({"node": b, "life": 0.1})


func _dig(m: Dictionary) -> void:
	if m.cd > 0.0:
		return
	var l: Dictionary = m.p.gear.get("lapatron", {})
	if l.is_empty():
		m.order = "follow"
		return
	m.cd = 0.9 if int(l.mk) < 2 else 0.6
	var p: Vector3 = m.spot
	p.y = surface.ground(p.x, p.z)
	_face(m.node, p, 1.0)
	_beam(m.node.position + Vector3(0, 1.0, 0), p, Color(3.2, 1.6, 0.4))
	if not surface._dig(p, People.lapatron_strength(l), People.lapatron_depth(l)):
		m.order = "wait"
		m.spot = m.node.position
		surface._notify("%s: глубже мой лапатрон не берёт." % m.p.name, Color("#ffbf55"))
		return
	var loot: Dictionary = surface.roll_loot(p, People.level(m.p, "geology"))
	var room := People.backpack_size(m.p.gear.get("backpack", {})) - _load_size(m)
	if loot.has("mineral") and room > 0:
		var k := mini(int(loot.n), room)
		m.load.minerals[loot.mineral] = int(m.load.minerals.get(loot.mineral, 0)) + k
		GameState.add_xp(m.p, "geology", 1)
		var mn: Dictionary = Items.MINERALS[loot.mineral]
		surface._notify("%s: +%d %s" % [m.p.name, k, mn.name], mn.color.lightened(0.3))
		room -= k
	if loot.has("sample") and room >= Items.SAMPLE_VOLUME:
		m.load.samples.append(Items.make_sample(surface.rng, surface.planet.biome, surface.planet.name, float(loot.sample)))
		GameState.add_xp(m.p, "geology", 2)
		surface._notify("%s нашёл неизвестный образец!" % m.p.name, Color("#9aff6a"))
	if People.backpack_size(m.p.gear.get("backpack", {})) - _load_size(m) <= 0:
		surface._notify("%s: рюкзак полон, несу добычу на корабль." % m.p.name, Color("#ffbf55"))
		m.order = "ship"
		m.back_to = "dig"


func _load_size(m: Dictionary) -> int:
	var used := 0
	for k in m.load.minerals:
		used += int(m.load.minerals[k])
	return used + m.load.samples.size() * Items.SAMPLE_VOLUME


## Добыча члена экипажа переходит в общую добычу высадки (она попадёт в трюм).
func _unload(m: Dictionary) -> void:
	if _load_size(m) == 0:
		return
	var trip: Dictionary = surface.trip
	var count := 0
	for k in m.load.minerals:
		trip.minerals[k] = int(trip.minerals.get(k, 0)) + int(m.load.minerals[k])
		count += int(m.load.minerals[k])
	for s in m.load.samples:
		trip.samples.append(s)
	surface._notify("%s сдал на корабль: минералов %d, образцов %d" % [m.p.name, count, m.load.samples.size()], Color("#ffbf55"))
	m.load = {"minerals": {}, "samples": []}


# ---------- Звери и урон ----------

func _nearest_beast(at: Vector3, radius: float) -> Dictionary:
	var best := {}
	var bd := radius
	for b in surface.beasts:
		var d: float = at.distance_to(b.node.position)
		if d < bd:
			bd = d
			best = b
	return best


func _angry_near(at: Vector3) -> Dictionary:
	# Сначала враги базы: солдаты и разозлённые мастера.
	var foe: Dictionary = surface.base_view.hostile_near(at, SHOOT_RANGE)
	if not foe.is_empty():
		return foe
	var best := {}
	var bd := SHOOT_RANGE
	for b in surface.beasts:
		if not b.angry:
			continue
		var d: float = at.distance_to(b.node.position)
		if d < bd:
			bd = d
			best = b
	return best


## Ближайший к точке член экипажа на ногах (для зверей).
func nearest(at: Vector3) -> Dictionary:
	var best := {}
	var bd := 1.0e9
	for m in members:
		if m.down:
			continue
		var d: float = at.distance_to(m.node.position)
		if d < bd:
			bd = d
			best = m
	return best


func hurt(m: Dictionary, amount: float) -> void:
	_damage(m, amount * (1.0 - People.armor_cut(m.p.gear.get("armor", {}))))


func _damage(m: Dictionary, amount: float) -> void:
	if m.down:
		return
	m.hp = max(0.0, float(m.hp) - amount)
	HealthBar.set_value(m.bar, m.hp, m.max)
	if m.hp <= 0.0:
		m.down = true
		m.order = "wait"
		surface._notify("%s без сознания! Подойдите и нажмите E: нужна аптечка из трюма." % m.p.name, Color("#ff6a4a"))


func _downed_near() -> Dictionary:
	for m in members:
		if m.down and m.node.position.distance_to(surface.player.position) < 3.0:
			return m
	return {}


func revive_hint() -> String:
	var m := _downed_near()
	if m.is_empty() or surface.inside:
		return ""
	return "E: поднять %s аптечкой (в трюме: %d)" % [m.p.name, GameState.count("medkit")]


func try_revive() -> bool:
	var m := _downed_near()
	if m.is_empty():
		return false
	if GameState.count("medkit") <= 0:
		surface._notify("Аптечек нет. Их делают на научной станции.", Color("#ff8a6a"))
		return true
	GameState.add_item("medkit", -1)
	m.down = false
	m.hp = float(m.max) * 0.4
	HealthBar.set_value(m.bar, m.hp, m.max)
	m.order = "follow"
	surface._notify("%s снова на ногах." % m.p.name, Color("#76e8a0"))
	return true


## Взлёт: все, кто на ногах, поднимаются на борт с добычей. Оставшиеся без сознания пропадают.
func board_all() -> void:
	for m in members:
		if m.down:
			GameState.crew.erase(m.p)
			GameState.stats["lost"] = int(GameState.stats.get("lost", 0)) + 1
		else:
			_unload(m)


## Имена тех, кто без сознания (останутся на планете при взлёте).
func left_behind() -> String:
	var names := PackedStringArray()
	for m in members:
		if m.down:
			names.append(m.p.name)
	return ", ".join(names)


func _update_panel() -> void:
	if members.is_empty():
		return
	var lines := PackedStringArray(["Экипаж · кому: %s  [Tab]" % ("всем" if selected < 0 else members[selected].p.name)])
	for i in members.size():
		var m: Dictionary = members[i]
		var state: String = "БЕЗ СОЗНАНИЯ" if m.down else ORDERS[m.order]
		var bag := _load_size(m)
		lines.append("%s %s · ♥%d/%d · %s%s" % ["▶" if selected == i or selected < 0 else "  ", m.p.name, ceili(m.hp), int(m.max), state,
			" · рюкзак %d" % bag if bag > 0 else ""])
	lines.append("G за мной · T ждать · V копать · B атака · X к кораблю")
	_panel.text = "\n".join(lines)
