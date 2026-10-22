extends Node
## Глобальное состояние игры (автозагрузка GameState).
## Время в галактике идёт всегда, в том числе во время боёв и высадок:
## 1 секунда реального времени = 1 час игрового.

signal hour_passed(hour: int)
signal lab_finished(sample: Dictionary)
## Навык персонажа вырос (person: капитан или член экипажа).
signal skill_up(person: Dictionary, skill: String, level: int)

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
	death = {}
	galaxy_seed = randi()


func _process(delta: float) -> void:
	hours += delta * HOURS_PER_SECOND
	while int(hours) > _last_hour:
		_last_hour += 1
		hour_passed.emit(_last_hour)
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


static func _category(id: String) -> String:
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
