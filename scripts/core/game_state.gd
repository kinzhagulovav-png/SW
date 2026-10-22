extends Node
## Глобальное состояние игры (автозагрузка GameState).
## Время в галактике идёт всегда, в том числе во время боёв и высадок:
## 1 секунда реального времени = 1 час игрового.

signal hour_passed(hour: int)
signal lab_finished(sample: Dictionary)

const HOURS_PER_SECOND := 1.0
const START_HOURS := 8.0
const HOURS_PER_STUDY_LEVEL := 6.0

var hours: float = START_HOURS
var money: int = 700 ## валюта «ПОТОМ»
## Трюм: id минерала, материала, базового элемента или прибора → количество (см. Items).
var inventory: Dictionary = {}
## Неизвестные образцы (Items.make_sample), изученные и нет.
var samples: Array[Dictionary] = []
## Образец в лаборатории: {"sample": id, "done_at": час} или пусто.
var lab: Dictionary = {}
## Экипаж: [{"name", "role", "skill"}]. Роли: "учёный", позже механик, боец и другие.
var crew: Array[Dictionary] = []
## Навыки капитана. science растёт от изучения образцов.
var skills := {"science": 0}
var science_xp := 0
## Здоровье капитана и скафандр: кислород, защита от радиации, броня (всё от 0 до 100).
## Радзащиту и броню восстанавливает только отсек ремонта оборудования на корабле.
var health := 100.0
var suit := {"oxygen": 100.0, "rad": 100.0, "armor": 100.0}
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
	skills = {"science": 0}
	science_xp = 0
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
	return true


# ---------- Лаборатория ----------

func best_scientist() -> Dictionary:
	var best := {}
	for c in crew:
		if c.role == "учёный" and (best.is_empty() or int(c.skill) > int(best.skill)):
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
	if int(sci.skill) + int(skills.science) < int(sample.level):
		return "мало знаний: учёный %d + Наука капитана %d < сложность %d" % [sci.skill, skills.science, sample.level]
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
			science_xp += int(s.level)
			while science_xp >= 3 and int(skills.science) < 5:
				science_xp -= 3
				skills.science += 1
			lab_finished.emit(s)
			return
