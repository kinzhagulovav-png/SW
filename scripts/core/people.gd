class_name People
extends RefCounted
## Навыки и снаряжение капитана и членов экипажа.
## Навыки в духе классических космических рейнджеров (точность, техника, торговля, лидерство…)
## плюс свои для планет: выносливость, геология, наука, дипломатия.
## Уровень навыка 0..10, опыт за действия. Снаряжение по слотам, Мк-1…4 и износ, как оборудование корабля.
##
## Персонаж: {"name", "role", "skills": {id: уровень}, "xp": {id: опыт}, "gear": {слот: {"id","mk","cond"}}}

const MAX_LEVEL := 10

const SKILLS := {
	"accuracy": {"name": "Точность", "color": Color("#ff7a5a"),
		"desc": "Урон бластера +8% за уровень и легче попасть. Опыт: попадания и победы над зверями."},
	"endurance": {"name": "Выносливость", "color": Color("#ffb04a"),
		"desc": "Кислород и радзащита тратятся на 4% медленнее за уровень, здоровье восстанавливается. Опыт: время на открытой местности."},
	"geology": {"name": "Геология", "color": Color("#d8a060"),
		"desc": "Шанс найти лишний минерал при раскопках +6% за уровень, детектор видит дальше. Опыт: найденные минералы и образцы."},
	"science": {"name": "Наука", "color": Color("#9aff6a"),
		"desc": "Сложные образцы: Наука учёного + Наука капитана должна быть не меньше сложности ×2. Опыт: изучение образцов."},
	"tech": {"name": "Техника", "color": Color("#6fdcff"),
		"desc": "Ремонт в отсеке быстрее на 10% за уровень, улучшение снаряжения дешевле. Опыт: переработка, сборка, ремонт."},
	"trade": {"name": "Торговля", "color": Color("#ffd75a"),
		"desc": "Покупка дешевле и продажа дороже на 3% за уровень. Опыт: сделки."},
	"piloting": {"name": "Пилотирование", "color": Color("#8ab0ff"),
		"desc": "Скорость корабля +4% и расход топлива на посадку −5% за уровень. Опыт: полёты, посадки и взлёты."},
	"leadership": {"name": "Лидерство", "color": Color("#e08aff"),
		"desc": "Экипаж учится быстрее на 10% за уровень, найм дешевле. Опыт: найм и рост экипажа."},
	"diplomacy": {"name": "Дипломатия", "color": Color("#7affd8"),
		"desc": "Цены на рынках колоний лучше на 2% за уровень. Позже: отношения с расами и смешанный экипаж. Опыт: сделки с колониями."},
}

## Главный навык роли: с ним член экипажа нанимается и в нём растёт быстрее.
const ROLE_SKILL := {"учёный": "science", "второй пилот": "piloting", "боец": "accuracy", "механик": "tech"}
## С чем нанимается каждая роль (Мк-1, немного поношенное).
const ROLE_GEAR := {
	"учёный": ["suit", "armor"],
	"второй пилот": ["suit", "armor"],
	"боец": ["suit", "armor", "weapon", "boots"],
	"механик": ["suit", "armor", "lapatron", "backpack"],
}

## Слоты снаряжения. base — цена Мк-1.
const GEAR := {
	"suit": {"name": "Скафандр", "base": 260, "mass": 8.0, "desc": "Экономит кислород и радзащиту."},
	"armor": {"name": "Броня", "base": 300, "mass": 10.0, "desc": "Поглощает часть урона от зверей и лавы."},
	"boots": {"name": "Ботинки", "base": 160, "mass": 3.0, "desc": "Скорость ходьбы и бега."},
	"weapon": {"name": "Бластер", "base": 320, "mass": 4.0, "desc": "Урон и скорострельность."},
	"jetpack": {"name": "Ранец", "base": 280, "mass": 7.0, "desc": "Сколько секунд держит в воздухе."},
	"backpack": {"name": "Рюкзак", "base": 140, "mass": 3.0, "desc": "Сколько минералов и образцов можно унести."},
	"lapatron": {"name": "Лапатрон", "base": 300, "mass": 6.0, "desc": "Скорость и глубина раскопок."},
	"detector": {"name": "Детектор недр", "base": 380, "mass": 2.0, "desc": "Показывает на радаре жилы минералов под землёй."},
}
const MK := ["Мк-1", "Мк-2", "Мк-3", "Мк-4"]
## Что нужно для улучшения на Мк выше: базовые элементы (см. Items.BASICS).
const UPGRADE_NEED := {2: {"frame": 1}, 3: {"frame": 1, "chip": 1}, 4: {"frame": 1, "chip": 1, "core": 1}}


static func new_person(name: String, role: String, main_level: int = 0) -> Dictionary:
	var p := {"name": name, "role": role, "skills": {}, "xp": {}, "gear": {}, "lands": true}
	for slot in ROLE_GEAR.get(role, []):
		p.gear[slot] = {"id": slot, "mk": 1, "cond": 80}
	for id in SKILLS:
		p.skills[id] = 0
		p.xp[id] = 0
	if ROLE_SKILL.has(role):
		p.skills[ROLE_SKILL[role]] = main_level
	return p


## Начальное снаряжение капитана: всё Мк-1, кроме детектора.
static func starter_gear() -> Dictionary:
	var g := {}
	for slot in GEAR:
		if slot != "detector":
			g[slot] = {"id": slot, "mk": 1, "cond": 90}
	return g


static func level(p: Dictionary, skill: String) -> int:
	return int(p.get("skills", {}).get(skill, 0))


## Сколько опыта нужно до следующего уровня.
static func xp_need(lvl: int) -> int:
	return 5 + lvl * 5


## Добавить опыт. Возвращает новый уровень, если навык вырос, иначе -1.
static func add_xp(p: Dictionary, skill: String, amount: int) -> int:
	var lvl := level(p, skill)
	if lvl >= MAX_LEVEL or amount <= 0:
		return -1
	var xp := int(p.xp.get(skill, 0)) + amount
	var grew := false
	while lvl < MAX_LEVEL and xp >= xp_need(lvl):
		xp -= xp_need(lvl)
		lvl += 1
		grew = true
	p.xp[skill] = xp if lvl < MAX_LEVEL else 0
	p.skills[skill] = lvl
	return lvl if grew else -1


# ---------- Снаряжение ----------

static func power(e: Dictionary) -> float:
	if e.is_empty():
		return 0.0
	return float(e.mk) * (0.5 + 0.5 * float(e.cond) / 100.0)


static func price(e: Dictionary) -> int:
	return int(float(GEAR[e.id].base) * pow(float(e.mk), 1.6) * (0.3 + 0.7 * float(e.cond) / 100.0))


static func buyback(e: Dictionary) -> int:
	return int(price(e) * 0.5)


static func title(e: Dictionary) -> String:
	return "%s %s (%d%%)" % [GEAR[e.id].name, MK[int(e.mk) - 1], int(e.cond)]


## Числа эффектов. Пустой слот работает как самое простое.
static func suit_o2_mult(e: Dictionary) -> float:
	return 1.0 / (1.0 + 0.3 * max(0.0, power(e) - 1.0)) if not e.is_empty() else 1.4


static func suit_rad_mult(e: Dictionary) -> float:
	return 1.0 / (1.0 + 0.4 * max(0.0, power(e) - 1.0)) if not e.is_empty() else 1.5


static func armor_cut(e: Dictionary) -> float:
	return 0.1 + 0.1 * power(e) if not e.is_empty() else 0.0


static func boots_mult(e: Dictionary) -> float:
	return 1.0 + 0.08 * max(0.0, power(e) - 1.0) if not e.is_empty() else 0.9


static func weapon_damage(e: Dictionary) -> float:
	return power(e) if not e.is_empty() else 0.0


static func weapon_cooldown(e: Dictionary) -> float:
	return 0.32 - 0.04 * float(int(e.mk) - 1) if not e.is_empty() else 1.0


static func jet_mult(e: Dictionary) -> float:
	return 1.0 + 0.35 * max(0.0, power(e) - 1.0) if not e.is_empty() else 0.0


static func backpack_size(e: Dictionary) -> int:
	return 40 + 15 * (int(e.mk) - 1) if not e.is_empty() else 15


static func lapatron_strength(e: Dictionary) -> float:
	return 0.18 + 0.05 * power(e) if not e.is_empty() else 0.0


static func lapatron_depth(e: Dictionary) -> float:
	return 12.0 + 6.0 * float(int(e.mk) - 1) if not e.is_empty() else 0.0


## Детектор: доля дальности радара, на которой видны жилы.
static func detector_reach(e: Dictionary) -> float:
	return 0.35 + 0.15 * power(e) if not e.is_empty() else 0.0


static func effect_text(e: Dictionary) -> String:
	match e.id:
		"suit":
			return "кислород ×%.2f, радиация ×%.2f" % [suit_o2_mult(e), suit_rad_mult(e)]
		"armor":
			return "поглощает %d%% урона" % int(armor_cut(e) * 100.0)
		"boots":
			return "скорость ×%.2f" % boots_mult(e)
		"weapon":
			return "урон %.1f, выстрел раз в %.2f с" % [weapon_damage(e), weapon_cooldown(e)]
		"jetpack":
			return "полёт %.1f с" % (1.6 * jet_mult(e))
		"backpack":
			return "%d ячеек" % backpack_size(e)
		"lapatron":
			return "копает ×%.2f, глубина %d м" % [lapatron_strength(e) / 0.23, int(lapatron_depth(e))]
		"detector":
			return "жилы на %d%% дальности радара" % int(min(1.0, detector_reach(e)) * 100.0)
	return ""


## Ассортимент снаряжения в месте на этот день.
static func shop_stock(key: String, day: int, tech: int) -> Array[Dictionary]:
	var r := RandomNumberGenerator.new()
	r.seed = hash(key + ":gear") + day * 6271
	var out: Array[Dictionary] = []
	var ids := GEAR.keys()
	for i in r.randi_range(5, 8):
		var mk := clampi(r.randi_range(1, tech) + (1 if r.randf() < 0.15 else 0), 1, 4)
		var e := {"id": ids[r.randi() % ids.size()], "mk": mk, "cond": r.randi_range(75, 100)}
		e["cost"] = int(price(e) * r.randf_range(0.9, 1.25))
		out.append(e)
	return out


## Цена улучшения предмета на один Мк (без учёта навыков).
static func upgrade_cost(e: Dictionary) -> int:
	var next := {"id": e.id, "mk": int(e.mk) + 1, "cond": e.cond}
	return int((price(next) - price(e)) * 0.7)
