extends Node
## Проверка вкладочного меню настроек (src/ui/settings_menu).
## Запуск: godot --headless dev/settings_menu_check.tscn
##
## Меню собирает контролы РЕКУРСИВНЫМ обходом поддерева, а не по путям, поэтому
## переверстка его логику не трогает — и ровно поэтому ломает её молча: настройка,
## случайно вынесенная мимо вкладок или потерянная при переносе, не даёт ни
## ошибки, ни предупреждения, она просто перестаёт быть в меню. Здесь и
## проверяется, что все ключи RS_Settings, у которых есть контрол, на месте и
## каждый лежит на своей вкладке.
##
## Второй тихий инвариант — «чистый» старт. TabContainer не раскладывает скрытые
## вкладки сразу, а baseline снимается со ВСЕХ контролов в _ready; если бы
## контрол на неоткрытой вкладке не отдавал значение, меню считало бы себя
## изменённым сразу при открытии и «Применить» горела бы на ровном месте.

const MENU_SCENE := "res://src/ui/settings_menu/settings_menu.tscn"

## Порядок вкладок — часть договорённости: первая открыта по умолчанию.
const TAB_ORDER: Array[String] = ["Графика", "Аудио", "Управление"]

## Куда какая настройка легла. Ответ на развилку из карточки задачи:
## чувствительность мыши — про управление, а не про графику; FOV — про камеру.
const EXPECTED_TAB := {
	"fov": "Графика",
	"max_fps": "Графика",
	"master_volume": "Аудио",
	"mouse_sensitivity": "Управление",
	"keybinds": "Управление",
}

## Сколько места под содержимое даёт панель: объявленный минимум 620 минус поля
## MarginContainer (16 сверху и снизу). Всё, что не влезло, вылезет за панель.
const PANEL_INNER_HEIGHT := 620.0 - 32.0

var _ok := 0
var _fail := 0


func _ready() -> void:
	_run()

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	var menu := (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)

	var tabs := menu.get_node("Panel/MarginContainer/VBox/Tabs") as TabContainer
	_check("TabContainer на месте", tabs != null, "меню перестало быть вкладочным")
	if tabs == null:
		return

	# --- 1. Состав вкладок ---------------------------------------------
	var titles: Array[String] = []
	for i in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	_check(
		"вкладки: %s" % ", ".join(TAB_ORDER),
		titles == TAB_ORDER,
		"вместо них %s" % [titles],
	)
	_check(
		"открыта первая вкладка",
		tabs.current_tab == 0,
		"открыта %d — вкладка по умолчанию не должна зависеть от точки входа" % tabs.current_tab,
	)

	# --- 2. Ни одна настройка не потерялась при переносе ----------------
	var by_key := {}
	for control in _collect(menu):
		var key: String = control.setting_key
		_check("ключ %s не задвоен" % key, not by_key.has(key), "два контрола на одну настройку")
		by_key[key] = control

	for key: String in EXPECTED_TAB:
		_check("настройка %s в меню" % key, by_key.has(key), "контрол потерялся при переверстке")
		if not by_key.has(key):
			continue
		_check(
			"настройка %s на вкладке «%s»" % [key, EXPECTED_TAB[key]],
			_tab_of(by_key[key], tabs) == EXPECTED_TAB[key],
			"оказалась на «%s»" % _tab_of(by_key[key], tabs),
		)

	# --- 3. Значения читаются и со скрытых вкладок ----------------------
	# Именно это делает открытие меню «чистым»: baseline снимается со всех
	# контролов сразу, включая те, чью вкладку ещё ни разу не показали.
	for key: String in ["master_volume", "mouse_sensitivity"]:
		if not by_key.has(key):
			continue
		var control = by_key[key]
		_check(
			"скрытая вкладка не мешает читать %s" % key,
			not control.is_visible_in_tree() and is_equal_approx(
				float(control.get_setting_value()), float(SettingsManager.settings.get(key))),
			"значение со скрытой вкладки не совпало с настройками",
		)

	var apply := menu.get_node("Panel/MarginContainer/VBox/Buttons/Apply") as Button
	_check(
		"свежеоткрытое меню не считает себя изменённым",
		apply.disabled,
		"«Применить» активна сразу при открытии — baseline снят не со всех контролов",
	)

	# --- 4. Правка на скрытой вкладке доходит до черновика ---------------
	var volume = by_key.get("master_volume")
	if volume != null:
		volume.set_setting_value(0.25 if not is_equal_approx(
				float(SettingsManager.settings.master_volume), 0.25) else 0.75)
		volume.setting_changed.emit(volume)
		_check(
			"изменение на неоткрытой вкладке зажигает «Применить»",
			not apply.disabled,
			"правка со скрытой вкладки не доехала до черновика",
		)

	# --- 5. Минимальный размер не растёт по самой длинной вкладке --------
	# Знакомая грабля TabContainer: он запрашивает минимум по ВСЕМ вкладкам
	# сразу, и «Управление» с восемью строками раскладки растянула бы окно и на
	# «Аудио» с единственным ползунком. Прокрутка внутри вкладки эту связь рвёт.
	# Спрашиваем VBox, а не саму панель: панель — не контейнер, её минимум всегда
	# равен объявленному custom_minimum_size, и переполнение содержимым на нём
	# никак не сказывается. Растёт именно требование содержимого.
	var vbox := menu.get_node("Panel/MarginContainer/VBox") as VBoxContainer
	var needed := vbox.get_combined_minimum_size().y
	_check(
		"содержимое меню влезает в панель",
		needed <= PANEL_INNER_HEIGHT,
		"нужно %.0f px при доступных %.0f" % [needed, PANEL_INNER_HEIGHT],
	)

	# Ключевое: минимум вкладок НЕ равен минимуму самой длинной страницы. Пока
	# это так, «Управление» может обрасти строками раскладки, не растягивая окно
	# на «Аудио» с единственным ползунком.
	var tallest := 0.0
	for page in tabs.get_children():
		var content := (page as Control).get_child(0) as Control
		tallest = maxf(tallest, content.get_combined_minimum_size().y)
	_check(
		"самая длинная вкладка не задаёт минимум остальным",
		tabs.get_combined_minimum_size().y < tallest,
		"вкладкам нужно %.0f px — ровно по самой длинной странице (%.0f), прокрутка не работает" % [
			tabs.get_combined_minimum_size().y, tallest],
	)

	# Настройки не трогались: правился только черновик меню, «Применить» не
	# нажималась. Убираем меню, чтобы его _input не пережил проверку.
	menu.queue_free()


## Те же правила, по которым контролы собирает само меню: узел с утиным
## контрактом настройки — лист, внутрь него не спускаемся.
func _collect(node: Node) -> Array:
	var found := []
	for child in node.get_children():
		if child.has_method("get_setting_value") and child.has_method("set_setting_value"):
			found.append(child)
		else:
			found.append_array(_collect(child))
	return found


## Заголовок вкладки, на которой лежит контрол ("" — вне вкладок).
func _tab_of(control: Node, tabs: TabContainer) -> String:
	var node := control as Node
	while node != null and node.get_parent() != tabs:
		node = node.get_parent()
	return String(node.name) if node != null else ""


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
