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
	"screen_effects": "SETTINGS_TAB_GRAPHICS",
	"glow_enabled": "SETTINGS_TAB_GRAPHICS",
	"aa_mode": "SETTINGS_TAB_GRAPHICS",
	"vsync_enabled": "SETTINGS_TAB_GRAPHICS",
	"window_mode": "SETTINGS_TAB_GRAPHICS",
	"resolution": "SETTINGS_TAB_GRAPHICS",
	"ui_scale": "SETTINGS_TAB_GRAPHICS",
	"brightness": "SETTINGS_TAB_GRAPHICS",
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
	var doubled: Array[String] = []
	for control in _collect(menu):
		var key: String = control.setting_key
		if by_key.has(key):
			doubled.append(key)
		by_key[key] = control
	_check("ни одна настройка не задвоена", doubled.is_empty(), "два контрола на %s" % ", ".join(doubled))

	var lost: Array[String] = []
	var misplaced: Array[String] = []
	for key: String in EXPECTED_TAB:
		if not by_key.has(key):
			lost.append(key)
		elif _tab_of(by_key[key], tabs) != EXPECTED_TAB[key]:
			misplaced.append("%s на «%s»" % [key, _tab_of(by_key[key], tabs)])
	_check("каждая настройка в меню", lost.is_empty(), "потерялись при переверстке: %s" % ", ".join(lost))
	_check("каждая настройка на своей вкладке", misplaced.is_empty(), ", ".join(misplaced))

	# Границы ползунка — те же, что держит камера: разойдись они, и ползунок
	# показывал бы угол, которого камера не даст.
	var fov_slider := by_key.get("fov") as Range
	if fov_slider != null:
		_check("ползунок поля зрения — от FOV_MIN до FOV_MAX",
			is_equal_approx(fov_slider.min_value, RS_Settings.FOV_MIN)
				and is_equal_approx(fov_slider.max_value, RS_Settings.FOV_MAX),
			"%.0f–%.0f" % [fov_slider.min_value, fov_slider.max_value])

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
		var effects = by_key.get("screen_effects")
		if shadows != null and effects != null:
			_check(
				"и на ступени теней и эффектов тоже",
				shadows.get_setting_value() == low.shadow_quality
					and effects.get_setting_value() == low.screen_effects,
				"тени %s, эффекты %s; ожидалось %s, %s" % [shadows.get_setting_value(),
					effects.get_setting_value(), low.shadow_quality, low.screen_effects],
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
		# Пресет, сославшийся на несуществующую ступень, не падает: тени или
		# эффекты просто выключаются.
		var dangling: Array[String] = []
		for p in library.presets:
			if library.shadow_level(p.shadow_quality) == null:
				dangling.append("%s: тени «%s»" % [p.id, p.shadow_quality])
			if library.effects_level(p.screen_effects) == null:
				dangling.append("%s: эффекты «%s»" % [p.id, p.screen_effects])
		_check("ступени теней и эффектов каждого пресета есть в каталоге", dangling.is_empty(),
				", ".join(dangling))
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

	var effects_control = by_key.get("screen_effects") as OptionSetting
	if effects_control != null:
		var effect_ids: Array = []
		for level in library.effects_levels:
			effect_ids.append(level.id)
		_check("список эффектов — ступени каталога по порядку", effects_control.option_values == effect_ids,
				"%s вместо %s" % [effects_control.option_values, effect_ids])

	# --- 9. Подсказка — в колонке, по строке, на которую смотрят ----------
	var shadows_row := menu.get_node("%Shadows") as UI_SettingRow
	shadows_row.looked_at.emit(shadows_row)
	var hint_text := menu.get_node("%HintText") as Label
	var hint_title := menu.get_node("%HintTitle") as Label
	_check("колонка подсказки показывает строку", hint_title.text == shadows_row.title()
			and hint_text.text == tr("SETTINGS_HINT_SHADOWS"),
			"«%s» / «%s»" % [hint_title.text, hint_text.text])

	# --- 10. Масштаб интерфейса без чёрных полей ---------------------------
	# Встроенный целый режим Godot при базе 1497 px на 1080p даёт множитель 1 и
	# ставит игру посередине в рамке. Масштаб поэтому задаётся базовым размером
	# холста: окно / k. Проверяется чистая функция — окна в headless нет.
	var base: Vector2i = SettingsManager.base_size()
	var full_hd := Vector2i(1920, 1080)
	_check("авто — холст базового размера",
		SettingsManager.ui_content_size(full_hd, base, 0.0) == base, "")
	var uhd := SettingsManager.ui_content_size(Vector2i(3840, 2160), base, 2.0)
	_check("200 % на 4K — холст ровно в половину окна, без полей", uhd == Vector2i(1920, 1080), str(uhd))
	var clamped := SettingsManager.ui_content_size(full_hd, base, 2.0)
	_check("масштаб больше влезающего зажимается: раскладке хватает базового места",
		clamped.x >= base.x and clamped.y >= base.y, str(clamped))
	_check("окно меньше базового — только авто",
		SettingsManager.ui_content_size(Vector2i(1280, 720), base, 1.0) == base, "")

	# Настройки не трогались: правился только черновик меню, «Применить» не
	# нажималась. Убираем меню, чтобы его _input не пережил проверку.
	menu.queue_free()

	_check_legacy_shadows()
	_check_player_fov()
	_check_level_light()
	_check_level_environment()
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


## Ползунок «Поле зрения» доходит до камеры игрока — и сразу, и при смене
## настройки. Ломалось молча: значение сохранялось и показывалось в меню, но его
## никто не читал, и камера жила с углом из сцены.
func _check_player_fov() -> void:
	var before := SettingsManager.settings
	var player := (load("res://src/entities/player/e_player.tscn") as PackedScene).instantiate() as E_Player
	add_child(player)
	var start_ok := is_equal_approx(player.camera.fov, before.fov)
	var narrow := before.copy()
	narrow.fov = 95.0 if not is_equal_approx(before.fov, 95.0) else 105.0
	SettingsManager.settings = narrow
	_check("поле зрения из настроек доходит до камеры игрока, по горизонтали",
		start_ok and is_equal_approx(player.camera.fov, narrow.fov)
			and player.camera.keep_aspect == Camera3D.KEEP_WIDTH,
		"на старте %.1f при %.1f, после смены %.1f при %.1f" % [
			player.camera.fov if start_ok else -1.0, before.fov, player.camera.fov, narrow.fov])
	# Сейв со старой шкалы 60–120: камера держит границы сама.
	var wide := before.copy()
	wide.fov = 120.0
	SettingsManager.settings = wide
	_check("поле зрения из старого сейва прижимается к границам",
		is_equal_approx(player.camera.fov, RS_Settings.FOV_MAX), "%.1f" % player.camera.fov)
	SettingsManager.settings = before
	player.free()


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
	_check("лампа берёт дальность теней ступени и гаснет там же", omni.shadow_enabled
			and is_equal_approx(omni.distance_fade_shadow, high.shadow_distance)
			and omni.distance_fade_enabled and is_equal_approx(omni.distance_fade_begin, high.shadow_distance),
			"тень %s, дальность тени %.0f, затухание с %.0f" % [omni.shadow_enabled,
				omni.distance_fade_shadow, omni.distance_fade_begin])
	var off := before.copy()
	off.shadow_quality = RS_GraphicsPreset.SHADOWS_OFF
	SettingsManager.settings = off
	var unshadowed := SettingsManager.GRAPHICS_PRESETS.unshadowed_light_distance
	_check("«Выкл» снимает тень с лампы, а гаснет она на дальности без теней",
		not omni.shadow_enabled and omni.distance_fade_enabled
			and is_equal_approx(omni.distance_fade_begin, unshadowed),
		"затухание с %.0f, ждали %.0f" % [omni.distance_fade_begin, unshadowed])
	# Апскейл: ниже 100 % — FSR1, иначе растяжение билинейным фильтром мылит
	# картинку «Низкого» пресета без всякой выгоды.
	var scaled := before.copy()
	scaled.render_scale = 0.65
	SettingsManager.settings = scaled
	var fsr := get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR
	scaled = before.copy()
	scaled.render_scale = 1.0
	SettingsManager.settings = scaled
	_check("ниже 100 % разрешения — FSR1, на 100 % — без апскейла",
		fsr and get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR,
		"режим %d" % get_viewport().scaling_3d_mode)
	SettingsManager.settings = before
	omni.queue_free()


## Окружение уровня под настройками: яркость доезжает до экспозиции поверх
## авторской, ступень эффектов снимает лишнее, но не включает того, что автор не
## ставил, а общий .tres окружения правкой не задевается. Всё это ломается молча —
## картинка просто светлее, темнее или дороже, чем выбрал игрок.
func _check_level_environment() -> void:
	var before := SettingsManager.settings
	var authored := Environment.new()
	authored.ssao_enabled = true
	authored.ssil_enabled = true
	authored.ssr_enabled = false
	authored.sdfgi_enabled = true
	authored.glow_enabled = true
	authored.fog_enabled = true
	authored.fog_mode = Environment.FOG_MODE_DEPTH
	authored.fog_depth_begin = 10.0
	authored.fog_depth_end = 40.0
	var attributes := CameraAttributesPractical.new()
	attributes.exposure_multiplier = 0.8

	# Всё, на что смотрят ассерты, задаётся явно: настройки разработчика бывают
	# любыми (пресет «Низкий» выключает свечение), и проверка не должна от них
	# зависеть.
	var tuned := before.copy()
	tuned.screen_effects = &"high"
	tuned.glow_enabled = true
	tuned.shadow_quality = &"high"
	tuned.brightness = 1.5
	SettingsManager.settings = tuned
	var node := WorldEnvironment.new()
	node.environment = authored
	node.camera_attributes = attributes
	node.set_script(LevelEnvironment)
	add_child(node)
	_check("яркость умножает авторскую экспозицию",
		is_equal_approx(node.camera_attributes.exposure_multiplier, 0.8 * 1.5),
		"%.3f" % node.camera_attributes.exposure_multiplier)
	_check("«Высокие» не включают эффект, которого автор не ставил",
		node.environment.ssao_enabled and node.environment.ssil_enabled and not node.environment.ssr_enabled,
		"ssao %s, ssil %s, ssr %s" % [node.environment.ssao_enabled, node.environment.ssil_enabled,
			node.environment.ssr_enabled])
	_check("SDFGI, поставленный автором, «Высокие» не включают — он только на «Ультра»",
		not node.environment.sdfgi_enabled, "")
	var ultra := tuned.copy()
	ultra.screen_effects = &"ultra"
	SettingsManager.settings = ultra
	_check("«Ультра» включает SDFGI, поставленный автором", node.environment.sdfgi_enabled, "")
	SettingsManager.settings = tuned

	_check("свечение, поставленное автором, при флажке «Вкл» остаётся", node.environment.glow_enabled, "")
	# Туман сгущается до полного там, где лампы погасли целиком, а начало держит
	# долю автора (10 из 40 — четверть).
	var fog_end := LevelLight.fade_begin() + LevelLight.FADE_LENGTH
	_check("туман кончается там, где погасли лампы, начало — в доле автора",
		is_equal_approx(node.environment.fog_depth_end, fog_end)
			and is_equal_approx(node.environment.fog_depth_begin, fog_end * 0.25),
		"туман %.1f–%.1f, лампы гаснут к %.1f" % [node.environment.fog_depth_begin,
			node.environment.fog_depth_end, fog_end])

	var low := before.copy()
	low.screen_effects = &"low"
	low.glow_enabled = false
	low.shadow_quality = &"low"
	SettingsManager.settings = low
	_check("«Низкие» оставляют только SSAO",
		node.environment.ssao_enabled and not node.environment.ssil_enabled,
		"ssao %s, ssil %s" % [node.environment.ssao_enabled, node.environment.ssil_enabled])
	_check("флажок «Свечение» снимает свечение", not node.environment.glow_enabled, "")
	_check("туман следует за ступенью теней: «Низкие» — ближе",
		is_equal_approx(node.environment.fog_depth_end, LevelLight.fade_begin() + LevelLight.FADE_LENGTH)
			and node.environment.fog_depth_end < fog_end,
		"%.1f при прежних %.1f" % [node.environment.fog_depth_end, fog_end])
	_check("правка не задела общий ресурс окружения и камеры",
		authored.ssil_enabled and is_equal_approx(attributes.exposure_multiplier, 0.8), "")

	SettingsManager.settings = tuned
	_check("ступень выше возвращает снятый эффект — счёт от авторского, а не от прошлого",
		node.environment.ssil_enabled, "")

	# Фон меню яркость не слушает, а эффекты — слушает.
	var menu_like := WorldEnvironment.new()
	menu_like.environment = authored
	menu_like.camera_attributes = attributes
	menu_like.set_script(LevelEnvironment)
	menu_like.set(&"apply_brightness", false)
	add_child(menu_like)
	_check("окружение без яркости экспозицию не трогает, а эффекты слушает",
		is_equal_approx(menu_like.camera_attributes.exposure_multiplier, 0.8)
			and menu_like.environment.ssil_enabled,
		"%.3f" % menu_like.camera_attributes.exposure_multiplier)

	SettingsManager.settings = before
	node.queue_free()
	menu_like.queue_free()
	_check_environments_wired()


## Каждое окружение сцен игры — WorldEnvironment под LevelEnvironment. Окружение,
## повешенное на Camera3D, или голый WorldEnvironment настройки не слышат и
## ничем об этом не скажут: эффекты в такой сцене просто не выключаются. Так и
## жил фон меню, пока окружение висело на его камере. Сверяется по SceneState —
## без инстанцирования сцен.
func _check_environments_wired() -> void:
	var stray: Array[String] = []
	var wired := 0
	for path in _scenes_under("res://src"):
		var state := (load(path) as PackedScene).get_state()
		for i in state.get_node_count():
			var type := state.get_node_type(i)
			var script: Script = null
			var has_environment := false
			for p in state.get_node_property_count(i):
				match state.get_node_property_name(i, p):
					&"script":
						script = state.get_node_property_value(i, p)
					&"environment":
						has_environment = true
			if type == &"WorldEnvironment":
				if script == LevelEnvironment:
					wired += 1
				else:
					stray.append("%s: %s без LevelEnvironment" % [path.get_file(), state.get_node_name(i)])
			elif type == &"Camera3D" and has_environment:
				stray.append("%s: окружение на камере %s" % [path.get_file(), state.get_node_name(i)])
	_check("каждое окружение сцен игры идёт через LevelEnvironment (%d)" % wired,
		stray.is_empty() and wired > 0, ", ".join(stray))


func _scenes_under(dir: String) -> Array[String]:
	var found: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scenes_under(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "tscn":
			found.append(dir.path_join(file))
	return found


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
	# Спрятанная лампа (узел дальше видимых) места в очереди не занимает: ближняя
	# спрятана — тень переходит к следующей видимой.
	(lamps[0] as Light3D).visible = false
	ShadowBudget.distribute(lamps, camera, level)
	_check("бюджет: спрятанная лампа тень у видимой не отнимает",
			(lamps[1] as Light3D).shadow_enabled and (lamps[2] as Light3D).shadow_enabled,
			str(lamps.map(func(l: Light3D) -> bool: return l.shadow_enabled)))
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
