class_name ShipData
extends RefCounted
## Корабли как в духе классических космических рейнджеров, но со своими названиями.
## Корпус задаёт класс: вместимость (ед. объёма, общая для оборудования и груза),
## грузоподъёмность (максимальная масса груза и оборудования, с которой корабль взлетает),
## места для экипажа и нужен ли второй пилот.
## Оборудование ставится в слоты, у каждого предмета есть уровень Мк-1…4 и износ.
## Купить и продать его можно на станциях и заселённых планетах, корпус — только на верфи станции.

const HULLS := {
	"skif": {"name": "Скиф", "kind": "Разведчик", "capacity": 220, "lift": 700, "crew": 2, "copilot": false, "price": 1500, "speed": 1.15, "scale": 0.75},
	"mul": {"name": "Мул", "kind": "Транспорт", "capacity": 620, "lift": 1900, "crew": 3, "copilot": false, "price": 5200, "speed": 0.8, "scale": 1.0},
	"sokol": {"name": "Сокол", "kind": "Корвет", "capacity": 400, "lift": 1100, "crew": 4, "copilot": true, "price": 7800, "speed": 1.3, "scale": 0.9},
	"bastion": {"name": "Бастион", "kind": "Фрегат", "capacity": 760, "lift": 2600, "crew": 6, "copilot": true, "price": 14500, "speed": 1.0, "scale": 1.2},
	"leviafan": {"name": "Левиафан", "kind": "Крейсер", "capacity": 1150, "lift": 4200, "crew": 8, "copilot": true, "price": 26000, "speed": 0.9, "scale": 1.5},
}

## Слоты оборудования. size и mass растут с уровнем Мк, base — цена Мк-1.
const EQUIP := {
	"engine": {"name": "Двигатель", "size": [30, 38, 46, 54], "base": 600,
		"desc": "Скорость в системе и прибавка к грузоподъёмности."},
	"tank": {"name": "Топливный бак", "size": [20, 26, 32, 40], "base": 300,
		"desc": "Запас топлива. Посадка и взлёт стоят по %d ед." % 8},
	"radar": {"name": "Радар", "size": [10, 14, 18, 22], "base": 350,
		"desc": "Дальность радара на планете."},
	"scanner": {"name": "Сканер", "size": [12, 16, 20, 24], "base": 450,
		"desc": "С орбиты: Мк-1 минералы, Мк-2 и жизнь, Мк-3 точный фон радиации."},
	"droid": {"name": "Ремдроид", "size": [20, 24, 28, 32], "base": 500,
		"desc": "Ускоряет ремонт скафандра в отсеке ремонта."},
	"shield": {"name": "Генератор защиты", "size": [25, 32, 40, 48], "base": 700,
		"desc": "Снижает урон кораблю в бою (бои появятся позже)."},
}
const MK := ["Мк-1", "Мк-2", "Мк-3", "Мк-4"]
const LAND_FUEL := 8.0
const FUEL_PRICE := 3

## Объём, который занимает в трюме единица предмета.
const CARGO_VOLUME := {"mineral": 1, "material": 1, "basic": 2, "device": 4, "sample": 2, "part": 3}
## Прочность корпуса по классу: её снимают атаки армий во время войны.
const ARMOR := {"skif": 120, "mul": 200, "sokol": 180, "bastion": 320, "leviafan": 500}
const HULL_REPAIR_PRICE := 4  # ПОТОМ за единицу прочности


static func size_of(e: Dictionary) -> int:
	return int(EQUIP[e.id].size[int(e.mk) - 1])


static func mass_of(e: Dictionary) -> float:
	return size_of(e) * 2.0


## Эффект предмета по уровню и износу (изношенный работает хуже).
static func power(e: Dictionary) -> float:
	return float(e.mk) * (0.5 + 0.5 * float(e.cond) / 100.0)


static func price(e: Dictionary) -> int:
	var mk := int(e.mk)
	return int(float(EQUIP[e.id].base) * pow(mk, 1.6) * (0.3 + 0.7 * float(e.cond) / 100.0))


static func title(e: Dictionary) -> String:
	return "%s %s (%d%%)" % [EQUIP[e.id].name, MK[int(e.mk) - 1], int(e.cond)]


static func effect_text(e: Dictionary) -> String:
	var p := power(e)
	match e.id:
		"engine":
			return "скорость %d, +%d кг к подъёму" % [int(engine_speed(e)), int(engine_lift(e))]
		"tank":
			return "%d ед. топлива" % int(tank_size(e))
		"radar":
			return "дальность %d м" % int(radar_range(e))
		"scanner":
			return ["минералы с орбиты", "минералы и жизнь с орбиты", "минералы, жизнь, точная радиация", "всё о планете с орбиты"][int(e.mk) - 1]
		"droid":
			return "ремонт скафандра ×%.1f" % (1.0 + p * 0.5)
		"shield":
			return "защита %d%%" % int(p * 6.0)
	return ""


static func engine_speed(e: Dictionary) -> float:
	return 22.0 + power(e) * 8.0


static func engine_lift(e: Dictionary) -> float:
	return power(e) * 120.0


static func tank_size(e: Dictionary) -> float:
	return 30.0 + power(e) * 25.0


static func radar_range(e: Dictionary) -> float:
	return 50.0 + power(e) * 25.0


## Ассортимент магазина. Зависит от места и дня, поэтому каждый день новый.
## tech: 1..4, насколько развито место (выше — чаще хорошие уровни Мк).
static func shop_stock(key: String, day: int, tech: int) -> Array[Dictionary]:
	var r := RandomNumberGenerator.new()
	r.seed = hash(key) + day * 7919
	var out: Array[Dictionary] = []
	var ids := EQUIP.keys()
	for i in r.randi_range(5, 8):
		var mk := clampi(r.randi_range(1, tech) + (1 if r.randf() < 0.15 else 0), 1, 4)
		var e := {"id": ids[r.randi() % ids.size()], "mk": mk, "cond": r.randi_range(70, 100)}
		e["cost"] = int(price(e) * r.randf_range(0.9, 1.25))
		out.append(e)
	return out


## Сколько место даёт за ваш предмет (дешевле, чем продаёт).
static func buyback(e: Dictionary) -> int:
	return int(price(e) * 0.55)
