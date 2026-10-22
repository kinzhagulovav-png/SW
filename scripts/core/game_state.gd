extends Node
## Глобальное состояние игры (автозагрузка GameState).
## Время в галактике идёт всегда, в том числе во время боёв и высадок:
## 1 секунда реального времени = 1 час игрового.

signal hour_passed(hour: int)
signal lab_finished(sample: Dictionary)
## Навык персонажа вырос (person: капитан или член экипажа).
signal skill_up(person: Dictionary, skill: String, level: int)
## Новости галактики: поломки на базах, доставки, налёты, атаки на корабль.
signal news(text: String, color: Color)
## Армия напала на базу, на которой сейчас капитан (сцена планеты выводит солдат).
signal raid_started(base_key: String, faction: String, strength: int)

const HOURS_PER_SECOND := 1.0
const START_HOURS := 8.0
const HOURS_PER_STUDY_LEVEL := 6.0
## Объём рюкзака капитана зависит от рюкзака в снаряжении (People.backpack_size).
## Вместимость и грузоподъёмность корабля зависят от корпуса и оборудования (ShipData).

var hours: float = START_HOURS
var money: int = 700 ## валюта «ПОТОМ»
## Трюм: id минерала, материала, базового элемента или прибора → количество (см. Items).
var inventory: Dictionary = {}
## Неизвестные образцы (Items.make_sample), изученные и нет.
var samples: Array[Dictionary] = []
## Образец в лаборатории: {"sample": id, "done_at": час} или пусто.
var lab: Dictionary = {}
## Капитан и экипаж: навыки и снаряжение (People.new_person). Роли: "учёный", "второй пилот", позже другие.
var hero := _new_hero()
var crew: Array[Dictionary] = []
## Здоровье капитана и скафандр: кислород, защита от радиации, броня (всё от 0 до 100).
## Радзащиту и броню восстанавливает только отсек ремонта оборудования на корабле.
var health := 100.0
var suit := {"oxygen": 100.0, "rad": 100.0, "armor": 100.0}
## Корабль: корпус, оборудование по слотам {"id","mk","cond"}, топливо.
var ship := _new_ship()
## Что уже куплено в магазинах сегодня: {"место:день": [номера]}.
var shop_sold := {}
## Для итогов в титрах.
var stats := {"minerals": 0, "samples": 0, "landings": 0, "beasts": 0, "dug": 0}
## Где и как погиб капитан (для титров).
var death: Dictionary = {}
var galaxy_seed: int = 0
## Планета, на которую высаживаемся: {"name", "biome", "seed"}.
var current_planet: Dictionary = {}
## Где был корабль в системе перед высадкой, чтобы вернуть его туда же.
var system_state: Dictionary = {}
## Базы на планетах: ключ — str(seed планеты), значение — BaseData.new_base.
var bases: Dictionary = {}
## Заказы в пути: {"type": "module"/"masters", "base", "id"/"uid", "from", "faction", "eta"}.
var orders: Array[Dictionary] = []
## Войны: ключ места (station:…/colony:…) → {"name", "since", "next_raid"}.
var wars: Dictionary = {}
var news_log: Array[String] = []
## Капитан сейчас на поверхности планеты (current_planet).
var on_planet := false

var _last_hour: int = int(START_HOURS)


func _ready() -> void:
	randomize()
	galaxy_seed = randi()


## Новая игра после гибели капитана.
func reset() -> void:
	hours = START_HOURS
	_last_hour = int(START_HOURS)
	money = 700
	inventory = {}
	samples.clear()
	lab = {}
	crew.clear()
	hero = _new_hero()
	ship = _new_ship()
	shop_sold = {}
	health = 100.0
	suit = {"oxygen": 100.0, "rad": 100.0, "armor": 100.0}
	stats = {"minerals": 0, "samples": 0, "landings": 0, "beasts": 0, "dug": 0}
	current_planet = {}
	system_state = {}
	bases = {}
	orders.clear()
	wars = {}
	news_log.clear()
	on_planet = false
	death = {}
	galaxy_seed = randi()


func _process(delta: float) -> void:
	hours += delta * HOURS_PER_SECOND
	while int(hours) > _last_hour:
		_last_hour += 1
		hour_passed.emit(_last_hour)
		_simulate_hour()
	if not lab.is_empty() and hours >= float(lab.done_at):
		_finish_study()


func time_text() -> String:
	var day := int(hours / 24.0) + 1
	return "День %d, %02d:00" % [day, int(hours) % 24]


func add_item(id: String, count: int = 1) -> void:
	inventory[id] = int(inventory.get(id, 0)) + count
	if inventory[id] <= 0:
		inventory.erase(id)


func count(id: String) -> int:
	return int(inventory.get(id, 0))


func _new_hero() -> Dictionary:
	var h := People.new_person("Капитан", "капитан")
	h.gear = People.starter_gear()
	return h


# ---------- Навыки и снаряжение ----------

## Опыт навыку персонажа. Экипаж учится быстрее с Лидерством капитана.
func add_xp(p: Dictionary, skill: String, amount: int = 1) -> void:
	if not is_same(p, hero):
		amount = int(round(float(amount) * (1.0 + 0.1 * People.level(hero, "leadership"))))
	var lvl := People.add_xp(p, skill, amount)
	if lvl >= 0:
		skill_up.emit(p, skill, lvl)
		if not is_same(p, hero):
			add_xp(hero, "leadership", 1)


func hero_xp(skill: String, amount: int = 1) -> void:
	add_xp(hero, skill, amount)


func lvl(skill: String) -> int:
	return People.level(hero, skill)


## Лучший уровень навыка среди капитана и экипажа (для полёта, ремонта).
func team_level(skill: String) -> int:
	var best := lvl(skill)
	for c in crew:
		best = max(best, People.level(c, skill))
	return best


func max_health() -> float:
	return People.max_hp(hero)


func gear(slot: String) -> Dictionary:
	return hero.gear.get(slot, {})


func backpack() -> int:
	return People.backpack_size(gear("backpack"))


## Множители цен: торговля капитана, на рынках колоний ещё дипломатия.
func buy_mult(colony: bool = false) -> float:
	return max(0.6, 1.0 - 0.03 * lvl("trade") - (0.02 * lvl("diplomacy") if colony else 0.0))


func sell_mult(colony: bool = false) -> float:
	return 1.0 + 0.03 * lvl("trade") + (0.02 * lvl("diplomacy") if colony else 0.0)


## Опыт за сделку: торговля, на рынке колонии и дипломатия.
func trade_xp(colony: bool = false) -> void:
	hero_xp("trade", 1)
	if colony:
		hero_xp("diplomacy", 1)


func land_fuel() -> float:
	return ShipData.LAND_FUEL * (1.0 - 0.05 * team_level("piloting"))


func _new_ship() -> Dictionary:
	return {
		"hull": "skif",
		"equip": {
			"engine": {"id": "engine", "mk": 1, "cond": 90},
			"tank": {"id": "tank", "mk": 1, "cond": 90},
			"radar": {"id": "radar", "mk": 1, "cond": 85},
		},
		"fuel": 45.0,
		"hull_hp": float(ShipData.ARMOR.skif),
	}


func hull() -> Dictionary:
	return ShipData.HULLS[ship.hull]


func equip(slot: String) -> Dictionary:
	return ship.equip.get(slot, {})


func equip_volume() -> int:
	var v := 0
	for slot in ship.equip:
		v += ShipData.size_of(ship.equip[slot])
	return v


func equip_mass() -> float:
	var m := 0.0
	for slot in ship.equip:
		m += ShipData.mass_of(ship.equip[slot])
	return m


## Свободное место корпуса после оборудования.
func cargo_capacity() -> int:
	return int(hull().capacity) - equip_volume()


func max_hull_hp() -> float:
	return float(ShipData.ARMOR[ship.hull])


static func _category(id: String) -> String:
	if BaseData.is_part(id):
		return "part"
	if Items.MINERALS.has(id):
		return "mineral"
	if Items.MATERIALS.has(id):
		return "material"
	if Items.BASICS.has(id):
		return "basic"
	return "device"


func cargo_volume() -> int:
	var v := 0
	for id in inventory:
		v += int(ShipData.CARGO_VOLUME[_category(id)]) * int(inventory[id])
	return v + samples.size() * int(ShipData.CARGO_VOLUME.sample)


func item_volume(id: String) -> int:
	return int(ShipData.CARGO_VOLUME[_category(id)])


## Масса всего груза в трюме, кг.
func cargo_mass() -> float:
	var m := 0.0
	for id in inventory:
		m += Items.mass_of(id) * int(inventory[id])
	return m + samples.size() * Items.SAMPLE_MASS


## Грузоподъёмность: сколько груза и оборудования корабль может поднять.
func max_lift() -> float:
	var e := equip("engine")
	return float(hull().lift) + (ShipData.engine_lift(e) if not e.is_empty() else 0.0)


func takeoff_mass() -> float:
	return cargo_mass() + equip_mass()


func overloaded() -> bool:
	return takeoff_mass() > max_lift()


func max_fuel() -> float:
	var e := equip("tank")
	return ShipData.tank_size(e) if not e.is_empty() else 10.0


func ship_speed() -> float:
	var e := equip("engine")
	return (ShipData.engine_speed(e) if not e.is_empty() else 8.0) * float(hull().speed) * (1.0 + 0.04 * team_level("piloting"))


func radar_range() -> float:
	var e := equip("radar")
	return ShipData.radar_range(e) if not e.is_empty() else 35.0


func repair_mult() -> float:
	var e := equip("droid")
	var base := 1.0 + ShipData.power(e) * 0.5 if not e.is_empty() else 1.0
	return base * (1.0 + 0.1 * team_level("tech"))


func scanner_mk() -> int:
	var e := equip("scanner")
	return int(e.mk) if not e.is_empty() else 0


func crew_full() -> bool:
	return crew.size() >= int(hull().crew) - 1  # одно место — капитан


func has_device(id: String) -> bool:
	return count(id) > 0


## Превратить ингредиенты в предмет. Возвращает false, если чего-то не хватает.
func craft(id: String, need: Dictionary, price: int = 0) -> bool:
	if not Items.can_make(inventory, need) or money < price:
		return false
	for k in need:
		add_item(k, -int(need[k]))
	money -= price
	add_item(id, 1)
	hero_xp("tech", 1)
	return true


# ---------- Лаборатория ----------

func best_scientist() -> Dictionary:
	var best := {}
	for c in crew:
		if c.role == "учёный" and (best.is_empty() or People.level(c, "science") > People.level(best, "science")):
			best = c
	return best


## Почему образец нельзя изучить, или пустая строка, если можно.
func study_problem(sample: Dictionary) -> String:
	if sample.studied:
		return "уже изучен"
	if not lab.is_empty():
		return "лаборатория занята"
	var sci := best_scientist()
	if sci.is_empty():
		return "нужен учёный в экипаже"
	var know := People.level(sci, "science") + lvl("science")
	if know < int(sample.level) * 2:
		return "мало знаний: Наука учёного %d + капитана %d < сложность %d ×2" % [People.level(sci, "science"), lvl("science"), sample.level]
	return ""


func start_study(sample: Dictionary) -> bool:
	if study_problem(sample) != "":
		return false
	lab = {"sample": sample.id, "done_at": hours + HOURS_PER_STUDY_LEVEL * float(sample.level)}
	return true


func _finish_study() -> void:
	var id: String = lab.sample
	lab = {}
	for s in samples:
		if s.id == id:
			s.studied = true
			s.name = s.true_name
			hero_xp("science", 2 * int(s.level))
			var sci := best_scientist()
			if not sci.is_empty():
				add_xp(sci, "science", 2 * int(s.level))
			lab_finished.emit(s)
			return


# ---------- Базы, заказы, войны (каждый час времени галактики) ----------

func say(text: String, color: Color = Color("#ffbf55")) -> void:
	news_log.append("%s · %s" % [time_text(), text])
	if news_log.size() > 30:
		news_log.remove_at(0)
	news.emit(text, color)


func base_here() -> Dictionary:
	if current_planet.is_empty():
		return {}
	return bases.get(str(current_planet.seed), {})


static func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)


func base_name(b: Dictionary) -> String:
	return "база на %s" % b.planet.name


func at_war(key: String) -> bool:
	return wars.has(key)


func declare_war(key: String, faction: String) -> void:
	if wars.has(key):
		return
	wars[key] = {"name": faction, "since": hours, "next_raid": hours + randf_range(40.0, 80.0)}
	say("%s объявляет вам войну! Их армия будет нападать на ваши базы и корабль." % faction, Color("#ff6a4a"))


## Цена мира: растёт со временем войны, Дипломатия снижает.
func peace_price(key: String) -> int:
	var w: Dictionary = wars[key]
	var days := (hours - float(w.since)) / 24.0
	return int((2000.0 + days * 150.0) * max(0.4, 1.0 - 0.06 * lvl("diplomacy")))


func make_peace(key: String) -> void:
	var w: Dictionary = wars[key]
	wars.erase(key)
	hero_xp("diplomacy", 4)
	say("Заключён мир: %s больше не воюет с вами." % w.name, Color("#9aff6a"))


## Мастера чинят модуль: всё как новое, ресурс эксплуатации восстановлен.
func masters_repair(b: Dictionary, m: Dictionary) -> void:
	m.worn = 0.0
	m.life = float(BaseData.MODULES[m.id].life)
	m.broken = false


## Механик чинит хуже мастеров: состояние до 55–95% и срок службы немного падает.
func mechanic_quality(mech: Dictionary) -> float:
	return min(95.0, 55.0 + 4.0 * People.level(mech, "tech"))


func best_mechanic() -> Dictionary:
	var best := {}
	for c in crew:
		if c.role == "механик" and (best.is_empty() or People.level(c, "tech") > People.level(best, "tech")):
			best = c
	return best


func _simulate_hour() -> void:
	for key in bases.keys():
		_simulate_base(key, bases[key])
	for i in range(orders.size() - 1, -1, -1):
		var o: Dictionary = orders[i]
		if hours >= float(o.eta):
			orders.remove_at(i)
			_arrive(o)
	for key in wars.keys():
		var w: Dictionary = wars[key]
		if hours >= float(w.next_raid):
			w.next_raid = hours + randf_range(150.0, 300.0)
			_raid(key, w)
	# Патрули армий охотятся за кораблём, пока он в космосе.
	if not on_planet and not wars.is_empty() and randf() < 0.01 * wars.size():
		var w: Dictionary = wars.values()[randi() % wars.size()]
		var sh := equip("shield")
		var cut := ShipData.power(sh) * 0.06 if not sh.is_empty() else 0.0
		var dmg := randf_range(12.0, 35.0) * (1.0 - cut)
		ship.hull_hp = max(0.0, float(ship.hull_hp) - dmg)
		say("Патруль армии «%s» атаковал корабль: −%d прочности (осталось %d)." % [w.name, int(dmg), int(ship.hull_hp)], Color("#ff6a4a"))
		if float(ship.hull_hp) <= 0.0:
			death = {"planet": "космосе", "biome": "корабль уничтожен армией «%s»" % w.name}
			get_tree().change_scene_to_file("res://scenes/ui/credits.tscn")


func _simulate_base(key: String, b: Dictionary) -> void:
	var en := BaseData.energy(b)
	var ratio: float = en.ratio
	var name := base_name(b)
	for m in b.modules:
		if m.broken:
			continue
		var d: Dictionary = BaseData.MODULES[m.id]
		# Работает только то, на что хватает энергии; электростанции работают всегда.
		var load := 1.0 if int(d.energy) >= 0 else ratio
		m.worn = float(m.worn) + load
		var c := BaseData.cond(m)
		var risk := 0.0 if c > 30.0 else (0.004 + (30.0 - c) * 0.0015)
		if float(m.worn) >= float(m.life) or randf() < risk:
			m.broken = true
			say("%s: сломался модуль «%s». Нужен ремонт." % [_cap(name), d.name], Color("#ff8a6a"))
	var acc: Dictionary = b.acc
	var cap := BaseData.store_cap(b)
	# Бур: минералы планеты.
	var drills := BaseData.count_working(b, "drill")
	var minerals: Array = Biomes.profile(b.planet).minerals
	if drills > 0 and not minerals.is_empty():
		acc.drill = float(acc.drill) + BaseData.DRILL_RATE * drills * ratio
		while float(acc.drill) >= 1.0 and BaseData.store_used(b) < cap:
			acc.drill = float(acc.drill) - 1.0
			var id := Items.roll_mineral(_rng_base, b.planet.biome, 8.0, minerals)
			if id != "":
				BaseData.store_add(b, id, 1)
	# Завод: первый материал, на который хватает минералов на складе.
	var refs := BaseData.count_working(b, "refinery")
	if refs > 0:
		acc.refine = float(acc.refine) + BaseData.REFINE_RATE * refs * ratio
		while float(acc.refine) >= 1.0:
			acc.refine = float(acc.refine) - 1.0
			for mid in Items.MATERIALS:
				var need: Dictionary = Items.MATERIALS[mid].need
				if Items.can_make(b.store, need):
					for k in need:
						BaseData.store_add(b, k, -int(need[k]))
					BaseData.store_add(b, mid, 1)
					break
	# Мастерская: очередь запчастей (материалы уже списаны при заказе).
	if not b.queue.is_empty() and BaseData.has_working(b, "workshop") and BaseData.has_working(b, "habitat"):
		acc.part = float(acc.part) + ratio / BaseData.PART_HOURS
		if float(acc.part) >= 1.0:
			acc.part = 0.0
			var pid: String = b.queue.pop_front()
			BaseData.store_add(b, pid, 1)
			say("%s: мастерская сделала «%s»." % [_cap(name), BaseData.part_name(pid)], Color("#9ad8ff"))
	# Ремонт механиком.
	if not b.job.is_empty() and hours >= float(b.job.done_at):
		var m := BaseData.find(b, int(b.job.uid))
		if not m.is_empty():
			m.broken = false
			m.life = float(m.life) * 0.92
			m.worn = float(m.life) * (1.0 - float(b.job.quality) / 100.0)
			say("%s: %s починил «%s» до %d%%." % [_cap(name), b.job.who, BaseData.MODULES[m.id].name, int(b.job.quality)], Color("#9aff6a"))
		b.job = {}
	# Мастера закончили работу и улетели.
	if not b.visit.is_empty() and hours >= float(b.visit.until):
		var v: Dictionary = b.visit
		b.visit = {}
		if not v.hostile:
			var m := BaseData.find(b, int(v.uid))
			if not m.is_empty():
				masters_repair(b, m)
				say("%s: мастера из «%s» починили «%s», как новый." % [_cap(name), v.faction, BaseData.MODULES[m.id].name], Color("#9aff6a"))


var _rng_base := RandomNumberGenerator.new()


func _arrive(o: Dictionary) -> void:
	var b: Dictionary = bases.get(o.base, {})
	if b.is_empty():
		return
	var name := base_name(b)
	if o.type == "module":
		BaseData.new_module(b, o.id)
		say("%s: доставлен модуль «%s»." % [_cap(name), BaseData.MODULES[o.id].name], Color("#9ad8ff"))
	elif o.type == "masters":
		var m := BaseData.find(b, int(o.uid))
		if m.is_empty() or at_war(o.from):
			return
		b.visit = {"uid": o.uid, "from": o.from, "faction": o.faction, "until": hours + 6.0 + 2.0 * float(BaseData.MODULES[m.id].tier),
			"hostile": false, "parts": 2, "id": m.id}
		say("%s: прилетели мастера из «%s» со своими запчастями и чинят «%s»." % [_cap(name), o.faction, BaseData.MODULES[m.id].name], Color("#9ad8ff"))


## Налёт армии на одну из баз. Если капитан на этой планете, бой идёт на месте.
func _raid(key: String, w: Dictionary) -> void:
	if bases.is_empty():
		return
	var bkey: String = bases.keys()[randi() % bases.size()]
	var b: Dictionary = bases[bkey]
	var days := (hours - float(w.since)) / 24.0
	var strength := 3 + int(days / 3.0)
	if on_planet and str(current_planet.get("seed", "")) == bkey:
		say("Армия «%s» высаживается у вашей базы! Солдат: %d." % [w.name, strength], Color("#ff6a4a"))
		raid_started.emit(bkey, w.name, strength)
		return
	resolve_raid(b, w.name, strength)


## Налёт без капитана: турели отбиваются, остальное достаётся модулям.
func resolve_raid(b: Dictionary, faction: String, strength: int) -> void:
	var ratio: float = BaseData.energy(b).ratio
	var defense := int(BaseData.count_working(b, "turret") * 2 * ratio)
	var hits := strength - defense
	var name := base_name(b)
	if hits <= 0:
		say("%s отбила налёт армии «%s»: турели справились." % [_cap(name), faction], Color("#9aff6a"))
		return
	var lost := PackedStringArray()
	for i in hits:
		if b.modules.is_empty():
			break
		var m: Dictionary = b.modules[randi() % b.modules.size()]
		m.worn = float(m.worn) + float(m.life) * 0.35
		if float(m.worn) >= float(m.life):
			if m.broken:
				b.modules.erase(m)
				lost.append(BaseData.MODULES[m.id].name)
			else:
				m.broken = true
	if b.modules.is_empty():
		bases.erase(str(b.planet.seed))
		say("Армия «%s» уничтожила вашу базу на %s!" % [faction, b.planet.name], Color("#ff4a3a"))
		return
	say("Налёт армии «%s» на %s: модули повреждены%s." % [faction, name, (", уничтожены: " + ", ".join(lost)) if not lost.is_empty() else ""], Color("#ff6a4a"))
