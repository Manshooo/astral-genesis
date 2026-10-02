extends Node
## Временный «фотограф» экранов меню для сверки с макетами. Не коммитится.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/C--Users-admin-Documents-Godot-Projects-astral-genesis/ff4b7ed6-d588-4ec9-b7f8-f865572c3dc4/scratchpad/shots/"
const MENU_MAP := "res://src/levels/menu_map/L_menu_map.tscn"
const PAUSE := "res://src/ui/pause_menu/pause_menu.tscn"
const SETTINGS := "res://src/ui/settings_menu/settings_menu.tscn"
const DEATH := "res://src/ui/death_screen/death_screen.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(OUT)
	var locale := OS.get_environment("SHOT_LOCALE")
	if locale != "":
		TranslationServer.set_locale(locale)
	var tag := locale if locale != "" else "ru"

	var bg: Node = load(MENU_MAP).instantiate()
	add_child(bg)
	await _wait(1.2)
	await _shot("01_menu_%s" % tag)

	# Наведение и фокус на пунктах меню.
	var items := bg.find_child("Items", true, false)
	(items.get_child(2) as Button).grab_focus()
	await _wait(0.5)
	await _shot("02_menu_focus_%s" % tag)

	# Настройки из главного меню — глухой фон.
	var menu_ui := bg.find_child("MainMenuUi", true, false) as Control
	var settings: Control = load(SETTINGS).instantiate()
	UIManager.push_screen(settings, false, menu_ui)
	await _wait(0.6)
	await _shot("03_settings_out_%s" % tag)
	# Фокус в строке «Разрешение теней» + выключенные тени — колонка подсказки
	# и недоступная строка.
	var shadows := settings.find_child("Shadows", true, false).get_child(1) as CheckBox
	shadows.button_pressed = false
	var atlas_row := settings.find_child("ShadowAtlasRow", true, false)
	(settings.find_child("Preset", true, false).get_child(1) as Control).grab_focus()
	await _wait(0.4)
	await _shot("03b_settings_focus_%s" % tag)
	(settings.find_child("Controls", true, false) as BaseButton).emit_signal("pressed")
	(settings.find_child("Controls", true, false) as BaseButton).button_pressed = true
	await _wait(0.4)
	await _shot("04_settings_keys_%s" % tag)
	UIManager.close_all()
	menu_ui.show()
	await _wait(0.3)

	# Пауза в забеге — поверх 3D-сцены меню, главное меню спрятано.
	menu_ui.hide()
	UIManager.enabled = true
	var pause: Control = load(PAUSE).instantiate()
	UIManager.push_screen(pause, true)
	await _wait(0.8)
	await _shot("05_pause_%s" % tag)
	var settings2: Control = load(SETTINGS).instantiate()
	UIManager.push_screen(settings2)
	await _wait(0.6)
	await _shot("06_settings_in_run_%s" % tag)
	UIManager.enabled = false
	UIManager.close_all()
	get_tree().paused = false
	bg.queue_free()
	await _wait(0.2)

	# Итоги с подложенной статистикой.
	var stats := RS_RunStats.new()
	stats.put(RS_RunStats.TIME, 754.0)
	stats.put(RS_RunStats.ROOMS, 23.0)
	stats.put(RS_RunStats.BODIES, 4.0)
	stats.put(RS_RunStats.DAMAGE_TAKEN, 182.0)
	stats.put(RS_RunStats.DAMAGE_DEALT, 64.0)
	stats.put(RS_RunStats.SKILL_POINTS, 3.0)
	stats.note_body("res://x.tscn", &"BODY_WALKER")
	stats.note_body("res://y.tscn", &"BODY_HOUND")
	RunStats.last = stats
	var death: Control = load(DEATH).instantiate()
	add_child(death)
	await _wait(1.0)
	await _shot("07_summary_%s" % tag)
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + shot_name + ".png")
	print("shot ", shot_name)
