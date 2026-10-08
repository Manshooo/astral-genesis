extends "res://dev/check_harness.gd"
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

## Порядок вкладок — часть договорённости: первая открыта по умолчанию. Имена
## страниц — ключи перевода: ярлыки TabContainer скрыты, их заменяют кнопки-
## вкладки с теми же ключами.
const TAB_ORDER: Array[String] = ["SETTINGS_TAB_GRAPHICS", "SETTINGS_TAB_AUDIO", "SETTINGS_TAB_CONTROLS"]

## Куда какая настройка легла. Ответ на развилку из карточки задачи:
## чувствительность мыши — про управление, а не про графику; FOV — про камеру.
const EXPECTED_TAB := {
	"fov": "SETTINGS_TAB_GRAPHICS",
	"max_fps": "SETTINGS_TAB_GRAPHICS",
	"graphics_preset_id": "SETTINGS_TAB_GRAPHICS",
	"render_scale": "SETTINGS_TAB_GRAPHICS",
	"shadow_quality": "SETTINGS_TAB_GRAPHICS",
	"aa_mode": "SETTINGS_TAB_GRAPHICS",
	"vsync_enabled": "SETTINGS_TAB_GRAPHICS",
	"master_volume": "SETTINGS_TAB_AUDIO",
	"mouse_sensitivity": "SETTINGS_TAB_CONTROLS",
	"keybinds": "SETTINGS_TAB_CONTROLS",
}

## Сколько места под страницы даёт экран: от y 150 до 100 px над низом базового
## окна 1497×720 (там ряд «Отмена / Сброс / Применить»). Всё, что не влезло,
## наехало бы на кнопки.
const PAGES_HEIGHT := 720.0 - 150.0 - 100.0


func _ready() -> void:
	_run()
	_finish()


func _run() -> void:
	var menu := (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)

	var tabs := menu.get_node("%Pages") as TabContainer
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

	var apply := menu.get_node("%Apply") as Button
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

	# --- 5. Пресет графики ↔ «Собственный» --------------------------------
	# Специфичная для фичи логика settings_menu.gd: выбор пресета раскатывает
	# его значения на связанные поля, а ручная правка любого из них откатывает
	# список обратно на «Собственный». Проверяется ТОЛЬКО через утиный контракт
	# контролов (set_setting_value + setting_changed), без обращения к
	# приватному _draft — так же, как раздел 4 выше правит master_volume.
	var preset = by_key.get("graphics_preset_id")
	var render_scale = by_key.get("render_scale")
	if preset != null and render_scale != null:
		var low := SettingsManager.preset_by_id(&"low")
		preset.set_setting_value(&"low")
		preset.setting_changed.emit(preset)
		_check(
			"выбор пресета «Низкий» раскатывает render_scale на контрол",
			is_equal_approx(float(render_scale.get_setting_value()), low.render_scale),
			"контрол показывает %s, ожидалось %s" % [render_scale.get_setting_value(), low.render_scale],
		)
		var shadows = by_key.get("shadow_quality")
		if shadows != null:
			_check(
				"и на ступень теней тоже",
				shadows.get_setting_value() == low.shadow_quality,
				"контрол показывает %s, ожидалось %s" % [shadows.get_setting_value(), low.shadow_quality],
			)

		# Ручная правка одного поля черновика — как будто игрок подвинул слайдер.
		render_scale.set_setting_value(1.5 if not is_equal_approx(low.render_scale, 1.5) else 0.5)
		render_scale.setting_changed.emit(render_scale)
		_check(
			"правка render_scale переводит пресет на «Собственный»",
			preset.get_setting_value() == GraphicsPresetSetting.CUSTOM_ID,
			"список пресетов остался на «%s»" % [preset.get_setting_value()],
		)

		# Vsync вынесен из пресета намеренно (не про качество картинки) — ни туда,
		# ни обратно он ходить не должен.
		var vsync = by_key.get("vsync_enabled")
		if vsync != null:
			var vsync_before = vsync.get_setting_value()
			preset.set_setting_value(&"high")
			preset.setting_changed.emit(preset)
			_check(
				"смена пресета не трогает vsync",
				vsync.get_setting_value() == vsync_before,
				"vsync изменился на «%s» после выбора пресета" % [vsync.get_setting_value()],
			)
			vsync.set_setting_value(not bool(vsync_before))
			vsync.setting_changed.emit(vsync)
			_check(
				"правка vsync не переводит пресет на «Собственный»",
				preset.get_setting_value() == &"high",
				"список пресетов откатился на «%s»" % [preset.get_setting_value()],
			)

	# --- 6. Минимальный размер не растёт по самой длинной вкладке --------
	# Знакомая грабля TabContainer: он запрашивает минимум по ВСЕМ вкладкам
	# сразу, и «Управление» с раскладкой растянула бы экран и на «Звуке» с
	# единственным ползунком. Прокрутка внутри вкладки эту связь рвёт.
	var needed := tabs.get_combined_minimum_size().y
	_check(
		"страницы влезают над рядом кнопок",
		needed <= PAGES_HEIGHT,
		"нужно %.0f px при доступных %.0f" % [needed, PAGES_HEIGHT],
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

	# --- 7. Вкладки — кнопки над скрытыми ярлыками ------------------------
	# Ярлыки TabContainer скрыты, страницы листают кнопки-мысли: разойдись их
	# порядок со страницами — «Звук» открывал бы «Управление», и молча.
	var buttons := menu.get_node("%TabButtons").get_children()
	_check("кнопок-вкладок столько же, сколько страниц", buttons.size() == tabs.get_tab_count(),
			"%d кнопок на %d страниц" % [buttons.size(), tabs.get_tab_count()])
	for i in range(buttons.size() - 1, -1, -1):
		(buttons[i] as BaseButton).pressed.emit()
		_check("кнопка %d открывает страницу %d" % [i, i], tabs.current_tab == i,
				"открыта %d" % tabs.current_tab)

	# --- 8. Тени — один список: «Выкл» и ступени каталога ----------------
	# Пункты строятся из данных: ступень, пропавшая из списка, или пресет,
	# ссылающийся на несуществующую ступень, не дают ошибки — пресет просто
	# выключил бы тени.
	var shadows_control = by_key.get("shadow_quality") as OptionSetting
	var library := SettingsManager.GRAPHICS_PRESETS
	if shadows_control != null:
		var expected: Array = [RS_GraphicsPreset.SHADOWS_OFF]
		for level in library.shadow_levels:
			expected.append(level.id)
		_check("список теней: «Выкл» и все ступени по порядку", shadows_control.option_values == expected,
				"%s вместо %s" % [shadows_control.option_values, expected])
		for p in library.presets:
			_check("ступень теней пресета «%s» есть в каталоге" % p.id,
					library.shadow_level(p.shadow_quality) != null, String(p.shadow_quality))
		# Ломается молча: при четырёх ячейках в четверти пары под омни-лампы
		# рвутся, и лампа в бюджете остаётся без тени — засвет вместо ошибки
		# (RS_ShadowLevel.cells_per_quadrant).
		for level in library.shadow_levels:
			_check("ступень «%s»: в четверти атласа не меньше 16 ячеек" % level.id,
					level.cells_per_quadrant >= Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16,
					"%d" % level.cells_per_quadrant)
		shadows_control.set_setting_value(RS_GraphicsPreset.SHADOWS_OFF)
		shadows_control.setting_changed.emit(shadows_control)
		_check("ручной выбор «Выкл» переводит пресет на «Собственный»",
				preset == null or preset.get_setting_value() == GraphicsPresetSetting.CUSTOM_ID,
				"список пресетов остался на «%s»" % [preset.get_setting_value()])

	# --- 9. Подсказка — в колонке, по строке, на которую смотрят ----------
	var shadows_row := menu.get_node("%Shadows") as UI_SettingRow
	shadows_row.looked_at.emit(shadows_row)
	var hint_text := menu.get_node("%HintText") as Label
	var hint_title := menu.get_node("%HintTitle") as Label
	_check("колонка подсказки показывает строку", hint_title.text == shadows_row.title()
			and hint_text.text == tr("SETTINGS_HINT_SHADOWS"),
			"«%s» / «%s»" % [hint_title.text, hint_text.text])

	# Настройки не трогались: правился только черновик меню, «Применить» не
	# нажималась. Убираем меню, чтобы его _input не пережил проверку.
	menu.queue_free()

	_check_legacy_shadows()
	_check_level_light()
	_check_shadow_budget()


## Сейв до ступеней теней: флажок и атлас приходят в RS_Settings._set тем же
## путём, что и из файла, — загрузчик ресурса зовёт set() на каждое поле. Ломается
## это молча: игрок, выключивший тени, после обновления получил бы их снова.
func _check_legacy_shadows() -> void:
	var off := RS_Settings.new()
	off.set(&"shadows_enabled", false)
	off.set(&"shadow_atlas_size", 4096)
	_check("старый сейв «тени выкл» остаётся без теней", off.shadow_quality == RS_GraphicsPreset.SHADOWS_OFF,
			String(off.shadow_quality))
	var sharp := RS_Settings.new()
	sharp.set(&"shadow_atlas_size", 4096)
	_check("старый атлас 4096 становится ступенью «Высокие»", sharp.shadow_quality == &"high",
			String(sharp.shadow_quality))
	var plain := RS_Settings.new()
	_check("без старых полей — умолчание «Средние»", plain.shadow_quality == &"medium", String(plain.shadow_quality))


## Лампа уровня следит за настройкой сама: «Выкл» снимает тень, ступень ставит
## свою дальность. Настройки подменяются только в памяти и возвращаются — на диск
## проверка ничего не пишет.
func _check_level_light() -> void:
	var before := SettingsManager.settings
	var omni := OmniLight3D.new()
	omni.set_script(LevelLight)
	add_child(omni)
	var tuned := before.copy()
	tuned.shadow_quality = &"high"
	SettingsManager.settings = tuned
	var high := SettingsManager.GRAPHICS_PRESETS.shadow_level(&"high")
	_check("лампа берёт дальность теней ступени", omni.shadow_enabled
			and is_equal_approx(omni.distance_fade_shadow, high.shadow_distance),
			"тень %s, дальность %.0f" % [omni.shadow_enabled, omni.distance_fade_shadow])
	var off := before.copy()
	off.shadow_quality = RS_GraphicsPreset.SHADOWS_OFF
	SettingsManager.settings = off
	_check("«Выкл» снимает тень с лампы", not omni.shadow_enabled, "")
	SettingsManager.settings = before
	omni.queue_free()


## Бюджет теней: в кадре тень получают лампы, чей свет ближе к камере, сверх
## бюджета — теряют; лампа вне кадра ячейку не занимает и тень сохраняет.
## Ломается тихо: перепутай порядок — без тени останется лампа над головой, и
## её свет пройдёт сквозь стену.
func _check_shadow_budget() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	var level := RS_ShadowLevel.new()
	level.cells_per_quadrant = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1  # бюджет 2
	level.shadow_distance = 40.0
	var lamps: Array = []
	for z in [-3.0, -20.0, -10.0, 15.0]:  # три впереди (камера смотрит в −Z), одна за спиной
		var lamp := OmniLight3D.new()
		lamp.omni_range = 8.0
		lamp.position = Vector3(0, 0, z)
		add_child(lamp)
		lamps.append(lamp)
	ShadowBudget.distribute(lamps, camera, level)
	var on: Array = lamps.map(func(l: Light3D) -> bool: return l.shadow_enabled)
	_check("бюджет: тень у двух ближних в кадре, дальняя без, лампа за спиной с тенью",
			on == [true, false, true, true], str(on))
	for lamp in lamps:
		lamp.queue_free()
	camera.queue_free()


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
