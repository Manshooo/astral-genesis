extends "res://dev/check_harness.gd"
## Проверка экрана калибровки яркости (src/ui/brightness_calibration).
## Запуск: godot --headless dev/brightness_calibration_check.tscn
##
## Пикселей headless не рисует, поэтому проверяется то, из чего складывается
## картинка знаков, — и ломается там всё молча. Калибровка честна, только пока
## знаки видят мир ровно так, как его видит камера забега: та же экспозиция при
## той же яркости, тот же тонмаппинг, фоновый свет эталонного слоя — серый той же
## яркости. Стоит одному из трёх разойтись — экран спокойно подберёт яркость не
## для того мира. Что кривая теней светлит и фоновый свет (а exposure_multiplier
## камеры — нет), headless не видно: это замер живым рендером, LevelEnvironment.
##
## Второе — куда уходит подобранное: из настроек в черновик (и только по
## «Применить» дальше), из главного меню на первом запуске — сразу в настройки.
## И что первый запуск предлагает экран ровно один раз, в том числе отказавшемуся.
## Настройки игрока (user://settings.tres) снимаются в начале и возвращаются.

const CALIBRATION_SCENE := "res://src/ui/brightness_calibration/brightness_calibration.tscn"
const SETTINGS_MENU_SCENE := "res://src/ui/settings_menu/settings_menu.tscn"
const MAIN_MENU_SCENE := "res://src/ui/main_menu/main_menu.tscn"
const WORLD_SCENE := "res://src/world/world.tscn"

var _settings_backup := PackedByteArray()
var _had_settings := false
var _settings_before: RS_Settings


func _ready() -> void:
	_settings_backup = FileAccess.get_file_as_bytes(SettingsManager.SETTINGS_PATH)
	_had_settings = not _settings_backup.is_empty()
	_settings_before = SettingsManager.settings.copy()

	await _check_sign_sees_world()
	await _check_settings_flow()
	await _check_first_launch()

	_restore_settings()
	_finish()


## Знаки под той же экспозицией и тем же тонмаппингом, что мир, и под фоновым
## светом дна. Окружение мира берётся из world.tscn — тем, чем его видит игра, —
## и ставится в синтетический LevelEnvironment: грузить весь мир ради одного
## ресурса незачем, а формула яркости у узла одна.
func _check_sign_sees_world() -> void:
	var screen := _new_calibration(1.25)
	add_child(screen)
	await get_tree().process_frame
	var mine := (screen.get_node("%Environment") as LevelEnvironment).environment

	var world := _world_environment_node()
	add_child(world)
	world.preview_brightness = 1.25
	var theirs := world.environment
	_check("знаки — под той же кривой теней, что мир, при той же яркости",
		_dark_lift(mine) > 0.0 and is_equal_approx(_dark_lift(mine), _dark_lift(theirs))
			and is_equal_approx(mine.tonemap_exposure, theirs.tonemap_exposure),
		"знаки %.3f, мир %.3f" % [_dark_lift(mine), _dark_lift(theirs)])
	_check("знаки — тем же тонмаппингом, что мир",
		mine.tonemap_mode == theirs.tonemap_mode and is_equal_approx(mine.tonemap_white, theirs.tonemap_white),
		"знаки %d/%.2f, мир %d/%.2f" % [mine.tonemap_mode, mine.tonemap_white, theirs.tonemap_mode, theirs.tonemap_white])

	var reference := (load(RS_DepthLighting.PATH) as RS_DepthLighting).for_depth(screen.reference_depth)
	var light := mine.ambient_light_color
	_check("знаки освещены светом эталонного слоя — серым той же яркости",
		is_equal_approx(light.r, light.g) and is_equal_approx(light.g, light.b)
			and is_equal_approx(light.srgb_to_linear().get_luminance(),
				reference.ambient_color.srgb_to_linear().get_luminance())
			and is_equal_approx(mine.ambient_light_energy, reference.ambient_energy),
		"%s × %.2f при слое %s × %.2f" % [light, mine.ambient_light_energy,
			reference.ambient_color, reference.ambient_energy])
	_check("фон за знаками — чистый чёрный",
		mine.background_mode == Environment.BG_COLOR and mine.background_color == Color.BLACK, "")
	var clear := (screen.get_node("%Clear") as MeshInstance3D).material_override as StandardMaterial3D
	var faint := (screen.get_node("%Faint") as MeshInstance3D).material_override as StandardMaterial3D
	var hidden := (screen.get_node("%Hidden") as MeshInstance3D).material_override as StandardMaterial3D
	_check("знаки идут по тьме: «виден» светлее «едва виден», тот светлее «не виден»",
		clear != null and faint != null and hidden != null
			and clear.albedo_color.get_luminance() > faint.albedo_color.get_luminance()
			and faint.albedo_color.get_luminance() > hidden.albedo_color.get_luminance(),
		"%s, %s, %s" % [clear.albedo_color if clear else null, faint.albedo_color if faint else null,
			hidden.albedo_color if hidden else null])
	# Ступень «Ультра» включила бы SDFGI окружению, где его поставил автор, — и
	# калибровка зависела бы от цены кадра. Ставится самая высокая ступень.
	var settings := SettingsManager.settings.copy()
	settings.screen_effects = &"ultra"
	settings.glow_enabled = true
	SettingsManager.settings = settings
	_check("ступень эффектов не добавляет знакам ни SSAO, ни SDFGI, ни тумана",
		not mine.ssao_enabled and not mine.ssil_enabled and not mine.sdfgi_enabled
			and not mine.glow_enabled and not mine.fog_enabled,
		"ssao %s, ssil %s, sdfgi %s, glow %s, fog %s" % [mine.ssao_enabled, mine.ssil_enabled,
			mine.sdfgi_enabled, mine.glow_enabled, mine.fog_enabled])
	SettingsManager.settings = _settings_before.copy()

	# Ползунок крутит черновик: экспозиция знаков идёт за ним, настройки — нет.
	var slider := screen.get_node("%Slider") as SliderSetting
	var lift_before := _dark_lift(mine)
	slider.set_setting_value(1.75)
	_check("ползунок светлит знаки",
		_dark_lift(mine) > lift_before, "%.3f → %.3f" % [lift_before, _dark_lift(mine)])
	_check("ползунок не применяет яркость в обход «Готово»",
		is_equal_approx(SettingsManager.settings.brightness, _settings_before.brightness),
		"применена %.2f" % SettingsManager.settings.brightness)

	world.queue_free()
	screen.queue_free()
	await get_tree().process_frame


## Из настроек подобранное доходит до ползунка «Яркости» в черновике и зажигает
## «Применить»; «Назад» с экрана не трогает ничего.
func _check_settings_flow() -> void:
	var menu := (load(SETTINGS_MENU_SCENE) as PackedScene).instantiate()
	UIManager.push_screen(menu)
	await get_tree().process_frame
	var brightness := _brightness_control(menu)
	var apply := menu.get_node("%Apply") as Button
	# Отличное от применённого: совпади оно — «Применить» верно не загорелась бы,
	# и проверка падала бы от того, какую яркость разработчик выставил себе.
	var picked := 2.0 if is_equal_approx(_settings_before.brightness, 1.5) else 1.5

	menu._on_calibration_pressed()
	await get_tree().process_frame
	var screen := _top_screen() as UI_BrightnessCalibration
	_check("из настроек открывается калибровка с яркостью черновика",
		screen != null and is_equal_approx(screen.brightness, brightness.get_setting_value()),
		"на вершине стека %s" % _top_screen())
	if screen == null:
		UIManager.close_all()
		return
	(screen.get_node("%Slider") as SliderSetting).set_setting_value(1.5)
	UIManager.close_top()
	await get_tree().process_frame
	_check("«Назад» с калибровки не трогает черновик",
		is_equal_approx(brightness.get_setting_value(), _settings_before.brightness) and apply.disabled,
		"ползунок %.2f" % brightness.get_setting_value())

	menu._on_calibration_pressed()
	await get_tree().process_frame
	screen = _top_screen() as UI_BrightnessCalibration
	(screen.get_node("%Slider") as SliderSetting).set_setting_value(picked)
	screen._on_done_pressed()
	await get_tree().process_frame
	_check("«Готово» кладёт подобранное в ползунок «Яркости» и зажигает «Применить»",
		is_equal_approx(brightness.get_setting_value(), picked) and not apply.disabled,
		"ползунок %.2f, «Применить» %s" % [brightness.get_setting_value(), "выкл" if apply.disabled else "вкл"])
	_check("до «Применить» настройки не тронуты",
		is_equal_approx(SettingsManager.settings.brightness, _settings_before.brightness), "")
	UIManager.close_all()
	await get_tree().process_frame


## Первый запуск: меню предлагает экран само, «Готово» применяет и сохраняет,
## «Назад» тоже снимает вопрос — и следующий запуск экран не показывает.
func _check_first_launch() -> void:
	_set_settings(1.0, false)
	var menu := await _open_main_menu()
	var screen := _top_screen() as UI_BrightnessCalibration
	_check("первый запуск открывает калибровку поверх меню", screen != null, "на вершине стека %s" % _top_screen())
	if screen != null:
		(screen.get_node("%Slider") as SliderSetting).set_setting_value(1.4)
		screen._on_done_pressed()
		await get_tree().process_frame
		var saved := ResourceLoader.load(SettingsManager.SETTINGS_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as RS_Settings
		_check("«Готово» на первом запуске применяет и сохраняет яркость",
			is_equal_approx(SettingsManager.settings.brightness, 1.4) and SettingsManager.settings.brightness_calibrated
				and saved != null and is_equal_approx(saved.brightness, 1.4) and saved.brightness_calibrated,
			"применена %.2f, на диске %s" % [SettingsManager.settings.brightness, saved.brightness if saved else "—"])
	menu.queue_free()
	UIManager.close_all()
	await get_tree().process_frame

	_set_settings(1.0, false)
	menu = await _open_main_menu()
	UIManager.close_top()  # Esc
	await get_tree().process_frame
	_check("«Назад» на первом запуске тоже отмечает калибровку предложенной",
		SettingsManager.settings.brightness_calibrated and is_equal_approx(SettingsManager.settings.brightness, 1.0),
		"отметка %s, яркость %.2f" % [SettingsManager.settings.brightness_calibrated, SettingsManager.settings.brightness])
	menu.queue_free()
	await get_tree().process_frame

	menu = await _open_main_menu()
	_check("откалиброванному игроку меню экран не предлагает",
		not (_top_screen() is UI_BrightnessCalibration), "на вершине стека %s" % _top_screen())
	menu.queue_free()
	UIManager.close_all()
	await get_tree().process_frame


## Во что кривая теней окружения переводит почти-чёрное 6/255; 0 — кривой нет.
func _dark_lift(environment: Environment) -> float:
	var curve := environment.adjustment_color_correction as Texture2D
	return curve.get_image().get_pixel(6, 0).r if curve and environment.adjustment_enabled else 0.0


func _open_main_menu() -> Node:
	var menu := (load(MAIN_MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame  # экран открывается отложенно
	return menu


func _new_calibration(brightness: float) -> UI_BrightnessCalibration:
	var screen := (load(CALIBRATION_SCENE) as PackedScene).instantiate() as UI_BrightnessCalibration
	screen.brightness = brightness
	return screen


## WorldEnvironment мира с его окружением — по SceneState world.tscn, не
## литералами: сверять надо с тем, что видит игра.
func _world_environment_node() -> LevelEnvironment:
	var state := (load(WORLD_SCENE) as PackedScene).get_state()
	var node := WorldEnvironment.new()
	for i in state.get_node_count():
		if state.get_node_type(i) != &"WorldEnvironment":
			continue
		for p in state.get_node_property_count(i):
			var name := state.get_node_property_name(i, p)
			if name == &"environment":
				node.set(name, state.get_node_property_value(i, p))
	node.set_script(LevelEnvironment)
	return node as LevelEnvironment


func _brightness_control(menu: Node) -> SliderSetting:
	for slider in menu.find_children("*", "HSlider", true, false):
		if slider is SliderSetting and (slider as SliderSetting).setting_key == "brightness":
			return slider
	return null


func _top_screen() -> Control:
	return UIManager._stack.back().screen if not UIManager._stack.is_empty() else null


func _set_settings(brightness: float, calibrated: bool) -> void:
	var settings := SettingsManager.settings.copy()
	settings.brightness = brightness
	settings.brightness_calibrated = calibrated
	SettingsManager.settings = settings


func _restore_settings() -> void:
	SettingsManager.settings = _settings_before
	if _had_settings:
		var file := FileAccess.open(SettingsManager.SETTINGS_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_settings_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsManager.SETTINGS_PATH))
	_check("настройки игрока возвращены на место",
		FileAccess.get_file_as_bytes(SettingsManager.SETTINGS_PATH) == _settings_backup, "")
