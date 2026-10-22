class_name Items
extends RefCounted
## Справочник предметов и цепочка производства:
## минералы (реальные элементы) → материалы (переработка на корабле)
## → базовые элементы (сборка из материалов на корабле)
## → приборы, вещи, еда, вода (только на научной станции и за ПОТОМ).
## Неизвестные образцы изучаются в лаборатории корабля, если в экипаже есть учёный.

## depth: на какой глубине (м) минерал начинает встречаться в недрах; weight: насколько часто.
const MINERALS := {
	"fe": {"name": "Железо", "sym": "Fe", "color": Color("#8a8f99"), "depth": 0.0, "weight": 10.0, "price": 4},
	"cu": {"name": "Медь", "sym": "Cu", "color": Color("#d07a40"), "depth": 0.0, "weight": 7.0, "price": 6},
	"si": {"name": "Кремний", "sym": "Si", "color": Color("#7a8aa8"), "depth": 0.0, "weight": 8.0, "price": 4},
	"c": {"name": "Углерод", "sym": "C", "color": Color("#3a3a40"), "depth": 0.0, "weight": 8.0, "price": 3},
	"al": {"name": "Алюминий", "sym": "Al", "color": Color("#d0d4dc"), "depth": 1.0, "weight": 6.0, "price": 6},
	"s": {"name": "Сера", "sym": "S", "color": Color("#e8d040"), "depth": 0.0, "weight": 5.0, "price": 5},
	"h2o": {"name": "Водяной лёд", "sym": "H₂O", "color": Color("#a8d8ff"), "depth": 0.0, "weight": 5.0, "price": 2},
	"ni": {"name": "Никель", "sym": "Ni", "color": Color("#b8b890"), "depth": 2.0, "weight": 4.0, "price": 9},
	"li": {"name": "Литий", "sym": "Li", "color": Color("#e8f0ff"), "depth": 2.0, "weight": 3.0, "price": 12},
	"ti": {"name": "Титан", "sym": "Ti", "color": Color("#9ab0c8"), "depth": 3.0, "weight": 3.0, "price": 14},
	"au": {"name": "Золото", "sym": "Au", "color": Color("#ffcc33"), "depth": 5.0, "weight": 1.5, "price": 40},
	"pt": {"name": "Платина", "sym": "Pt", "color": Color("#eceef2"), "depth": 6.0, "weight": 1.0, "price": 55},
	"u": {"name": "Уран", "sym": "U", "color": Color("#6aff4a"), "depth": 7.0, "weight": 1.0, "price": 60},
}

## Какие минералы чаще встречаются в каждом биоме (множитель веса).
const BIOME_BIAS := {
	"desert": {"si": 3.0, "al": 2.0, "ti": 2.0, "h2o": 0.1},
	"ice": {"h2o": 5.0, "li": 2.5, "ni": 1.5},
	"jungle": {"c": 3.0, "cu": 2.0, "ni": 1.5},
	"volcano": {"s": 4.0, "fe": 2.0, "au": 2.5, "pt": 1.5, "h2o": 0.0},
	"toxic": {"s": 2.5, "u": 3.0, "cu": 1.5},
}

## Материалы: переработка минералов на корабле.
const MATERIALS := {
	"steel": {"name": "Сталь", "need": {"fe": 3, "c": 1}},
	"wire": {"name": "Медный провод", "need": {"cu": 2}},
	"glass": {"name": "Стекло", "need": {"si": 3}},
	"alloy": {"name": "Титановый сплав", "need": {"ti": 2, "al": 1}},
	"cell": {"name": "Литиевая ячейка", "need": {"li": 2, "ni": 1}},
	"polymer": {"name": "Полимер", "need": {"c": 2, "s": 1}},
	"conductor": {"name": "Сверхпроводник", "need": {"au": 1, "cu": 1}},
	"fuel_rod": {"name": "Топливный стержень", "need": {"u": 2, "ni": 1}},
	"water": {"name": "Очищенная вода", "need": {"h2o": 3}},
	"nutrient": {"name": "Питательная среда", "need": {"c": 1, "s": 1, "h2o": 1}},
	"catalyst": {"name": "Платиновый катализатор", "need": {"pt": 1, "al": 1}},
}

## Базовые элементы: комбинации материалов, из них на станции делают приборы и вещи.
const BASICS := {
	"chip": {"name": "Микросхема", "need": {"glass": 1, "conductor": 1}},
	"frame": {"name": "Корпусная панель", "need": {"steel": 2, "alloy": 1}},
	"power": {"name": "Энергоблок", "need": {"cell": 2, "wire": 1}},
	"core": {"name": "Ядро реактора", "need": {"fuel_rod": 2, "alloy": 1}},
	"food_base": {"name": "Пищевая основа", "need": {"nutrient": 2, "water": 1}},
	"water_pack": {"name": "Запас воды", "need": {"water": 2, "polymer": 1}},
	"fabric": {"name": "Гермоткань", "need": {"polymer": 2, "glass": 1}},
	"medgel": {"name": "Медицинский гель", "need": {"catalyst": 1, "water": 1, "polymer": 1}},
}

## Приборы и вещи: только на научной станции, из базовых элементов и за ПОТОМ.
const DEVICES := {
	"ration": {"name": "Сухой паёк", "need": {"food_base": 2, "water_pack": 1}, "price": 40,
		"desc": "Еда для экипажа в долгих полётах."},
	"medkit": {"name": "Аптечка", "need": {"medgel": 1, "fabric": 1}, "price": 60,
		"desc": "На планете клавиша H: +60 здоровья."},
	"scanner": {"name": "Сканер недр", "need": {"chip": 1, "power": 1}, "price": 150,
		"desc": "Радар на планете показывает залежи под землёй."},
	"jetpack2": {"name": "Ранец Мк-2", "need": {"frame": 1, "power": 2}, "price": 250,
		"desc": "Ранец работает в 1,7 раза дольше."},
	"suit": {"name": "Защитный костюм", "need": {"fabric": 2, "frame": 1}, "price": 300,
		"desc": "Урон от животных и лавы меньше на 40%."},
	"lapatron2": {"name": "Лапатрон Мк-2", "need": {"frame": 1, "chip": 1, "power": 1}, "price": 350,
		"desc": "Копает вдвое быстрее и до глубины 24 м."},
	"blaster2": {"name": "Бластер Мк-2", "need": {"chip": 1, "core": 1}, "price": 400,
		"desc": "Двойной урон и быстрее стреляет."},
}

const SAMPLE_PREFIX := ["Кри", "Ноа", "Вел", "Ор", "Зен", "Тал", "Ир", "Ксо", "Мер", "Аль"]
const SAMPLE_SUFFIX := ["ит", "оксид", "ан", "иний", "оль", "ид", "ен"]


static func name_of(id: String) -> String:
	for table in [MINERALS, MATERIALS, BASICS, DEVICES]:
		if table.has(id):
			return table[id].name
	return id


## Случайный минерал для биома с учётом глубины копания.
static func roll_mineral(rng: RandomNumberGenerator, biome: String, depth: float) -> String:
	var bias: Dictionary = BIOME_BIAS.get(biome, {})
	var total := 0.0
	var weights := {}
	for id in MINERALS:
		var m: Dictionary = MINERALS[id]
		if depth < float(m.depth):
			continue
		# Глубже редкие минералы встречаются чаще.
		var w: float = float(m.weight) * float(bias.get(id, 1.0)) * (1.0 + depth * float(m.depth) * 0.05)
		weights[id] = w
		total += w
	var r := rng.randf() * total
	for id in weights:
		r -= weights[id]
		if r <= 0.0:
			return id
	return "fe"


## Новый неизвестный образец. level: сложность изучения (1..3).
static func make_sample(rng: RandomNumberGenerator, biome: String, planet_name: String, depth: float) -> Dictionary:
	var level := 1
	if depth > 6.0 or rng.randf() < 0.25:
		level = 2
	if depth > 14.0 or rng.randf() < 0.08:
		level = 3
	return {
		"id": "%X" % rng.randi_range(0x1000, 0xFFFF),
		"name": "Неизвестный минерал",
		"true_name": SAMPLE_PREFIX[rng.randi() % SAMPLE_PREFIX.size()] + SAMPLE_SUFFIX[rng.randi() % SAMPLE_SUFFIX.size()],
		"biome": biome,
		"planet": planet_name,
		"level": level,
		"studied": false,
		"value": 60 * level + rng.randi_range(0, 40),
	}


static func can_make(inv: Dictionary, need: Dictionary) -> bool:
	for id in need:
		if int(inv.get(id, 0)) < int(need[id]):
			return false
	return true


static func need_text(need: Dictionary) -> String:
	var parts := []
	for id in need:
		parts.append("%s ×%d" % [name_of(id), need[id]])
	return ", ".join(parts)
