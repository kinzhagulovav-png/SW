class_name PlanetRadar
extends Control
## Круглый радар на поверхности планеты. Верх радара: куда смотрит игрок.
## Корабль: жёлтый значок (за пределами дальности прижимается к краю стрелкой),
## животные: красные точки, ресурсы: голубые и зелёные.

const RANGE := 70.0
const RADIUS := 105.0

var surface: Node3D  # сцена планеты: player, yaw, ship, items, beasts
var _sweep := 0.0
var _font: Font


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0 + 20.0, RADIUS * 2.0 + 44.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_sweep = fmod(_sweep + delta * 1.6, TAU)
	queue_redraw()


func _to_radar(world: Vector3) -> Vector2:
	var p: Vector3 = surface.player.position
	var yaw: float = surface.yaw
	var vx := world.x - p.x
	var vz := world.z - p.z
	var right := vx * cos(yaw) - vz * sin(yaw)
	var fwd := -vx * sin(yaw) - vz * cos(yaw)
	return Vector2(right, -fwd) * (RADIUS / RANGE)


func _draw() -> void:
	if surface == null or surface.player == null:
		return
	var c := Vector2(RADIUS + 10.0, RADIUS + 10.0)
	draw_circle(c, RADIUS + 4.0, Color(0.03, 0.08, 0.16, 0.8))
	draw_arc(c, RADIUS + 4.0, 0, TAU, 96, Color("#4a78bc"), 2.0, true)
	for k in [0.33, 0.66]:
		draw_arc(c, RADIUS * k, 0, TAU, 64, Color(0.4, 0.7, 1.0, 0.18), 1.0, true)
	draw_line(c + Vector2(-RADIUS, 0), c + Vector2(RADIUS, 0), Color(0.4, 0.7, 1.0, 0.12))
	draw_line(c + Vector2(0, -RADIUS), c + Vector2(0, RADIUS), Color(0.4, 0.7, 1.0, 0.12))
	# Бегущий луч радара со шлейфом.
	for i in 14:
		var a := _sweep - i * 0.045
		var tip := c + Vector2(cos(a), sin(a)) * RADIUS
		draw_line(c, tip, Color(0.43, 0.86, 1.0, 0.22 * (1.0 - i / 14.0)), 2.0)

	# Север: буква «С» на ободке.
	var n: Vector2 = _to_radar(surface.player.position + Vector3(0, 0, -1000)).normalized() * (RADIUS - 10.0)
	draw_string(_font, c + n + Vector2(-6, 7), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.85, 1.0, 0.8))

	for it in surface.items:
		var r: Vector2 = _to_radar(it.node.global_position)
		if r.length() < RADIUS:
			var col := Color("#5fe0ff") if it.type == "ore" else Color("#9aff6a")
			draw_circle(c + r, 2.5, col)
	for b in surface.beasts:
		var r: Vector2 = _to_radar(b.node.global_position)
		if r.length() < RADIUS:
			draw_circle(c + r, 4.0, Color("#ff4a3a"))

	# Игрок в центре: стрелка вверх.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 7), c + Vector2(-6, 7)]), Color("#6fdcff"))
	# Корабль (рисуем поверх игрока, он важнее).
	var s: Vector2 = _to_radar(surface.ship.global_position)
	var gold := Color("#ffbf55")
	if s.length() < RADIUS - 8.0:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.15
		draw_circle(c + s, 13.0 * pulse, Color(1.0, 0.75, 0.33, 0.25))
		var pts := PackedVector2Array([c + s + Vector2(0, -11), c + s + Vector2(8, 8), c + s + Vector2(0, 4), c + s + Vector2(-8, 8)])
		draw_colored_polygon(pts, gold)
	else:
		var d := s.normalized()
		var e := c + d * (RADIUS - 6.0)
		var side := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([e + d * 9.0, e - d * 5.0 + side * 7.0, e - d * 5.0 - side * 7.0]), gold)

	var dist: float = surface.player.position.distance_to(surface.ship.position)
	var text := "Корабль: %d м" % int(dist)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(_font, Vector2(c.x - w / 2.0, RADIUS * 2.0 + 38.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, gold)
