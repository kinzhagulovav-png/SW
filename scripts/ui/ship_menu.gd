class_name ShipMenu
extends PanelContainer
## Окно корабля и научной станции.
## На корабле: трюм, переработка минералов в материалы, сборка базовых элементов, лаборатория.
## На научной станции: приборы и вещи за ПОТОМ, оборудование, верфь, экипаж, продажа образцов и ресурсов.
## На рынке заселённой планеты: оборудование, снаряжение, продажа ресурсов, топливо.
## Окно «Персонажи» (клавиша C): навыки со шкалами опыта и снаряжение капитана и экипажа.

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
## Кому покупаем снаряжение: 0 — капитан, дальше члены экипажа.
var _gear_for := 0


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
	GameState.skill_up.connect(func(p, sk, lvl): if visible: _status.text = "%s: навык «%s» вырос до %d!" % [p.name, People.SKILLS[sk].name, lvl])
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
	elif mode == "people":
		_title.text = "Персонажи · навыки и снаряжение"
		_page(GameState.hero.name, func(box): _fill_person(box, GameState.hero))
		for c in GameState.crew:
			_page(c.name, func(box): _fill_person(box, c))
	elif mode == "market":
		_title.text = "Рынок колонии %s · ПОТОМ: %d" % [place.name, GameState.money]
		_page("Оборудование", _fill_equipment)
		_page("Снаряжение", _fill_gear_shop)
		_page("Ресурсы", _fill_resources)
		_page("Корабль", _fill_ship)
		_page("Трюм", _fill_hold)
	else:
		_title.text = "Научная станция · ПОТОМ: %d" % GameState.money
		_page("Приборы и вещи", func(box): _fill_recipes(box, Items.DEVICES, "Изготовить", 1))
		_page("Оборудование", _fill_equipment)
		_page("Снаряжение", _fill_gear_shop)
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
		_label(box, "Учёный: %s, Наука %d.  Наука капитана: %d.  Изучить можно образец сложности до %d." % [sci.name, People.level(sci, "science"),
			GameState.lvl("science"), (People.level(sci, "science") + GameState.lvl("science")) / 2], Color("#9ad8ff"))
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
		var main: String = People.ROLE_SKILL.get(c.role, "science")
		_label(box, "%s · %s · %s %d   (подробно: окно «Персонажи», клавиша C)" % [c.name, c.role, People.SKILLS[main].name, People.level(c, main)])
	var full := GameState.crew_full()
	var disc := 1.0 - 0.05 * GameState.lvl("leadership")
	if full:
		_label(box, "Мест на корабле больше нет. Нужен корпус побольше (верфь).", Color("#ff8a6a"))
	for offer in [["учёного", "учёный", SCIENTIST_PRICE, NAMES], ["второго пилота", "второй пилот", COPILOT_PRICE, PILOT_NAMES]]:
		var row := _row(box)
		var cost := int(float(offer[2]) * disc)
		var main: String = People.ROLE_SKILL[offer[1]]
		_label(row, "Нанять %s (%s 2–4)  ·  %d ПОТОМ" % [offer[0], People.SKILLS[main].name, cost])
		_button(row, "Нанять", GameState.money >= cost and not full, func():
			GameState.money -= cost
			var names: Array = offer[3]
			var c := People.new_person(names[randi() % names.size()], offer[1], randi_range(2, 4))
			c.gear = {"suit": {"id": "suit", "mk": 1, "cond": 80}, "armor": {"id": "armor", "mk": 1, "cond": 80}}
			GameState.crew.append(c)
			GameState.hero_xp("leadership", 3)
			_status.text = "%s теперь в экипаже. %s: %d." % [c.name, People.SKILLS[main].name, People.level(c, main)]
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
		var value := int(float(s.value) * GameState.sell_mult())
		_button(row, "Продать за %d ПОТОМ" % value, true, func():
			GameState.money += value
			GameState.trade_xp()
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


func _colony() -> bool:
	return mode == "market"


func _fill_equipment(box: VBoxContainer) -> void:
	var tech: int = place.get("tech", 3)
	var mult: float = place.get("prices", 1.0) * GameState.buy_mult(_colony())
	var smult: float = place.get("prices", 1.0) * GameState.sell_mult(_colony())
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
		var back := int(ShipData.buyback(e) * smult)
		_button(row, "Продать за %d" % back, true, func():
			GameState.money += back
			GameState.trade_xp(_colony())
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
		var trade := int(ShipData.buyback(old) * smult) if not old.is_empty() else 0
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
			GameState.trade_xp(_colony())
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
	var mult: float = place.get("prices", 1.0) * GameState.sell_mult(_colony())
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
				GameState.trade_xp(_colony())
				refresh())
			_button(row, "Все за %d" % (price * c), true, func():
				GameState.add_item(id, -c)
				GameState.money += price * c
				GameState.trade_xp(_colony())
				refresh())
	if not any:
		_label(box, "Продавать нечего.", Color(0.7, 0.75, 0.85))


# ---------- Персонажи: навыки и снаряжение ----------

func _bar(box: Control, value: float, max_value: float, col: Color, width: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = max_value
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 14)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.16, 0.28)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(4)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	box.add_child(b)
	return b


func _fill_person(box: VBoxContainer, p: Dictionary) -> void:
	var is_hero := is_same(p, GameState.hero)
	_label(box, "%s · %s" % [p.name, "капитан корабля" if is_hero else p.role], Color("#ffbf55"), 24)
	_label(box, "Навыки (уровень 0–%d). Верхняя шкала — уровень, нижняя — опыт до следующего." % People.MAX_LEVEL, Color("#6fdcff"), 20)
	for id in People.SKILLS:
		var sk: Dictionary = People.SKILLS[id]
		var lvl := People.level(p, id)
		var row := _row(box)
		var name_l := _label(row, sk.name, sk.color, 19)
		name_l.size_flags_horizontal = Control.SIZE_FILL
		name_l.custom_minimum_size = Vector2(170, 0)
		var bars := VBoxContainer.new()
		bars.add_theme_constant_override("separation", 3)
		bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bars)
		_bar(bars, lvl, People.MAX_LEVEL, sk.color, 230)
		var need := People.xp_need(lvl)
		_bar(bars, int(p.xp.get(id, 0)) if lvl < People.MAX_LEVEL else need, need, sk.color.darkened(0.35), 230)
		var lv := _label(row, "%d   %s" % [lvl, ("опыт %d/%d" % [int(p.xp.get(id, 0)), need]) if lvl < People.MAX_LEVEL else "максимум"], Color(0.9, 0.92, 1.0), 18)
		lv.size_flags_horizontal = Control.SIZE_FILL
		lv.custom_minimum_size = Vector2(150, 0)
		var d := _label(row, sk.desc, Color(0.6, 0.68, 0.8), 14)
		d.custom_minimum_size = Vector2(300, 0)
	_label(box, "Снаряжение", Color("#6fdcff"), 20)
	for slot in People.GEAR:
		var g: Dictionary = p.gear.get(slot, {})
		if g.is_empty():
			_label(box, "    %s: нет" % People.GEAR[slot].name, Color(0.6, 0.65, 0.75), 18)
		else:
			_label(box, "    %s — %s" % [People.title(g), People.effect_text(g)], Color(0.9, 0.92, 1.0), 18)
	if not is_hero:
		_label(box, "Снаряжение экипажа пригодится, когда члены экипажа будут высаживаться и штурмовать вместе с вами.", Color(0.6, 0.68, 0.8), 15)


func _people() -> Array[Dictionary]:
	var out: Array[Dictionary] = [GameState.hero]
	out.append_array(GameState.crew)
	return out


func _fill_gear_shop(box: VBoxContainer) -> void:
	var tech: int = place.get("tech", 3)
	var colony := _colony()
	var mult: float = place.get("prices", 1.0) * GameState.buy_mult(colony)
	var smult: float = place.get("prices", 1.0) * GameState.sell_mult(colony)
	var people := _people()
	_gear_for = clampi(_gear_for, 0, people.size() - 1)
	var who: Dictionary = people[_gear_for]
	var sel := _row(box)
	var for_l := _label(sel, "Для кого:", Color(0.7, 0.75, 0.85), 18)
	for_l.size_flags_horizontal = Control.SIZE_FILL
	for_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	for i in people.size():
		var idx := i
		var b := Button.new()
		b.text = "  %s  " % people[i].name
		b.toggle_mode = true
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.button_pressed = i == _gear_for
		b.pressed.connect(func():
			_gear_for = idx
			refresh())
		sel.add_child(b)
	# Улучшение: на станции любой уровень, на рынке — до уровня техники места.
	var tech_disc := 1.0 - 0.05 * GameState.team_level("tech")
	_label(box, "Снаряжение: %s. Продать можно за %d%% цены. Улучшить на Мк выше: базовые элементы + ПОТОМ (Техника снижает цену)." % [who.name, 50], Color("#6fdcff"), 20)
	for slot in People.GEAR:
		var g: Dictionary = who.gear.get(slot, {})
		if g.is_empty():
			continue
		var row := _row(box)
		_label(row, "%s — %s" % [People.title(g), People.effect_text(g)], Color(0.9, 0.92, 1.0), 18)
		var back := int(People.buyback(g) * smult)
		_button(row, "Продать за %d" % back, true, func():
			GameState.money += back
			GameState.trade_xp(colony)
			who.gear.erase(slot)
			_status.text = "Продано: %s" % People.title(g)
			refresh())
		var mk := int(g.mk)
		if mk < 4:
			var need: Dictionary = People.UPGRADE_NEED[mk + 1]
			var cost := int(People.upgrade_cost(g) * place.get("prices", 1.0) * tech_disc)
			var can := mk + 1 <= tech and Items.can_make(GameState.inventory, need) and GameState.money >= cost
			_button(row, "До %s: %s, %d" % [People.MK[mk], Items.need_text(need), cost], can, func():
				for k in need:
					GameState.add_item(k, -int(need[k]))
				GameState.money -= cost
				g.mk = mk + 1
				g.cond = 100
				GameState.hero_xp("tech", 2)
				_status.text = "Улучшено: %s" % People.title(g)
				refresh())
	_label(box, "В продаже сегодня (уровень техники места: %d)" % tech, Color("#6fdcff"), 20)
	var key := _shop_key() + ":gear"
	var sold: Array = GameState.shop_sold.get(key, [])
	var stock := People.shop_stock(place.get("key", "station"), int(GameState.hours / 24.0), tech)
	for i in stock.size():
		if sold.has(i):
			continue
		var e: Dictionary = stock[i]
		var price := int(e.cost * mult)
		var old: Dictionary = who.gear.get(e.id, {})
		var trade := int(People.buyback(old) * smult) if not old.is_empty() else 0
		var row := _row(box)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		_label(info, "%s — %s" % [People.title(e), People.effect_text(e)], Color(0.9, 0.92, 1.0), 19)
		var note: String = People.GEAR[e.id].desc
		if trade > 0:
			note += " Старый %s заберут за %d." % [People.title(old), trade]
		_label(info, note, Color(0.65, 0.72, 0.85), 15)
		_button(row, "Купить за %d" % price, GameState.money + trade >= price, func():
			GameState.money += trade - price
			GameState.trade_xp(colony)
			who.gear[e.id] = {"id": e.id, "mk": e.mk, "cond": e.cond}
			sold.append(i)
			GameState.shop_sold[key] = sold
			_status.text = "%s: новое снаряжение %s" % [who.name, People.title(e)]
			refresh())
