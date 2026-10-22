extends Node
## Глобальное состояние игры (автозагрузка GameState).
## Время в галактике идёт всегда, в том числе во время боёв и высадок:
## 1 секунда реального времени = 1 час игрового.

signal hour_passed(hour: int)

const HOURS_PER_SECOND := 1.0

var hours: float = 8.0
var money: int = 700 ## валюта «ПОТОМ»
var cargo := {"ore": 0, "samples": 0}
var galaxy_seed: int = 0
## Планета, на которую высаживаемся: {"name", "biome", "seed"}.
var current_planet: Dictionary = {}
## Где был корабль в системе перед высадкой, чтобы вернуть его туда же.
var system_state: Dictionary = {}

var _last_hour: int = 8


func _ready() -> void:
	randomize()
	galaxy_seed = randi()


func _process(delta: float) -> void:
	hours += delta * HOURS_PER_SECOND
	while int(hours) > _last_hour:
		_last_hour += 1
		hour_passed.emit(_last_hour)


func time_text() -> String:
	var day := int(hours / 24.0) + 1
	return "День %d, %02d:00" % [day, int(hours) % 24]
