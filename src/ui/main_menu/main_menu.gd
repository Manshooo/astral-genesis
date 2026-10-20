# res://src/ui/main_menu/main_menu.gd
## Главное меню языка «Отголосок» (§9 «Меню — спека»): название с эхом и пункты-мысли слева, справа живая сцена L_menu_map, в которую меню вложено.
extends UI_MenuScreen

const WORLD_SCENE := "res://src/world/world.tscn"
const CALIBRATION_SCENE := preload("res://src/ui/brightness_calibration/brightness_calibration.tscn")

@onready var load_button: Button = %Load
@onready var load_aside: Label = %LoadAside
@onready var version_label: Label = %Version
@onready var completed_note: Label = %CompletedNote


func _ready() -> void:
	super._ready()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIManager.enabled = false
	# Продолжать нечего, пока нет сейва (WorldSave держит заготовку); недоступный пункт объясняется словами рядом (§1).
	load_button.disabled = not WorldSave.has_save_file
	load_aside.visible = load_button.disabled
	# Тихая отметка вместо плашки «Пройдено»: игра после финала продолжается, концовку меню помнит.
	completed_note.visible = WorldSave.save.game_completed
	# Номер сборки — чтобы по скриншоту бага видеть коммит (не-релиз: 0.7.0-dev.33+fc91d3c, .github/scripts/build_version.sh).
	version_label.text = tr("MENU_BUILD") % ProjectSettings.get_setting("application/config/version")
	# Отложенно: меню входит в дерево вместе со сценой, корень занят.
	if not SettingsManager.settings.brightness_calibrated:
		_offer_calibration.call_deferred()


## Первый запуск: калибровка яркости поверх меню до входа в мир (иначе вслепую, по тьме забега); подобранное применяется сразу.
func _offer_calibration() -> void:
	var screen := CALIBRATION_SCENE.instantiate() as UI_BrightnessCalibration
	screen.brightness = SettingsManager.settings.brightness
	screen.confirmed.connect(_commit_brightness)
	UIManager.push_screen(screen, false, self, _on_calibration_closed)


## Показан — значит предложен: и «Назад» ставит отметку, иначе экран был бы каждый запуск.
func _on_calibration_closed() -> void:
	if not SettingsManager.settings.brightness_calibrated:
		_commit_brightness(SettingsManager.settings.brightness)


func _commit_brightness(brightness: float) -> void:
	var applied := SettingsManager.settings.copy()
	applied.brightness = brightness
	applied.brightness_calibrated = true
	SettingsManager.settings = applied
	SettingsManager.save()


func _on_new_game_pressed() -> void:
	WorldSave.new_game()  # катим новый world_seed до загрузки мира
	# Дерево навыков — метапрогресс; «новая игра» — чистый лист, оставленные ранги исказили бы первый забег. Зовём рядом с WorldSave.new_game(), не изнутри: автолоады держат файлы сами; Архитектор — то же.
	SkillManager.reset()
	ArchitectManager.reset()
	_enter_world($Content/Items/NewGame as UI_EchoButton)


## Продолжить сохранённое: WorldSave уже поднял сейв, RunManager возьмёт сид и узел.
func _on_load_pressed() -> void:
	_enter_world(load_button as UI_EchoButton)


## Уходит в мир: world.tscn грузится в фоне; нажатый пункт — бегущий штрих, остальные гаснут (второе нажатие начало бы вход дважды).
func _enter_world(pressed: UI_EchoButton) -> void:
	for node in find_children("*", "Button", true, false):
		(node as Button).disabled = true
	if pressed:
		pressed.busy = true
	await SceneLoader.change_to(get_tree(), WORLD_SCENE)


func _on_settings_pressed() -> void:
	var settings_menu = load("res://src/ui/settings_menu/settings_menu.tscn").instantiate()
	UIManager.push_screen(settings_menu, false, self)


func _on_exit_pressed() -> void:
	get_tree().quit()
