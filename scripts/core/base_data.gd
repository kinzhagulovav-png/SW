class_name BaseData
extends RefCounted
## База на планете: модульные помещения и оборудование, энергия, износ, запчасти.
## Всё заказывается за ПОТОМ на научной станции и развитых колониях (уровень техники 3+)
## и прилетает на базу с доставкой. Для работы нужна энергия от электростанций.
## Оборудование изнашивается от работы: у каждого модуля свой срок эксплуатации (часы).
## Изношенное ломается. Чинят механик (нужна Техника и запчасти) или мастера с другой планеты.
##
## База: {"planet", "center": [x, z], "modules": [...], "store": {id: n}, "acc": {...},
##        "queue": [id частей], "job": {...}, "visit": {...}, "uid": счётчик}
## Модуль: {"uid", "id", "slot", "worn" (часы работы), "life" (срок), "broken"}

const FOUND_PRICE := 2500
const DELIVERY_FEE := 150

## kind: room — помещение, gen — электростанция, equip — оборудование.
## energy: плюс — выработка, минус — потребление (кВт). tier: сложность (1..3),
## от неё зависят требования к механику и цена мастеров.
const MODULES := {
	"core": {"name": "Командный модуль", "kind": "room", "tier": 1, "price": FOUND_PRICE, "energy": 6, "life": 6000, "store": 150,
		"desc": "Сердце базы: связь, небольшой склад и аварийные батареи. С него начинается база."},
	"habitat": {"name": "Жилой модуль", "kind": "room", "tier": 1, "price": 900, "energy": -4, "life": 5000,
		"desc": "Экипаж отдыхает: на базе быстрее восстанавливается здоровье. Нужен для мастерской."},
	"storage": {"name": "Складской модуль", "kind": "room", "tier": 1, "price": 600, "energy": -1, "life": 8000, "store": 300,
		"desc": "+300 ед. склада для добычи, материалов и запчастей."},
	"workshop": {"name": "Мастерская", "kind": "room", "tier": 2, "price": 1600, "energy": -12, "life": 3000,
		"desc": "Делает запчасти из материалов со склада. Нужен жилой модуль."},
	"solar": {"name": "Солнечная электростанция", "kind": "gen", "tier": 1, "price": 800, "energy": 16, "life": 2500,
		"desc": "Дешёвая энергия. На ледяных и ядовитых планетах света меньше."},
	"reactor": {"name": "Реакторная электростанция", "kind": "gen", "tier": 3, "price": 4200, "energy": 60, "life": 2000,
		"desc": "Много энергии где угодно. Сложна в ремонте."},
	"drill": {"name": "Буровая установка", "kind": "equip", "tier": 1, "price": 1400, "energy": -10, "life": 1500,
		"desc": "Сама добывает минералы планеты на склад. На пустых планетах бесполезна."},
	"refinery": {"name": "Перерабатывающий завод", "kind": "equip", "tier": 2, "price": 1900, "energy": -15, "life": 1800,
		"desc": "Сам перерабатывает минералы со склада в материалы."},
	"turret": {"name": "Оборонная турель", "kind": "equip", "tier": 2, "price": 1500, "energy": -6, "life": 2000,
		"desc": "Стреляет по налётчикам и защищает базу от армий."},
}

## Запчасти для каждого модуля: из чего их делает мастерская.
const PARTS := {
	"core": {"steel": 2, "wire": 1},
	"habitat": {"polymer": 2, "glass": 1},
	"storage": {"steel": 2},
	"workshop": {"steel": 1, "wire": 1, "alloy": 1},
	"solar": {"glass": 2, "wire": 1},
	"reactor": {"alloy": 1, "fuel_rod": 1, "conductor": 1},
	"drill": {"steel": 2, "alloy": 1},
	"refinery": {"steel": 1, "catalyst": 1},
	"turret": {"alloy": 1, "wire": 1, "cell": 1},
}
const PART_HOURS := 3.0     # сколько часов мастерская делает одну запчасть
const PART_MASS := 8.0
const DRILL_RATE := 0.15    # минералов в час
const REFINE_RATE := 0.25   # материалов в час


static func part_id(module_id: String) -> String:
	return "part_" + module_id


static func is_part(id: String) -> bool:
	return id.begins_with("part_") and MODULES.has(id.substr(5))


static func part_name(id: String) -> String:
	return "Запчасти: %s" % MODULES[id.substr(5)].name


static func part_price(id: String) -> int:
	var p := 0.0
	var need: Dictionary = PARTS[id.substr(5)]
	for k in need:
		p += Items.price_of(k) * int(need[k])
	return int(p * 1.6) + 20


## Солнце слабее на ледяных и ядовитых планетах.
static func sun(biome: String) -> float:
	return {"desert": 1.3, "ice": 0.6, "jungle": 1.0, "volcano": 0.9, "toxic": 0.55}.get(biome, 1.0)


static func cond(m: Dictionary) -> float:
	return clamp(100.0 * (1.0 - float(m.worn) / float(m.life)), 0.0, 100.0)


static func new_module(base: Dictionary, id: String) -> Dictionary:
	var slots: Array = base.modules.map(func(x): return int(x.slot))
	var slot := 0
	while slots.has(slot):
		slot += 1
	base.uid = int(base.uid) + 1
	var m := {"uid": int(base.uid), "id": id, "slot": slot, "worn": 0.0, "life": float(MODULES[id].life), "broken": false}
	base.modules.append(m)
	return m


static func new_base(planet: Dictionary, center: Vector2) -> Dictionary:
	var b := {"planet": planet.duplicate(), "center": [center.x, center.y], "modules": [], "store": {}, "acc": {"drill": 0.0, "refine": 0.0, "part": 0.0},
		"queue": [], "job": {}, "visit": {}, "uid": 0}
	new_module(b, "core")
	return b


## Где стоит модуль: кольца вокруг центра базы (в метрах от центра).
static func slot_offset(slot: int) -> Vector2:
	if slot == 0:
		return Vector2.ZERO
	var ring := 1
	var first := 1
	var count := 6
	while slot >= first + count:
		first += count
		ring += 1
		count = 6 * ring
	var a := TAU * float(slot - first) / float(count) + ring * 0.4
	return Vector2(cos(a), sin(a)) * (13.0 * ring)


static func working(m: Dictionary) -> bool:
	return not m.broken


## Выработка и потребление энергии базы.
static func energy(base: Dictionary) -> Dictionary:
	var made := 0.0
	var used := 0.0
	var s := sun(base.planet.biome)
	for m in base.modules:
		if not working(m):
			continue
		var e := float(MODULES[m.id].energy)
		if e > 0.0:
			made += e * (s if m.id == "solar" else 1.0)
		else:
			used -= e
	return {"made": made, "used": used, "ratio": 1.0 if used <= 0.0 else clamp(made / used, 0.0, 1.0)}


static func store_cap(base: Dictionary) -> int:
	var c := 0
	for m in base.modules:
		c += int(MODULES[m.id].get("store", 0))
	return c


static func store_used(base: Dictionary) -> int:
	var u := 0
	for k in base.store:
		u += int(base.store[k])
	return u


static func has_working(base: Dictionary, id: String) -> bool:
	for m in base.modules:
		if m.id == id and working(m):
			return true
	return false


static func count_working(base: Dictionary, id: String) -> int:
	var n := 0
	for m in base.modules:
		if m.id == id and working(m):
			n += 1
	return n


static func find(base: Dictionary, uid: int) -> Dictionary:
	for m in base.modules:
		if int(m.uid) == uid:
			return m
	return {}


static func store_add(base: Dictionary, id: String, n: int) -> void:
	base.store[id] = int(base.store.get(id, 0)) + n
	if int(base.store[id]) <= 0:
		base.store.erase(id)


## Где делают модули: станция всё, развитая колония (техника 3+) — до своего уровня.
static func sold_here(id: String, tech: int) -> bool:
	return tech >= 3 and int(MODULES[id].tier) <= tech - 1 and id != "core"


static func masters_price(id: String) -> int:
	return 300 + 150 * int(MODULES[id].tier)


## Какой Техники нужно механику для ремонта.
static func mech_need(id: String) -> int:
	return 2 * int(MODULES[id].tier)


static func status_text(m: Dictionary) -> String:
	if m.broken:
		return "СЛОМАН"
	return "износ %d%%" % int(100.0 - cond(m))
