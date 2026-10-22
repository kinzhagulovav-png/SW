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
const FIGHTER_NAMES := ["Крон Валд", "Ния Шторм", "Тимур Бек", "Рагна Холм", "Зейн Арко"]
const MECH_NAMES := ["Отто Винтер", "Юна Пак", "Савва Грин", "Илса Мор", "Брок Тейлор"]
const FIGHTER_PRICE := 350
const MECH_PRICE := 350
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
var _base_for := 0
const DELIVERY_FEE_UI := BaseData.DELIVERY_FEE


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
		_page("Базы и новости", _fill_bases)
	elif mode == "base":
		var b := GameState.base_here()
		_title.text = "%s · ПОТОМ: %d" % [GameState._cap(GameState.base_name(b)), GameState.money]
		_page("Обзор", _fill_base)
		_page("Мастерская", _fill_workshop)
		_page("Склад", _fill_store)
	elif mode == "found":
		_title.text = "Основать базу на планете %s" % GameState.current_planet.get("name", "")
		_page("Новая база", _fill_found)
	elif (mode == "market" or mode == "station") and GameState.at_war(place.get("key", "")):
		_title.text = "%s · ВОЙНА" % ("Рынок колонии " + place.name if mode == "market" else "Научная станция")
		_page("Переговоры", _fill_war)
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
		_page("Для базы", _fill_base_shop)
		_page("Корабль", _fill_ship)
		_page("Трюм", _fill_hold)
	else:
		_title.text = "Научная станция · ПОТОМ: %d" % GameState.money
		_page("Приборы и вещи", func(box): _fill_recipes(box, Items.DEVICES, "Изготовить", 1))
		_page("Оборудование", _fill_equipment)
		_page("Снаряжение", _fill_gear_shop)
		_page("Для базы", _fill_base_shop)
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
	_label(box, "Скафандр: кислород %d%%, радзащита %d%%, броня %d%%.  Здоровье: %d из %d.  Радзащиту и броню чинит отсек ремонта на корабле во время высадки." % [su.oxygen, su.rad, su.armor, GameState.health, GameState.max_health()], Color("#d0e040"), 18)
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
	_label(box, "Учёный изучает образцы в лаборатории. Боец приходит с бластером и прикрывает на высадке. Механик приходит с лапатроном: копает по команде и ускоряет ремонт (Техника). Экипаж высаживается вместе с вами и слушает команды.", Color(0.7, 0.75, 0.85), 18)
	for c in GameState.crew:
		var main: String = People.ROLE_SKILL.get(c.role, "science")
		_label(box, "%s · %s · %s %d   (подробно: окно «Персонажи», клавиша C)" % [c.name, c.role, People.SKILLS[main].name, People.level(c, main)])
	var full := GameState.crew_full()
	var disc := 1.0 - 0.05 * GameState.lvl("leadership")
	if full:
		_label(box, "Мест на корабле больше нет. Нужен корпус побольше (верфь).", Color("#ff8a6a"))
	for offer in [["учёного", "учёный", SCIENTIST_PRICE, NAMES], ["второго пилота", "второй пилот", COPILOT_PRICE, PILOT_NAMES],
			["бойца", "боец", FIGHTER_PRICE, FIGHTER_NAMES], ["механика", "механик", MECH_PRICE, MECH_NAMES]]:
		var row := _row(box)
		var cost := int(float(offer[2]) * disc)
		var main: String = People.ROLE_SKILL[offer[1]]
		_label(row, "Нанять %s (%s 2–4)  ·  %d ПОТОМ" % [offer[0], People.SKILLS[main].name, cost])
		_button(row, "Нанять", GameState.money >= cost and not full, func():
			GameState.money -= cost
			var names: Array = offer[3]
			var c := People.new_person(names[randi() % names.size()], offer[1], randi_range(2, 4))
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
	_label(box, "Прочность корпуса: %d из %d" % [GameState.ship.hull_hp, GameState.max_hull_hp()], Color("#ff8a6a") if float(GameState.ship.hull_hp) < GameState.max_hull_hp() * 0.5 else Color(0.9, 0.92, 1.0))
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
	var dmg := int(GameState.max_hull_hp() - float(GameState.ship.hull_hp))
	var hcost := int(dmg * ShipData.HULL_REPAIR_PRICE * mult)
	var hrow := _row(box)
	_label(hrow, "Корпус: %d из %d. Ремонт: %d ПОТОМ" % [GameState.ship.hull_hp, GameState.max_hull_hp(), hcost], Color("#ffbf55"))
	_button(hrow, "Починить корпус", dmg > 0 and GameState.money >= hcost, func():
		GameState.money -= hcost
		GameState.ship.hull_hp = GameState.max_hull_hp()
		_status.text = "Корпус как новый."
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
			GameState.ship.hull_hp = GameState.max_hull_hp()
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
	var hrow := _row(box)
	var cur: float = GameState.health if is_hero else People.max_hp(p)
	var hl := _label(hrow, "Здоровье", Color("#76e8a0"), 19)
	hl.size_flags_horizontal = Control.SIZE_FILL
	hl.custom_minimum_size = Vector2(170, 0)
	_bar(hrow, cur, People.max_hp(p), Color("#76e8a0"), 230)
	var hv := _label(hrow, "%d из %d  (роль %s, +8 за уровень Выносливости)" % [cur, People.max_hp(p), p.role], Color(0.9, 0.92, 1.0), 17)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		var row := _row(box)
		var lands: bool = p.get("lands", true)
		_label(row, "На высадке: %s" % ("идёт с капитаном" if lands else "остаётся на корабле"), Color("#9aff6a") if lands else Color(0.7, 0.75, 0.85), 19)
		_button(row, "Оставить на корабле" if lands else "Брать на высадку", true, func():
			p["lands"] = not lands
			refresh())
		_label(box, "На планете: G за мной, T ждать, V копать (нужен лапатрон), B атаковать (нужен бластер), X к кораблю, Tab — кому команда.", Color(0.6, 0.68, 0.8), 15)


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


# ---------- База на планете ----------

func _fill_found(box: VBoxContainer) -> void:
	var p: Dictionary = GameState.current_planet
	var prof := Biomes.profile(p)
	_label(box, "База — ваш дом на этой планете: буры сами добывают минералы, завод перерабатывает, мастерская делает запчасти. Всё работает, даже когда вы улетели: время в галактике идёт.", Color(0.8, 0.85, 0.95), 18)
	_label(box, "Командный модуль корабль привёз с собой. Остальные модули и оборудование заказывают с доставкой на научной станции и в развитых колониях (вкладка «Для базы»).", Color(0.7, 0.75, 0.85), 17)
	_label(box, "Планета: %s · фон %s · минералы: %s · солнце ×%.1f" % [p.get("name", ""), Biomes.rad_text(prof.rad),
		", ".join(PackedStringArray(prof.minerals.map(func(m): return Items.MINERALS[m].sym))) if not prof.minerals.is_empty() else "нет", BaseData.sun(p.get("biome", ""))], Color("#ffbf55"), 18)
	var row := _row(box)
	_label(row, "Командный модуль: %d ПОТОМ" % BaseData.FOUND_PRICE, Color(0.9, 0.92, 1.0), 20)
	_button(row, "Основать базу", GameState.money >= BaseData.FOUND_PRICE, func():
		GameState.money -= BaseData.FOUND_PRICE
		base_founded.emit()
		mode = "base"
		_tab_index = 0
		refresh())


signal base_founded


func _fill_base(box: VBoxContainer) -> void:
	var b := GameState.base_here()
	if b.is_empty():
		_label(box, "Базы здесь нет.", Color(0.7, 0.75, 0.85))
		return
	var en := BaseData.energy(b)
	_label(box, "Энергия: выработка %d кВт, потребление %d кВт%s" % [en.made, en.used,
		"" if float(en.ratio) >= 1.0 else "  ·  НЕХВАТКА: всё работает на %d%%" % int(float(en.ratio) * 100.0)],
		Color("#9aff6a") if float(en.ratio) >= 1.0 else Color("#ff8a6a"), 20)
	_label(box, "Склад: %d из %d ед.   ·   Модулей: %d" % [BaseData.store_used(b), BaseData.store_cap(b), b.modules.size()], Color(0.85, 0.9, 1.0), 18)
	if not b.visit.is_empty():
		_label(box, "На базе мастера из «%s»%s." % [b.visit.faction, " — ВРАЖДЕБНЫ" if b.visit.hostile else ", чинят «%s»" % BaseData.MODULES[b.visit.id].name], Color("#ffbf55"), 18)
	if not b.job.is_empty():
		_label(box, "%s чинит модуль, готово через ~%d ч." % [b.job.who, ceili(float(b.job.done_at) - GameState.hours)], Color("#ffbf55"), 18)
	var mech := GameState.best_mechanic()
	_label(box, "Ремонт: механик (%s) — нужна Техника и запчасти; мастера — заказ на станции или в колонии, прилетают со своими запчастями и чинят как новое." %
		("%s, Техника %d" % [mech.name, People.level(mech, "tech")] if not mech.is_empty() else "в экипаже нет"), Color(0.65, 0.72, 0.85), 16)
	for m in b.modules:
		var d: Dictionary = BaseData.MODULES[m.id]
		var row := _row(box)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var e := int(d.energy)
		_label(info, "%s · %s · %s кВт" % [d.name, BaseData.status_text(m), ("+%d" % e) if e > 0 else str(e)],
			Color("#ff6a4a") if m.broken else Color(0.9, 0.92, 1.0), 19)
		_label(info, "Отработано %d ч из %d.  %s" % [m.worn, m.life, d.desc], Color(0.6, 0.68, 0.8), 15)
		var bar := _bar(info, BaseData.cond(m), 100.0, Color("#76e8a0") if BaseData.cond(m) > 30.0 else Color("#ff8a6a"), 300)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if BaseData.cond(m) < 99.0 or m.broken:
			var pid := BaseData.part_id(m.id)
			var have := int(b.store.get(pid, 0)) + GameState.count(pid)
			var need_tech := BaseData.mech_need(m.id)
			var ok: bool = not mech.is_empty() and People.level(mech, "tech") >= need_tech and have > 0 and b.job.is_empty()
			var why := ""
			if mech.is_empty():
				why = "нет механика"
			elif People.level(mech, "tech") < need_tech:
				why = "нужна Техника %d" % need_tech
			elif have <= 0:
				why = "нет запчастей"
			_button(row, "Механик: до %d%%" % int(GameState.mechanic_quality(mech)) if why == "" else "Механик: %s" % why, ok, func():
				if int(b.store.get(pid, 0)) > 0:
					BaseData.store_add(b, pid, -1)
				else:
					GameState.add_item(pid, -1)
				b.job = {"uid": m.uid, "done_at": GameState.hours + 3.0 * float(d.tier), "quality": GameState.mechanic_quality(mech), "who": mech.name}
				GameState.add_xp(mech, "tech", 2)
				_status.text = "%s взялся за ремонт." % mech.name
				refresh())


func _fill_workshop(box: VBoxContainer) -> void:
	var b := GameState.base_here()
	var ok_room := BaseData.has_working(b, "workshop") and BaseData.has_working(b, "habitat")
	_label(box, "Мастерская делает запчасти из материалов со склада базы, по %d ч на штуку." % int(BaseData.PART_HOURS) if ok_room else
		"Нужны работающие мастерская и жилой модуль. Закажите их на станции или в развитой колонии.", Color(0.8, 0.85, 0.95) if ok_room else Color("#ff8a6a"), 18)
	if not b.queue.is_empty():
		_label(box, "В очереди: %s" % ", ".join(PackedStringArray(b.queue.map(func(q): return BaseData.MODULES[q.substr(5)].name))), Color("#ffbf55"), 17)
	for id in BaseData.PARTS:
		var need: Dictionary = BaseData.PARTS[id]
		var pid := BaseData.part_id(id)
		var row := _row(box)
		_label(row, "%s (на складе %d)  ·  %s" % [BaseData.part_name(pid), int(b.store.get(pid, 0)), Items.need_text(need)], Color(0.9, 0.92, 1.0), 18)
		_button(row, "Сделать", ok_room and Items.can_make(b.store, need), func():
			for k in need:
				BaseData.store_add(b, k, -int(need[k]))
			b.queue.append(pid)
			GameState.hero_xp("tech", 1)
			refresh())


func _fill_store(box: VBoxContainer) -> void:
	var b := GameState.base_here()
	_label(box, "Склад базы %d из %d ед. Перенос между складом и трюмом корабля." % [BaseData.store_used(b), BaseData.store_cap(b)], Color(0.8, 0.85, 0.95), 18)
	_label(box, "На складе базы", Color("#6fdcff"), 21)
	if b.store.is_empty():
		_label(box, "    пусто", Color(0.6, 0.65, 0.75))
	for id in b.store.keys():
		var n := int(b.store[id])
		var row := _row(box)
		_label(row, "    %s: %d" % [Items.name_of(id), n], Color(0.9, 0.92, 1.0), 18)
		_button(row, "В трюм все", true, func():
			BaseData.store_add(b, id, -n)
			GameState.add_item(id, n)
			refresh())
	_label(box, "В трюме корабля", Color("#6fdcff"), 21)
	for id in GameState.inventory.keys():
		var n := GameState.count(id)
		var room := BaseData.store_cap(b) - BaseData.store_used(b)
		var row := _row(box)
		_label(row, "    %s: %d" % [Items.name_of(id), n], Color(0.9, 0.92, 1.0), 18)
		_button(row, "На склад", room > 0, func():
			var k := mini(n, BaseData.store_cap(b) - BaseData.store_used(b))
			GameState.add_item(id, -k)
			BaseData.store_add(b, id, k)
			refresh())


## Удалённый обзор баз (связь через командный модуль) и последние новости.
func _fill_bases(box: VBoxContainer) -> void:
	if GameState.bases.is_empty():
		_label(box, "Баз пока нет. Основать базу: на планете клавиша N.", Color(0.7, 0.75, 0.85))
	for key in GameState.bases:
		var b: Dictionary = GameState.bases[key]
		var en := BaseData.energy(b)
		var broken: int = b.modules.filter(func(m): return m.broken).size()
		_label(box, "%s: модулей %d, сломано %d, энергия %d/%d кВт, склад %d/%d" % [GameState._cap(GameState.base_name(b)), b.modules.size(), broken,
			en.made, en.used, BaseData.store_used(b), BaseData.store_cap(b)], Color("#ff8a6a") if broken > 0 else Color(0.9, 0.92, 1.0), 18)
	for key in GameState.wars:
		_label(box, "Война: %s" % GameState.wars[key].name, Color("#ff6a4a"), 18)
	if not GameState.orders.is_empty():
		_label(box, "В пути", Color("#6fdcff"), 21)
		for o in GameState.orders:
			_label(box, "    %s → %s, через ~%d ч" % [BaseData.MODULES[o.id].name if o.type == "module" else "мастера из «%s»" % o.faction,
				GameState.bases[o.base].planet.name if GameState.bases.has(o.base) else "?", ceili(float(o.eta) - GameState.hours)], Color(0.8, 0.85, 0.95), 17)
	_label(box, "Новости", Color("#6fdcff"), 21)
	var log := GameState.news_log.duplicate()
	log.reverse()
	for line in log:
		_label(box, line, Color(0.75, 0.8, 0.9), 16)


## Станция и развитые колонии: модули с доставкой, запчасти, вызов мастеров.
func _fill_base_shop(box: VBoxContainer) -> void:
	var tech: int = place.get("tech", 3)
	var mult: float = place.get("prices", 1.0) * GameState.buy_mult(_colony())
	var faction: String = place.get("name", "станция")
	if GameState.bases.is_empty():
		_label(box, "У вас нет баз. Основать базу: на планете клавиша N.", Color("#ff8a6a"), 18)
	var keys := GameState.bases.keys()
	_base_for = clampi(_base_for, 0, max(0, keys.size() - 1))
	if keys.size() > 1:
		var sel := _row(box)
		for i in keys.size():
			var idx := i
			var b := Button.new()
			b.text = "  %s  " % GameState.bases[keys[i]].planet.name
			b.toggle_mode = true
			b.button_pressed = i == _base_for
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func():
				_base_for = idx
				refresh())
			sel.add_child(b)
	var bkey: String = keys[_base_for] if not keys.is_empty() else ""
	if tech < 3:
		_label(box, "Эта колония не производит модули и оборудование (нужна развитая колония, уровень техники 3+).", Color(0.7, 0.75, 0.85), 17)
	else:
		_label(box, "Модули с доставкой%s (доставка %d ПОТОМ + 10%%)" % [" на базу " + GameState.bases[bkey].planet.name if bkey != "" else "", DELIVERY_FEE_UI], Color("#6fdcff"), 21)
		for id in BaseData.MODULES:
			if not BaseData.sold_here(id, tech):
				continue
			var d: Dictionary = BaseData.MODULES[id]
			var cost := int(float(d.price) * 1.1 * mult) + BaseData.DELIVERY_FEE
			var row := _row(box)
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var e := int(d.energy)
			_label(info, "%s · %s кВт · срок службы %d ч" % [d.name, ("+%d" % e) if e > 0 else str(e), d.life], Color(0.9, 0.92, 1.0), 19)
			_label(info, d.desc, Color(0.6, 0.68, 0.8), 15)
			_button(row, "Заказать за %d" % cost, bkey != "" and GameState.money >= cost, func():
				GameState.money -= cost
				var eta := GameState.hours + randf_range(10.0, 30.0)
				GameState.orders.append({"type": "module", "base": bkey, "id": id, "from": place.get("key", ""), "faction": faction, "eta": eta})
				GameState.trade_xp(_colony())
				_status.text = "%s в пути, прибудет через ~%d ч." % [d.name, ceili(eta - GameState.hours)]
				refresh())
	_label(box, "Запчасти (в трюм корабля)", Color("#6fdcff"), 21)
	for id in BaseData.PARTS:
		var pid := BaseData.part_id(id)
		var price := int(BaseData.part_price(pid) * mult)
		var row := _row(box)
		_label(row, "%s · %d ПОТОМ  (в трюме: %d)" % [BaseData.part_name(pid), price, GameState.count(pid)], Color(0.9, 0.92, 1.0), 18)
		_button(row, "Купить", GameState.money >= price, func():
			GameState.money -= price
			GameState.add_item(pid, 1)
			GameState.trade_xp(_colony())
			refresh())
	if bkey == "":
		return
	var base: Dictionary = GameState.bases[bkey]
	_label(box, "Мастера: прилетают со своими запчастями и чинят как новое", Color("#6fdcff"), 21)
	var any := false
	for m in base.modules:
		if BaseData.cond(m) >= 90.0 and not m.broken:
			continue
		if tech < 3 or (tech < 4 and int(BaseData.MODULES[m.id].tier) > tech - 1):
			continue
		any = true
		var cost := int(BaseData.masters_price(m.id) * mult)
		var busy: bool = not base.visit.is_empty() or GameState.orders.any(func(o): return o.type == "masters" and o.base == bkey)
		var row := _row(box)
		_label(row, "%s · %s" % [BaseData.MODULES[m.id].name, BaseData.status_text(m)], Color("#ff6a4a") if m.broken else Color(0.9, 0.92, 1.0), 18)
		_button(row, "Вызвать за %d" % cost, not busy and GameState.money >= cost, func():
			GameState.money -= cost
			var eta := GameState.hours + randf_range(8.0, 20.0)
			GameState.orders.append({"type": "masters", "base": bkey, "uid": m.uid, "from": place.get("key", ""), "faction": faction, "eta": eta})
			_status.text = "Мастера вылетели, будут через ~%d ч." % ceili(eta - GameState.hours)
			refresh())
	if not any:
		_label(box, "    Ремонт мастерами не нужен или им не по силам.", Color(0.6, 0.65, 0.75), 16)


func _fill_war(box: VBoxContainer) -> void:
	var key: String = place.key
	var w: Dictionary = GameState.wars[key]
	_label(box, "Вы напали на их мастеров. «%s» воюет с вами: торговли нет, армия нападает на ваши базы и корабль." % w.name, Color("#ff6a4a"), 20)
	var price := GameState.peace_price(key)
	var row := _row(box)
	_label(row, "Мирный договор: %d ПОТОМ (Дипломатия снижает цену)" % price, Color("#ffbf55"), 20)
	_button(row, "Заключить мир", GameState.money >= price, func():
		GameState.money -= price
		GameState.make_peace(key)
		_tab_index = 0
		refresh())
