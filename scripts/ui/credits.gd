extends Control
## Конец игры: капитан погиб. Титры во славу исследователя космических просторов.
## Пробел или Enter ускоряют титры, в конце можно начать новую игру.

const SPEED := 46.0

var _roll: VBoxContainer
var _stars: Array[Vector3] = []
var _fast := false
var _done := false


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 260:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.3, 1.0)))
	var theme := Theme.new()
	theme.default_font_size = 24
	self.theme = theme

	_roll = VBoxContainer.new()
	_roll.alignment = BoxContainer.ALIGNMENT_BEGIN
	_roll.add_theme_constant_override("separation", 14)
	add_child(_roll)

	var d: Dictionary = GameState.death
	var s: Dictionary = GameState.stats
	var studied := 0
	for smp in GameState.samples:
		if smp.studied:
			studied += 1
	_line("Капитан погиб", 30, Color("#ff8a6a"))
	if not d.is_empty():
		_line("на планете %s (%s)" % [d.planet, d.biome], 22, Color(0.8, 0.82, 0.9))
	_gap(60)
	_line("ВО СЛАВУ", 44, Color("#ffbf55"))
	_line("ИССЛЕДОВАТЕЛЯ КОСМИЧЕСКИХ ПРОСТОРОВ", 44, Color("#ffbf55"))
	_gap(30)
	for t in ["Он шёл туда, где не ступала нога человека.",
			"Он копал недра чужих миров и не боялся их обитателей.",
			"Звёзды запомнят его имя.",
			"А те, кто придёт следом, найдут его следы на далёких планетах."]:
		_line(t, 24, Color(0.85, 0.88, 0.95))
	_gap(70)
	_line("Путь капитана", 30, Color("#6fdcff"))
	_gap(6)
	for row in [
			["Дней в странствиях", str(int(GameState.hours / 24.0) + 1)],
			["Высадок на планеты", str(s.landings)],
			["Добыто минералов", str(s.minerals)],
			["Найдено образцов", str(s.samples)],
			["Изучено в лаборатории", str(studied)],
			["Раскопок лапатроном", str(s.dug)],
			["Побеждено животных", str(s.beasts)],
			["Осталось ПОТОМ", str(GameState.money)]]:
		_line("%s:  %s" % row, 24, Color(0.9, 0.92, 1.0))
	_gap(90)
	_line("СТРАННИКИ ГАЛАКТИКИ", 40, Color("#ffbf55"))
	_gap(30)
	for pair in [["Идея и геймдизайн", "Ustefs"], ["Программирование и процедурный мир", "Claude"],
			["Движок", "Godot Engine"], ["Вдохновение", "любовь к космосу и к старым добрым играм про него"]]:
		_line(pair[0], 22, Color(0.6, 0.66, 0.8))
		_line(pair[1], 28, Color(0.95, 0.96, 1.0))
		_gap(18)
	_gap(80)
	_line("Галактика ждёт нового странника.", 28, Color("#6fdcff"))
	_gap(20)
	var btn := Button.new()
	btn.text = "   Новая игра   "
	btn.add_theme_font_size_override("font_size", 28)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_new_game)
	_roll.add_child(btn)

	await get_tree().process_frame
	_roll.size.x = size.x
	_roll.position = Vector2(0, size.y)


func _line(text: String, font_size: int, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	_roll.add_child(l)


func _gap(h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size.y = h
	_roll.add_child(c)


func _process(delta: float) -> void:
	queue_redraw()
	if _done:
		return
	_roll.size.x = size.x
	_roll.position.y -= SPEED * delta * (5.0 if _fast else 1.0)
	# Останавливаемся, когда кнопка «Новая игра» в середине экрана.
	if _roll.position.y + _roll.size.y < size.y * 0.5 + 40.0:
		_done = true


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#02040a"))
	var t := Time.get_ticks_msec() * 0.001
	for s in _stars:
		var p := Vector2(fmod(s.x + t * 0.004 * s.z, 1.0) * size.x, s.y * size.y)
		var a := 0.45 + 0.4 * sin(t * 2.0 * s.z + s.x * 40.0)
		draw_circle(p, 1.4 * s.z, Color(0.85, 0.9, 1.0, a * s.z))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_fast = event.pressed
		elif event.pressed and event.keycode == KEY_ESCAPE:
			_new_game()


func _new_game() -> void:
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/system/star_system.tscn")
