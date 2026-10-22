class_name ShipMenu
extends PanelContainer
## Окно корабля и научной станции.
## На корабле: трюм, переработка минералов в материалы, сборка базовых элементов, лаборатория.
## На научной станции: приборы и вещи за ПОТОМ, оборудование, верфь, экипаж, продажа образцов и ресурсов.
## На рынке заселённой планеты: оборудование, продажа ресурсов, топливо.

const SCIENTIST_PRICE := 300
const COPILOT_PRICE := 400
const PILOT_NAMES := ["Рейн Торн", "Кира Мэй", "Борис Ланг", "Селена Ю", "Гарт Ормонд"]
const NAMES := ["Ирма Вейс", "Тарос Кейн", "Лия Орлова", "Дорн Салех", "Мика Ито", "Ярослав Нейман", "Ава Корр"]

var mode := "ship"
## Где мы торгуем: {"key", "name", "tech" 1..4, "prices" множитель}.
var place: Dictionary = {}
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


func open(new_mode: String, new_place: Dictionary = {}) -> void:
	if mode != new_mode or place.get("key", "") != new_place.get("key", ""):
		_tab_index = 0
	mode = new_mode
	place = new_place
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
		_page("Корабль", _fill_ship)
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
	elif mode == "market":
		_title.text = "Рынок колонии %s · ПОТОМ: %d" % [place.name, GameState.money]
		_page("Оборудование", _fill_equipment)
		_page("Ресурсы", _fill_resources)
		_page("Корабль", _fill_ship)
		_page("Трюм", _fill_hold)
	else:
		_title.text = "Научная станция · ПОТОМ: %d" % GameState.money
		_page("Приборы и вещи", func(box): _fill_recipes(box, Items.DEVICES, "Изготовить", 1))
		_page("Оборудование", _fill_equipment)
		_page("Верфь", _fill_shipyard)
		_page("Экипаж", _fill_crew)
		_page("Ресурсы", _fill_resources)
		_page("Образцы", _fill_sell)
		_page("Корабль", _fill_ship)
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
	_label(box, "Объём трюма: %d из %d ед.   Взлётная масса: %d из %d кг%s" % [GameState.cargo_volume(), GameState.cargo_capacity(),
		GameState.takeoff_mass(), GameState.max_lift(), "   ПЕРЕГРУЗ: корабль не взлетит!" if over else ""],
		Color("#ff6a4a") if over else Color("#ffbf55"), 19)
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
				lines.append([id, "%s%s: %d  ·  %d кг · %d ед." % [g[1][id].name, extra, c, Items.mass_of(id) * c, GameState.item_volume(id) * c]])
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
	var h := GameState.hull()
	_label(box, "Корабль «%s» (%s): мест для экипажа %d, одно из них ваше.%s" % [h.name, h.kind, h.crew,
		" Этому классу нужен второй пилот." if h.copilot else ""], Color(0.7, 0.75, 0.85), 18)
	_label(box, "Учёный изучает неизвестные образцы в лаборатории корабля. Чем выше его навык, тем сложнее образцы ему по силам.", Color(0.7, 0.75, 0.85), 18)
	for c in GameState.crew:
		_label(box, "%s · %s · навык %d" % [c.name, c.role, c.skill])
	var full := GameState.crew_full()
	if full:
		_label(box, "Мест на корабле больше нет. Нужен корпус побольше (верфь).", Color("#ff8a6a"))
	for offer in [["учёного", "учёный", SCIENTIST_PRICE, NAMES], ["второго пилота", "второй пилот", COPILOT_PRICE, PILOT_NAMES]]:
		var row := _row(box)
		_label(row, "Нанять %s (навык 1–3)  ·  %d ПОТОМ" % [offer[0], offer[2]])
		_button(row, "Нанять", GameState.money >= int(offer[2]) and not full, func():
			GameState.money -= int(offer[2])
			var names: Array = offer[3]
			var c := {"name": names[randi() % names.size()], "role": offer[1], "skill": randi_range(1, 3)}
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


# ---------- Корабль, оборудование, верфь, ресурсы ----------

func _fill_ship(box: VBoxContainer) -> void:
	var h := GameState.hull()
	_label(box, "«%s» · класс %s" % [h.name, h.kind], Color("#ffbf55"), 24)
	_label(box, "Вместимость корпуса: %d ед. (оборудование %d, груз %d, свободно %d)" % [h.capacity, GameState.equip_volume(),
		GameState.cargo_volume(), GameState.cargo_capacity() - GameState.cargo_volume()])
	_label(box, "Грузоподъёмность: %d кг (масса груза %d и оборудования %d)" % [GameState.max_lift(), GameState.cargo_mass(), GameState.equip_mass()])
	_label(box, "Скорость: %d   ·   Топливо: %d из %d   ·   Экипаж: %d из %d мест%s" % [GameState.ship_speed(), GameState.ship.fuel,
		GameState.max_fuel(), GameState.crew.size() + 1, h.crew, "   ·   нужен второй пилот" if h.copilot else ""])
	_label(box, "Оборудование", Color("#6fdcff"), 22)
	for slot in ShipData.EQUIP:
		var e := GameState.equip(slot)
		if e.is_empty():
			_label(box, "    %s: пусто" % ShipData.EQUIP[slot].name, Color(0.6, 0.65, 0.75))
		else:
			_label(box, "    %s — %s · %d ед., %d кг" % [ShipData.title(e), ShipData.effect_text(e), ShipData.size_of(e), ShipData.mass_of(e)])


func _shop_key() -> String:
	return "%s:%d" % [place.get("key", "station"), int(GameState.hours / 24.0)]


func _fill_equipment(box: VBoxContainer) -> void:
	var tech: int = place.get("tech", 3)
	var mult: float = place.get("prices", 1.0)
	# Топливо.
	var need := int(GameState.max_fuel() - float(GameState.ship.fuel))
	var cost := need * ShipData.FUEL_PRICE
	var frow := _row(box)
	_label(frow, "Топливо: %d из %d. Заправка до полного: %d ПОТОМ" % [GameState.ship.fuel, GameState.max_fuel(), cost], Color("#ffbf55"))
	_button(frow, "Заправить", need > 0 and GameState.money >= cost, func():
		GameState.money -= cost
		GameState.ship.fuel = GameState.max_fuel()
		_status.text = "Баки полны."
		refresh())
	_label(box, "Ваше оборудование (место его покупает за %d%% цены)" % 55, Color("#6fdcff"), 22)
	for slot in ShipData.EQUIP:
		var e := GameState.equip(slot)
		if e.is_empty():
			continue
		var row := _row(box)
		_label(row, "%s — %s" % [ShipData.title(e), ShipData.effect_text(e)], Color(0.9, 0.92, 1.0), 19)
		var back := int(ShipData.buyback(e) * mult)
		_button(row, "Продать за %d" % back, true, func():
			GameState.money += back
			GameState.ship.equip.erase(slot)
			GameState.ship.fuel = min(float(GameState.ship.fuel), GameState.max_fuel())
			_status.text = "Продано: %s" % ShipData.title(e)
			refresh())
	_label(box, "В продаже сегодня (уровень техники места: %d)" % tech, Color("#6fdcff"), 22)
	var key := _shop_key()
	var sold: Array = GameState.shop_sold.get(key, [])
	var stock := ShipData.shop_stock(place.get("key", "station"), int(GameState.hours / 24.0), tech)
	for i in stock.size():
		if sold.has(i):
			continue
		var e: Dictionary = stock[i]
		var price := int(e.cost * mult)
		var old := GameState.equip(e.id)
		var trade := int(ShipData.buyback(old) * mult) if not old.is_empty() else 0
		var new_cap := int(GameState.hull().capacity) - GameState.equip_volume() + (ShipData.size_of(old) if not old.is_empty() else 0) - ShipData.size_of(e)
		var fits := new_cap >= GameState.cargo_volume()
		var row := _row(box)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		_label(info, "%s — %s" % [ShipData.title(e), ShipData.effect_text(e)], Color(0.9, 0.92, 1.0), 20)
		var note := "%d ед., %d кг. %s" % [ShipData.size_of(e), ShipData.mass_of(e), ShipData.EQUIP[e.id].desc]
		if trade > 0:
			note += " Старый %s заберут за %d." % [ShipData.title(old), trade]
		if not fits:
			note += " Не влезет: освободите трюм."
		_label(info, note, Color(0.65, 0.72, 0.85) if fits else Color("#ff8a6a"), 16)
		_button(row, "Купить за %d" % price, fits and GameState.money + trade >= price, func():
			GameState.money += trade - price
			GameState.ship.equip[e.id] = {"id": e.id, "mk": e.mk, "cond": e.cond}
			GameState.ship.fuel = min(float(GameState.ship.fuel), GameState.max_fuel())
			sold.append(i)
			GameState.shop_sold[key] = sold
			_status.text = "Установлено: %s" % ShipData.title(e)
			refresh())


func _fill_shipyard(box: VBoxContainer) -> void:
	var cur := GameState.hull()
	var trade := int(float(cur.price) * 0.5)
	_label(box, "Верфь меняет корпус. Ваш «%s» заберут за %d ПОТОМ. Оборудование, груз и экипаж переезжают, если влезают." % [cur.name, trade], Color(0.7, 0.75, 0.85), 18)
	for id in ShipData.HULLS:
		var h: Dictionary = ShipData.HULLS[id]
		if id == GameState.ship.hull:
			continue
		var need_space := GameState.equip_volume() + GameState.cargo_volume()
		var ok_space := int(h.capacity) >= need_space
		var ok_crew := GameState.crew.size() <= int(h.crew) - 1
		var cost := int(h.price) - trade
		var row := _row(box)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		_label(info, "«%s» · %s" % [h.name, h.kind], Color("#ffbf55"), 21)
		_label(info, "Вместимость %d ед. · грузоподъёмность %d кг · экипаж %d · скорость ×%.2f%s" % [h.capacity, h.lift, h.crew, h.speed,
			" · нужен второй пилот" if h.copilot else ""], Color(0.8, 0.85, 0.95), 17)
		if not ok_space:
			_label(info, "Не влезут оборудование и груз (%d ед.)" % need_space, Color("#ff8a6a"), 16)
		if not ok_crew:
			_label(info, "Не хватит мест для экипажа", Color("#ff8a6a"), 16)
		_button(row, ("Доплатить %d" % cost) if cost >= 0 else ("Получить %d" % -cost), ok_space and ok_crew and GameState.money >= cost, func():
			GameState.money -= cost
			GameState.ship.hull = id
			_status.text = "Новый корабль: «%s»!" % h.name
			refresh())


func _fill_resources(box: VBoxContainer) -> void:
	var mult: float = place.get("prices", 1.0)
	_label(box, "Здесь покупают минералы, материалы и базовые элементы. Переработанное стоит дороже сырья.", Color(0.7, 0.75, 0.85), 18)
	var any := false
	for table in [Items.MINERALS, Items.MATERIALS, Items.BASICS]:
		for id in table:
			var c := GameState.count(id)
			if c <= 0:
				continue
			any = true
			var price := maxi(1, int(Items.price_of(id) * mult))
			var row := _row(box)
			_label(row, "%s: %d шт. · по %d ПОТОМ" % [Items.name_of(id), c, price])
			_button(row, "Продать 1", true, func():
				GameState.add_item(id, -1)
				GameState.money += price
				refresh())
			_button(row, "Все за %d" % (price * c), true, func():
				GameState.add_item(id, -c)
				GameState.money += price * c
				refresh())
	if not any:
		_label(box, "Продавать нечего.", Color(0.7, 0.75, 0.85))
