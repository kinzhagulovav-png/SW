class_name Biomes
extends RefCounted
## Описание биомов планет: цвета для вида из космоса и для поверхности.
## Цвета задаются как на экране (sRGB), Godot сам переводит их в линейные.

const DATA := {
	"desert": {
		"name": "Пустыня", "atmo": Color("#ffb070"), "cloud": Color(1, 0.94, 0.86),
		"stops": [[0.0, "#5a321c"], [0.4, "#a8622e"], [0.6, "#d39a5a"], [0.85, "#e9c58c"], [1.0, "#f5e2b8"]],
		"sky_top": Color("#3f7fc8"), "sky_hor": Color("#f2c48e"), "sun": Color("#fff1d6"),
		"low": Color("#8a5230"), "high": Color("#d8a467"), "grass": Color("#d08a2a"), "rock": Color("#7a5038"),
		"amp": 18.0, "water": {}, "flora": "pillars", "creature": Color("#c8a070"),
		"grass_h": 1.0, "grass_cover": 0.9, "danger": 1.0,
	},
	"ice": {
		"name": "Ледяной мир", "atmo": Color("#9fd0ff"), "cloud": Color(1, 1, 1),
		"stops": [[0.0, "#20406a"], [0.45, "#4e7fb2"], [0.55, "#bcd6ee"], [1.0, "#ffffff"]],
		"sky_top": Color("#3d6fb8"), "sky_hor": Color("#d8e8f6"), "sun": Color("#ffffff"),
		"low": Color("#8098b8"), "high": Color("#dce6f2"), "grass": Color("#bcd8e8"), "rock": Color("#5a6a80"),
		"amp": 26.0, "water": {"level": -12.0, "color": Color("#8fc2e6"), "ice": true}, "flora": "spikes", "creature": Color("#e8eef8"),
		"grass_h": 0.5, "grass_cover": 0.35, "danger": 0.6,
	},
	"jungle": {
		"name": "Джунгли", "atmo": Color("#7fd0ff"), "cloud": Color(1, 1, 1),
		"stops": [[0.0, "#0a2848"], [0.47, "#1a5a88"], [0.5, "#2d6a30"], [0.7, "#3e8a34"], [0.88, "#6a7a40"], [1.0, "#9a9a70"]],
		"sky_top": Color("#2f7fd0"), "sky_hor": Color("#b8e6d8"), "sun": Color("#fff8e0"),
		"low": Color("#2f4a22"), "high": Color("#5a7a34"), "grass": Color("#4fa82a"), "rock": Color("#4a4a44"),
		"amp": 20.0, "water": {"level": -7.0, "color": Color("#1d6a8a")}, "flora": "trees", "creature": Color("#8a5ab0"),
		"grass_h": 1.3, "grass_cover": 1.0, "danger": 1.4,
	},
	"volcano": {
		"name": "Вулканический", "atmo": Color("#ff6a30"), "cloud": Color(0.28, 0.24, 0.24),
		"stops": [[0.0, "#ff7a1a"], [0.3, "#a0280a"], [0.42, "#2a1612"], [0.8, "#3e302c"], [1.0, "#5a4a44"]],
		"sky_top": Color("#1e0a08"), "sky_hor": Color("#a04a22"), "sun": Color("#ffb070"),
		"low": Color("#2a2220"), "high": Color("#4a3a34"), "grass": Color("#5a2a14"), "rock": Color("#1e1a1a"),
		"amp": 30.0, "water": {"level": -9.0, "color": Color("#ff5a10"), "lava": true}, "flora": "basalt", "creature": Color("#3a2a2a"),
		"grass_h": 0.5, "grass_cover": 0.25, "danger": 1.6,
	},
	"toxic": {
		"name": "Токсичный", "atmo": Color("#c8f060"), "cloud": Color(0.86, 0.94, 0.55),
		"stops": [[0.0, "#2a3a08"], [0.45, "#6a8a1a"], [0.6, "#a6c03a"], [0.8, "#d8e070"], [1.0, "#f0f4b0"]],
		"sky_top": Color("#5a7a1a"), "sky_hor": Color("#d8e07a"), "sun": Color("#f8ffd0"),
		"low": Color("#4a5418"), "high": Color("#8a9a30"), "grass": Color("#9ac81e"), "rock": Color("#4a4a30"),
		"amp": 14.0, "water": {"level": -5.0, "color": Color("#7aa018")}, "flora": "shrooms", "creature": Color("#d06a9a"),
		"grass_h": 1.1, "grass_cover": 0.8, "danger": 1.2,
	},
}


## Фон радиации по биомам (мЗв/ч, условно). У каждой планеты он ещё умножается на 0,6–1,6.
const RAD_BASE := {"desert": 1.0, "ice": 0.6, "jungle": 0.35, "volcano": 1.9, "toxic": 2.6}
## Расход кислорода: в джунглях атмосфера частично пригодна, фильтры тратят меньше.
const O2_USE := {"desert": 1.0, "ice": 1.0, "jungle": 0.5, "volcano": 1.3, "toxic": 1.2}


const RACES := ["Люди", "Империя Аркос", "Орден Эфира", "Конклав синтетов", "Рой Кхарр", "Нокты"]


## Постоянные свойства конкретной планеты по её сиду: радиация и какие минералы в недрах.
## Примерно каждая седьмая планета пустая: минералов нет совсем.
static func profile(planet: Dictionary) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = int(planet.seed) + 9157
	var biome: String = planet.biome
	var minerals: Array[String] = []
	if r.randf() > 0.15:
		var want := r.randi_range(2, 5)
		var tries := 0
		while minerals.size() < want and tries < 60:
			tries += 1
			var id := Items.roll_mineral(r, biome, r.randf_range(0.0, 8.0))
			if id != "" and not minerals.has(id):
				minerals.append(id)
	var rad := float(RAD_BASE[biome]) * r.randf_range(0.6, 1.6)
	# Заселённые планеты: колония с рынком (покупка и продажа оборудования и ресурсов).
	var colony := {}
	if rad < 2.6 and r.randf() < 0.4:
		colony = {
			"race": RACES[r.randi() % RACES.size()],
			"tech": r.randi_range(1, 4),
			"prices": r.randf_range(0.85, 1.25),
		}
	return {
		"rad": rad,
		"colony": colony,
		"o2": float(O2_USE[biome]),
		"minerals": minerals,
	}


static func rad_text(rad: float) -> String:
	var word := "низкий"
	if rad > 2.5:
		word = "смертельный"
	elif rad > 1.6:
		word = "высокий"
	elif rad > 0.8:
		word = "средний"
	return "%.1f мЗв/ч (%s)" % [rad, word]
