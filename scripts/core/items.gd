class_name Items
extends RefCounted
## Справочник предметов и цепочка производства:
## минералы (реальные элементы) → материалы (переработка на корабле)
## → базовые элементы (сборка из материалов на корабле)
## → приборы, вещи, еда, вода (только на научной станции и за ПОТОМ).
## Неизвестные образцы изучаются в лаборатории корабля, если в экипаже есть учёный.

## depth: на какой глубине (м) минерал начинает встречаться в недрах; weight: насколько часто.
const MINERALS := {
	"fe": {"name": "Железо", "sym": "Fe", "color": Color("#8a8f99"), "depth": 0.0, "weight": 10.0, "price": 4, "mass": 8},
	"cu": {"name": "Медь", "sym": "Cu", "color": Color("#d07a40"), "depth": 0.0, "weight": 7.0, "price": 6, "mass": 9},
	"si": {"name": "Кремний", "sym": "Si", "color": Color("#7a8aa8"), "depth": 0.0, "weight": 8.0, "price": 4, "mass": 3},
	"c": {"name": "Углерод", "sym": "C", "color": Color("#3a3a40"), "depth": 0.0, "weight": 8.0, "price": 3, "mass": 2},
	"al": {"name": "Алюминий", "sym": "Al", "color": Color("#d0d4dc"), "depth": 1.0, "weight": 6.0, "price": 6, "mass": 3},
	"s": {"name": "Сера", "sym": "S", "color": Color("#e8d040"), "depth": 0.0, "weight": 5.0, "price": 5, "mass": 2},
	"h2o": {"name": "Водяной лёд", "sym": "H₂O", "color": Color("#a8d8ff"), "depth": 0.0, "weight": 5.0, "price": 2, "mass": 1},
	"ni": {"name": "Никель", "sym": "Ni", "color": Color("#b8b890"), "depth": 2.0, "weight": 4.0, "price": 9, "mass": 9},
	"li": {"name": "Литий", "sym": "Li", "color": Color("#e8f0ff"), "depth": 2.0, "weight": 3.0, "price": 12, "mass": 1},
	"ti": {"name": "Титан", "sym": "Ti", "color": Color("#9ab0c8"), "depth": 3.0, "weight": 3.0, "price": 14, "mass": 5},
	"au": {"name": "Золото", "sym": "Au", "color": Color("#ffcc33"), "depth": 5.0, "weight": 1.5, "price": 40, "mass": 19},
	"pt": {"name": "Платина", "sym": "Pt", "color": Color("#eceef2"), "depth": 6.0, "weight": 1.0, "price": 55, "mass": 21},
	"u": {"name": "Уран", "sym": "U", "color": Color("#6aff4a"), "depth": 7.0, "weight": 1.0, "price": 60, "mass": 19},
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
	"o2_can": {"name": "Кислородный баллон", "need": {"water_pack": 1, "frame": 1}, "price": 50,
		"desc": "Срабатывает сам, когда кислород кончился: +60 кислорода."},
	"antirad": {"name": "Антирад", "need": {"medgel": 1, "power": 1}, "price": 90,
		"desc": "Срабатывает сам, когда радзащита кончилась: +50 защиты."},
	"armor_patch": {"name": "Броневая заплата", "need": {"frame": 1, "fabric": 1}, "price": 70,
		"desc": "Срабатывает сама, когда броня разбита: +50 брони."},
}

## Масса единицы минерала в кг задана в MINERALS.mass; образец весит SAMPLE_MASS.
## В рюкзаке единица минерала занимает 1 ячейку объёма, образец — SAMPLE_VOLUME.
const SAMPLE_MASS := 5.0
const SAMPLE_VOLUME := 2
const DEVICE_MASS := 6.0

const SAMPLE_PREFIX := ["Кри", "Ноа", "Вел", "Ор", "Зен", "Тал", "Ир", "Ксо", "Мер", "Аль"]
const SAMPLE_SUFFIX := ["ит", "оксид", "ан", "иний", "оль", "ид", "ен"]


static func name_of(id: String) -> String:
	for table in [MINERALS, MATERIALS, BASICS, DEVICES]:
		if table.has(id):
			return table[id].name
	return id


## Случайный минерал для биома с учётом глубины копания.
## Случайный минерал с учётом глубины копания. allowed: какие минералы вообще есть на планете,
## prefer: минерал этой жилы (встречается в 4 раза чаще). Пустая строка, если подходящих нет.
static func roll_mineral(rng: RandomNumberGenerator, biome: String, depth: float, allowed: Array = [], prefer: String = "") -> String:
	var bias: Dictionary = BIOME_BIAS.get(biome, {})
	var total := 0.0
	var weights := {}
	for id in MINERALS:
		if not allowed.is_empty() and not allowed.has(id):
			continue
		var m: Dictionary = MINERALS[id]
		if depth < float(m.depth):
			continue
		# Глубже редкие минералы встречаются чаще.
		var w: float = float(m.weight) * float(bias.get(id, 1.0)) * (1.0 + depth * float(m.depth) * 0.05)
		if id == prefer:
			w *= 4.0
		if w <= 0.0:
			continue
		weights[id] = w
		total += w
	if total <= 0.0:
		return ""
	var r := rng.randf() * total
	for id in weights:
		r -= weights[id]
		if r <= 0.0:
			return id
	return weights.keys()[0]


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


## Масса предмета: у материалов и базовых элементов — сумма ингредиентов.
static func mass_of(id: String) -> float:
	if MINERALS.has(id):
		return float(MINERALS[id].mass)
	for table in [MATERIALS, BASICS]:
		if table.has(id):
			var m := 0.0
			for k in table[id].need:
				m += mass_of(k) * int(table[id].need[k])
			return m
	return DEVICE_MASS


## Базовая цена предмета в ПОТОМ: переработанное дороже сырья.
static func price_of(id: String) -> int:
	if MINERALS.has(id):
		return int(MINERALS[id].price)
	if DEVICES.has(id):
		return int(DEVICES[id].price)
	for pair in [[MATERIALS, 1.3], [BASICS, 1.5]]:
		if pair[0].has(id):
			var p := 0.0
			for k in pair[0][id].need:
				p += price_of(k) * int(pair[0][id].need[k])
			return int(p * pair[1])
	return 1
