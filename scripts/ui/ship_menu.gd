class_name ShipMenu
extends PanelContainer
## Окно корабля и научной станции.
## На корабле: трюм, переработка минералов в материалы, сборка базовых элементов, лаборатория.
## На научной станции: приборы и вещи за ПОТОМ, наём учёного, продажа изученных образцов.

const SCIENTIST_PRICE := 300
const NAMES := ["Ирма Вейс", "Тарос Кейн", "Лия Орлова", "Дорн Салех", "Мика Ито", "Ярослав Нейман", "Ава Корр"]

var mode := "ship"
var _tabs: TabContainer
var _title: Label
var _status: Label
var _tab_index := 0
var _rebuilding := false


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.12, 0.24, 0.96)
	style.border_color = Color("#4a78bc")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(980, 640)
	visible = false

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = Label.new()
	_title.add_theme_color_override("font_color", Color("#ffbf55"))
	_title.add_theme_font_size_override("font_size", 26)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "  Закрыть (Esc)  "
	close.pressed.connect(hide)
	head.add_child(close)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(i): if not _rebuilding: _tab_index = i)
	col.add_child(_tabs)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("#9ad8ff"))
	col.add_child(_status)
	GameState.lab_finished.connect(func(s): if visible: _status.text = "Лаборатория: изучен образец %s — это %s!" % [s.id, s.name]; refresh())


func open(new_mode: String) -> void:
	if mode != new_mode:
		_tab_index = 0
	mode = new_mode
	_status.text = ""
	visible = true
	refresh()
	# Окно всегда по центру экрана.
	size = custom_minimum_size
	position = (get_viewport_rect().size - size) / 2.0


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	var want := _tab_index
	_rebuilding = true
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	if mode == "ship":
		_title.text = "Корабль · ПОТОМ: %d" % GameState.money
		_page("Трюм", _fill_hold)
		_page("Переработка", func(box): _fill_recipes(box, Items.MATERIALS, "Переработать", 0))
		_page("Сборка", func(box): _fill_recipes(box, Items.BASICS, "Собрать", 0))
		_page("Лаборатория", _fill_lab)
	elif mode == "lab":
		var sci := GameState.best_scientist()
		_title.text = "Научный отсек · %s" % ("учёный %s" % sci.name if not sci.is_empty() else "учёного нет")
		_page("Переработка", func(box): _fill_recipes(box, Items.MATERIALS, "Переработать", 0))
		_page("Сборка", func(box): _fill_recipes(box, Items.BASICS, "Собрать", 0))
		_page("Образцы", _fill_lab)
		_page("Трюм", _fill_hold)
	else:
		_title.text = "Научная станция · ПОТОМ: %d" % GameState.money
		_page("Приборы и вещи", func(box): _fill_recipes(box, Items.DEVICES, "Изготовить", 1))
		_page("Экипаж", _fill_crew)
		_page("Образцы", _fill_sell)
		_page("Трюм", _fill_hold)
	_tabs.current_tab = clampi(want, 0, _tabs.get_tab_count() - 1)
	_tab_index = _tabs.current_tab
	_rebuilding = false


func _page(title: String, filler: Callable) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	_tabs.add_child(scroll)
	filler.call(box)


func _label(box: Control, text: String, col: Color = Color(0.9, 0.92, 1.0), size: int = 20) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(l)
	return l


func _row(box: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	box.add_child(r)
	return r


func _button(row: Control, text: String, enabled: bool, action: Callable) -> void:
	var b := Button.new()
	b.text = "  %s  " % text
	b.disabled = not enabled
	b.pressed.connect(action)
	row.add_child(b)


# ---------- Трюм ----------

func _fill_hold(box: VBoxContainer) -> void:
	var over := GameState.overloaded()
	_label(box, "Груз: %d из %d кг (предел взлётной массы корабля)%s" % [GameState.cargo_mass(), GameState.SHIP_MAX_CARGO,
		".  ПЕРЕГРУЗ: корабль не взлетит!" if over else ""], Color("#ff6a4a") if over else Color("#ffbf55"), 20)
	var su: Dictionary = GameState.suit
	_label(box, "Скафандр: кислород %d%%, радзащита %d%%, броня %d%%.  Здоровье: %d.  Радзащиту и броню чинит отсек ремонта на корабле во время высадки." % [su.oxygen, su.rad, su.armor, GameState.health], Color("#d0e040"), 18)
	var groups := [["Минералы", Items.MINERALS], ["Материалы", Items.MATERIALS], ["Базовые элементы", Items.BASICS], ["Приборы и вещи", Items.DEVICES]]
	var empty := true
	for g in groups:
		var lines := []
		for id in g[1]:
			var c := GameState.count(id)
			if c > 0:
				var extra: String = " (%s)" % g[1][id].sym if g[1][id].has("sym") else ""
				lines.append([id, "%s%s: %d  ·  %d кг" % [g[1][id].name, extra, c, Items.mass_of(id) * c]])
		if lines.is_empty():
			continue
		empty = false
		_label(box, g[0], Color("#6fdcff"), 22)
		for ln in lines:
			var row := _row(box)
			_label(row, "    " + ln[1], Color(0.9, 0.92, 1.0), 19)
			if mode != "station":
				var item_id: String = ln[0]
				_button(row, "Выбросить 1", true, func():
					GameState.add_item(item_id, -1)
					refresh())
				_button(row, "Все", true, func():
					GameState.add_item(item_id, -GameState.count(item_id))
					refresh())
	if empty:
		_label(box, "Трюм пуст. Высаживайтесь на планеты и добывайте минералы лапатроном.", Color(0.7, 0.75, 0.85))
	_label(box, "Неизученных образцов: %d" % GameState.samples.filter(func(s): return not s.studied).size(), Color("#9aff6a"))


# ---------- Рецепты: переработка, сборка, приборы ----------

func _fill_recipes(box: VBoxContainer, table: Dictionary, verb: String, price_mode: int) -> void:
	if mode != "station":
		_label(box, "Минералы → материалы → базовые элементы. Приборы и вещи из базовых элементов делают только на научной станции.", Color(0.7, 0.75, 0.85), 18)
	else:
		_label(box, "Станция изготовит прибор из ваших базовых элементов за плату в ПОТОМ.", Color(0.7, 0.75, 0.85), 18)
	for id in table:
		var r: Dictionary = table[id]
		var price: int = int(r.get("price", 0)) if price_mode == 1 else 0
		var ok := Items.can_make(GameState.inventory, r.need) and GameState.money >= price
		var row := _row(box)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var have := GameState.count(id)
		_label(info, "%s%s" % [r.name, "  (есть: %d)" % have if have > 0 else ""], Color("#ffbf55") if ok else Color(0.9, 0.92, 1.0), 21)
		var need_line := "Нужно: " + Items.need_text(r.need)
		if price > 0:
			need_line += "  ·  %d ПОТОМ" % price
		_label(info, need_line, Color(0.75, 0.8, 0.9), 17)
		if r.has("desc"):
			_label(info, r.desc, Color(0.6, 0.68, 0.8), 16)
		_button(row, verb, ok, func():
			if GameState.craft(id, r.need, price):
				_status.text = "Готово: %s" % r.name
			refresh())


# ---------- Лаборатория ----------

func _fill_lab(box: VBoxContainer) -> void:
	var sci := GameState.best_scientist()
	if sci.is_empty():
		_label(box, "В экипаже нет учёного. Нанять его можно на научной станции.", Color("#ff8a6a"))
	else:
		_label(box, "Учёный: %s, навык %d.  Наука капитана: %d." % [sci.name, sci.skill, GameState.skills.science], Color("#9ad8ff"))
	if not GameState.lab.is_empty():
		var left: float = float(GameState.lab.done_at) - GameState.hours
		_label(box, "Идёт изучение образца %s, осталось ~%d ч." % [GameState.lab.sample, ceili(left)], Color("#ffbf55"))
	if GameState.samples.is_empty():
		_label(box, "Образцов нет. Их находят на планетах: светящиеся растения, глубокие раскопки, добыча с животных.", Color(0.7, 0.75, 0.85))
	for s in GameState.samples:
		var row := _row(box)
		var t := "Образец %s · %s · сложность %d · с планеты %s" % [s.id, s.name, s.level, s.planet]
		_label(row, t, Color("#9aff6a") if s.studied else Color(0.9, 0.92, 1.0), 19)
		if not s.studied:
			var why := GameState.study_problem(s)
			if why == "":
				_button(row, "Изучить (%d ч)" % int(GameState.HOURS_PER_STUDY_LEVEL * s.level), true, func():
					GameState.start_study(s)
					_status.text = "Образец %s в лаборатории. Время в галактике идёт." % s.id
					refresh())
			else:
				_label(box, "    Нельзя изучить: " + why, Color("#ff8a6a"), 16)


# ---------- Станция: экипаж и продажа ----------

func _fill_crew(box: VBoxContainer) -> void:
	_label(box, "Учёный изучает неизвестные образцы в лаборатории корабля. Чем выше его навык, тем сложнее образцы ему по силам.", Color(0.7, 0.75, 0.85), 18)
	for c in GameState.crew:
		_label(box, "%s · %s · навык %d" % [c.name, c.role, c.skill])
	var row := _row(box)
	_label(row, "Нанять учёного (навык 1–3)  ·  %d ПОТОМ" % SCIENTIST_PRICE)
	_button(row, "Нанять", GameState.money >= SCIENTIST_PRICE, func():
		GameState.money -= SCIENTIST_PRICE
		var c := {"name": NAMES[randi() % NAMES.size()], "role": "учёный", "skill": randi_range(1, 3)}
		GameState.crew.append(c)
		_status.text = "%s теперь в экипаже. Навык: %d." % [c.name, c.skill]
		refresh())


func _fill_sell(box: VBoxContainer) -> void:
	_label(box, "Станция покупает изученные образцы. Неизученные она не берёт: сначала изучите их в лаборатории.", Color(0.7, 0.75, 0.85), 18)
	var any := false
	for s in GameState.samples:
		if not s.studied:
			continue
		any = true
		var row := _row(box)
		_label(row, "%s (образец %s, планета %s)" % [s.name, s.id, s.planet], Color("#9aff6a"))
		_button(row, "Продать за %d ПОТОМ" % s.value, true, func():
			GameState.money += int(s.value)
			GameState.samples.erase(s)
			_status.text = "Продано: %s" % s.name
			refresh())
	if not any:
		_label(box, "Изученных образцов нет.", Color(0.7, 0.75, 0.85))
