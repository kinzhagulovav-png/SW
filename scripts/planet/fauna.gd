class_name Fauna
extends RefCounted
## Существа планет. Каждая планета по своему сиду получает 1–4 вида.
## Вид зависит от биома (какие формы тел там живут), фона радиации (мутанты светятся,
## злее и крепче) и опасности биома. Формы тел:
##   quad — четвероногий зверь, biped — длинноногий на двух ногах, crawler — шестиногий ползун,
##   hopper — прыгающий шар, flyer — летун с крыльями, floater — ядовитая парящая медуза,
##   rockback — медленный панцирник.
## Нрав: passive (убегает), neutral (нападает, только если ранить), aggressive (охотится).

const PLANS_BY_BIOME := {
	"desert": ["crawler", "hopper", "rockback", "biped"],
	"ice": ["biped", "hopper", "crawler", "quad"],
	"jungle": ["quad", "biped", "flyer", "hopper", "crawler"],
	"volcano": ["rockback", "crawler", "flyer"],
	"toxic": ["floater", "crawler", "hopper", "flyer"],
}
const PLAN_STATS := {
	# скорость шага, скорость атаки, урон в секунду, здоровье, размер
	"quad": {"walk": 2.0, "run": 6.5, "dmg": 12.0, "hp": 3, "size": 1.0},
	"biped": {"walk": 2.4, "run": 7.5, "dmg": 10.0, "hp": 3, "size": 1.2},
	"crawler": {"walk": 1.6, "run": 5.5, "dmg": 9.0, "hp": 2, "size": 0.8},
	"hopper": {"walk": 2.5, "run": 6.0, "dmg": 6.0, "hp": 2, "size": 0.7},
	"flyer": {"walk": 3.5, "run": 8.0, "dmg": 8.0, "hp": 2, "size": 0.9},
	"floater": {"walk": 1.0, "run": 2.6, "dmg": 14.0, "hp": 2, "size": 1.1},
	"rockback": {"walk": 1.0, "run": 3.0, "dmg": 18.0, "hp": 6, "size": 1.3},
}
const SYL_A := ["Кр", "Зо", "Ва", "Тх", "Ну", "Ша", "Ор", "Гле", "Ми", "Хаа", "Ски", "Ру"]
const SYL_B := ["ах", "ук", "ирн", "одон", "елл", "ус", "ракс", "ипт", "ан", "ош"]
const TEMPER_NAMES := {"passive": "мирный", "neutral": "осторожный", "aggressive": "хищник"}


## Список видов планеты. Пустой список — жизни нет (такое бывает на смертельно радиоактивных мирах).
static func species_for(planet: Dictionary, profile: Dictionary, biome_data: Dictionary) -> Array[Dictionary]:
	var r := RandomNumberGenerator.new()
	r.seed = int(planet.seed) + 4242 + hash(planet.biome)
	var rad: float = profile.rad
	var out: Array[Dictionary] = []
	if rad > 3.4 and r.randf() < 0.6:
		return out
	var plans: Array = PLANS_BY_BIOME[planet.biome].duplicate()
	var n := r.randi_range(1, 4) if rad < 2.5 else r.randi_range(1, 2)
	var danger: float = biome_data.danger
	for i in n:
		if plans.is_empty():
			break
		var plan: String = plans.pop_at(r.randi() % plans.size())
		var mutant: bool = rad > 1.6 and r.randf() < clamp((rad - 1.2) / 2.0, 0.0, 0.9)
		var roll: float = r.randf() + (danger - 1.0) * 0.4 + (0.25 if mutant else 0.0)
		var temper := "passive" if roll < 0.4 else ("neutral" if roll < 0.78 else "aggressive")
		if plan == "floater" or plan == "rockback":
			temper = "neutral" if temper == "passive" else temper
		var base: Color = biome_data.creature
		var col: Color = Color.from_hsv(fposmod(base.h + r.randf_range(-0.15, 0.15), 1.0), clamp(base.s * r.randf_range(0.7, 1.2), 0.15, 1.0), clamp(base.v * r.randf_range(0.7, 1.15), 0.2, 1.0))
		if planet.biome == "ice" and r.randf() < 0.6:
			col = Color(0.85, 0.9, 0.95).lerp(col, 0.25)
		var st: Dictionary = PLAN_STATS[plan]
		out.append({
			"name": SYL_A[r.randi() % SYL_A.size()] + SYL_B[r.randi() % SYL_B.size()],
			"plan": plan,
			"temper": temper,
			"mutant": mutant,
			"color": col,
			"glow": Color.from_hsv(r.randf(), 0.8, 1.0) * 2.5 if mutant else Color(3.5, 2.2, 0.5),
			"size": float(st.size) * r.randf_range(0.8, 1.35) * (1.25 if mutant else 1.0),
			"hp": 0,
			"dmg": float(st.dmg) * (1.5 if mutant else 1.0) * danger,
			"walk": float(st.walk),
			"run": float(st.run) * (1.15 if mutant else 1.0),
			"count": r.randi_range(2, 5) if plan != "rockback" else r.randi_range(1, 3),
		})
	# Запас здоровья: от тела, размера и мутации. Крупные и мутанты крепче.
	for sp in out:
		var st: Dictionary = PLAN_STATS[sp.plan]
		sp.hp = int(round((float(st.hp) * 20.0 + (40.0 if sp.mutant else 0.0)) * float(sp.size) / float(st.size)))
	return out


static func describe(sp: Dictionary) -> String:
	return "%s · %s%s" % [sp.name, TEMPER_NAMES[sp.temper], ", мутант" if sp.mutant else ""]


# ---------- Модели ----------

static func _mat(c: Color, rough: float = 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _sphere(parent: Node3D, r: float, pos: Vector3, scl: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.material = mat
	mi.mesh = sm
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _limb(parent: Node3D, pos: Vector3, length: float, radius: float, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	var leg := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = radius
	lm.bottom_radius = radius * 0.6
	lm.height = length
	lm.material = mat
	leg.mesh = lm
	leg.position.y = -length / 2.0
	pivot.add_child(leg)
	parent.add_child(pivot)
	return pivot


static func _eyes(parent: Node3D, pos: Vector3, spread: float, c: Color) -> void:
	var em := ShipBuilder.unshaded(c)
	for s in [-1.0, 1.0]:
		_sphere(parent, 0.07, pos + Vector3(s * spread, 0, 0), Vector3.ONE, em)


## Собирает существо. Возвращает {"node", "legs", "wings", "body", "plan"}.
static func build(sp: Dictionary) -> Dictionary:
	var g := Node3D.new()
	var col: Color = sp.color
	var mat := _mat(col)
	if sp.mutant:
		mat.emission_enabled = true
		mat.emission = Color(sp.glow) * 0.15
	var legs: Array[Node3D] = []
	var wings: Array[Node3D] = []
	var body: MeshInstance3D
	match sp.plan:
		"quad":
			body = _sphere(g, 0.5, Vector3(0, 1.55, 0), Vector3(1.6, 1.24, 2.5) * 0.5 * 2.0, mat)
			body.scale = Vector3(0.8, 0.62, 1.25)
			var head := _sphere(g, 0.5, Vector3(0, 1.95, -1.2), Vector3(1, 0.9, 1.2), mat)
			_eyes(g, Vector3(0, 2.05, -1.68), 0.22, sp.glow)
			for lp in [Vector2(-0.5, -0.6), Vector2(0.5, -0.6), Vector2(-0.5, 0.6), Vector2(0.5, 0.6)]:
				legs.append(_limb(g, Vector3(lp.x, 1.3, lp.y), 1.3, 0.13, mat))
			head.name = "Head"
		"biped":
			body = _sphere(g, 0.5, Vector3(0, 2.4, 0), Vector3(0.9, 0.8, 1.3), mat)
			var neck := _limb(g, Vector3(0, 2.5, -0.4), 1.2, 0.12, mat)
			neck.rotation.x = -2.4
			_sphere(g, 0.32, Vector3(0, 3.4, -1.25), Vector3(0.9, 0.8, 1.5), mat)
			_eyes(g, Vector3(0, 3.5, -1.6), 0.16, sp.glow)
			for s in [-0.3, 0.3]:
				legs.append(_limb(g, Vector3(s, 2.2, 0), 2.2, 0.11, mat))
		"crawler":
			body = _sphere(g, 0.5, Vector3(0, 0.75, 0), Vector3(1.1, 0.5, 2.2), mat)
			_sphere(g, 0.35, Vector3(0, 0.8, -1.2), Vector3(1.2, 0.7, 1.0), mat)
			_eyes(g, Vector3(0, 0.92, -1.48), 0.18, sp.glow)
			for z in [-0.6, 0.0, 0.6]:
				for s in [-1.0, 1.0]:
					var l := _limb(g, Vector3(s * 0.45, 0.8, z), 1.0, 0.07, mat)
					l.rotation.z = s * 0.9
					legs.append(l)
		"hopper":
			body = _sphere(g, 0.6, Vector3(0, 0.6, 0), Vector3.ONE, mat)
			_eyes(g, Vector3(0, 0.85, -0.52), 0.2, sp.glow)
			for s in [-0.25, 0.25]:
				var ear := _limb(g, Vector3(s, 1.1, 0), 0.6, 0.06, mat)
				ear.rotation.x = PI
				ear.rotation.z = s * 1.2
				wings.append(ear)
		"flyer":
			body = _sphere(g, 0.4, Vector3(0, 0, 0), Vector3(0.8, 0.7, 1.8), mat)
			_eyes(g, Vector3(0, 0.12, -0.68), 0.14, sp.glow)
			var wing_mat := _mat(col.lightened(0.2), 0.4)
			wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			for s in [-1.0, 1.0]:
				var pivot := Node3D.new()
				pivot.position = Vector3(s * 0.25, 0.05, 0)
				var w := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.size = Vector3(1.0, 1.6, 0.03)
				pm.material = wing_mat
				w.mesh = pm
				w.rotation = Vector3(PI / 2.0, 0, s * PI / 2.0)
				w.position = Vector3(s * 0.8, 0, 0.1)
				pivot.add_child(w)
				g.add_child(pivot)
				wings.append(pivot)
		"floater":
			var jelly := _mat(Color(col, 0.55), 0.2)
			jelly.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			jelly.emission_enabled = true
			jelly.emission = col * 0.6
			body = _sphere(g, 0.8, Vector3(0, 0, 0), Vector3(1, 0.7, 1), jelly)
			_sphere(g, 0.3, Vector3(0, 0.05, 0), Vector3.ONE, ShipBuilder.unshaded(Color(sp.glow) * 0.6))
			for i in 6:
				var a := TAU * i / 6.0
				var t := _limb(g, Vector3(cos(a) * 0.45, -0.2, sin(a) * 0.45), 1.6, 0.04, jelly)
				legs.append(t)
		"rockback":
			var shell := _mat(col.darkened(0.45), 0.95)
			body = _sphere(g, 1.0, Vector3(0, 1.0, 0), Vector3(1.2, 0.75, 1.5), shell)
			for i in 5:
				_sphere(g, 0.35, Vector3(randf_range(-0.6, 0.6), 1.6, randf_range(-0.9, 0.9)), Vector3(1, 1.4, 1), shell)
			_sphere(g, 0.4, Vector3(0, 0.75, -1.4), Vector3(1, 0.8, 1), mat)
			_eyes(g, Vector3(0, 0.85, -1.75), 0.18, sp.glow)
			for lp in [Vector2(-0.8, -0.7), Vector2(0.8, -0.7), Vector2(-0.8, 0.7), Vector2(0.8, 0.7)]:
				legs.append(_limb(g, Vector3(lp.x, 0.6, lp.y), 0.7, 0.2, mat))
	g.scale = Vector3.ONE * float(sp.size)
	return {"node": g, "legs": legs, "wings": wings, "body": body, "plan": sp.plan}


## Анимация по форме тела. Возвращает высоту над землёй.
static func animate(b: Dictionary, t: float, moving: bool) -> float:
	var ph: float = b.phase
	match b.plan:
		"quad", "rockback":
			for i in b.legs.size():
				b.legs[i].rotation.x = sin(ph + (0.0 if i == 0 or i == 3 else PI)) * (0.55 if moving else 0.05)
			return 0.0
		"biped":
			for i in b.legs.size():
				b.legs[i].rotation.x = sin(ph + PI * i) * (0.6 if moving else 0.05)
			return abs(sin(ph)) * 0.12 if moving else 0.0
		"crawler":
			for i in b.legs.size():
				b.legs[i].rotation.x = sin(ph * 1.5 + i * 1.1) * (0.5 if moving else 0.08)
			return 0.0
		"hopper":
			var h: float = abs(sin(ph * 0.7)) * (1.4 if moving else 0.25)
			b.body.scale = Vector3(1.0 + (0.15 if h < 0.1 else 0.0), 1.0 - (0.15 if h < 0.1 else 0.0), 1.0)
			return h
		"flyer":
			for i in b.wings.size():
				b.wings[i].rotation.z = sin(t * 9.0 + b.seed) * 0.7 * (1.0 if i == 0 else -1.0)
			return 4.0 + sin(t * 0.8 + b.seed) * 1.2
		"floater":
			var k := 1.0 + sin(t * 2.0 + b.seed) * 0.08
			b.body.scale = Vector3(k, 0.7 / k, k)
			for i in b.legs.size():
				b.legs[i].rotation.x = sin(t * 1.5 + i) * 0.25
			return 2.2 + sin(t * 0.9 + b.seed) * 0.5
	return 0.0
