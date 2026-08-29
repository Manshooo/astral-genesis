# res://src/autoloads/settings_manager.gd
extends Node

const SETTINGS_PATH := "user://settings.tres"
## Не preload: preload резолвится на компиляции и в debug/export-сборке падает на
## кастомном ресурсе («Cannot get class ''», godotengine/godot#100100). Грузим в
## рантайме через load() в _init — поэтому var, а не const.
const DEFAULT_SETTINGS_PATH := "res://data/settings.tres"
var DEFAULT_SETTINGS: RS_Settings

## Действия, доступные для переназначения, в порядке показа в настройках.
## pause_game сюда НЕ входит намеренно: Esc — инвариант UI (им закрывается любой
## экран, включая сам экран настроек, где идёт захват клавиши).
const REBINDABLE_ACTIONS := {
	&"move_forward": "Вперёд",
	&"move_backward": "Назад",
	&"move_left": "Влево",
	&"move_right": "Вправо",
	&"jump": "Прыжок",
	&"interact": "Взаимодействие",
	&"snatch_body": "Захват тела",
	&"leave_body": "Покинуть тело",
}

## Человекочитаемые имена кнопок мыши: OS.get_keycode_string умеет только клавиши.
const MOUSE_BUTTON_NAMES := {
	MOUSE_BUTTON_LEFT: "ЛКМ",
	MOUSE_BUTTON_RIGHT: "ПКМ",
	MOUSE_BUTTON_MIDDLE: "СКМ",
	MOUSE_BUTTON_WHEEL_UP: "Колесо вверх",
	MOUSE_BUTTON_WHEEL_DOWN: "Колесо вниз",
	MOUSE_BUTTON_XBUTTON1: "Мышь 4",
	MOUSE_BUTTON_XBUTTON2: "Мышь 5",
}

## Эмитится каждый раз, когда settings меняются (загрузка, Apply, Reset) —
## подписывайтесь, если системе/UI нужно среагировать на смену настроек.
signal settings_changed(settings: RS_Settings)

var settings: RS_Settings:
	set(value):
		settings = value
		_apply_runtime_effects()

## Дефолтная раскладка из project.godot: action → код события. Снимается ОДИН раз
## в _init, до того как настройки успели что-то переопределить в InputMap.
var _default_codes: Dictionary = {}


func _init() -> void:
	DEFAULT_SETTINGS = load(DEFAULT_SETTINGS_PATH)
	# Автолоады создаются уже после инициализации InputMap из project.godot,
	# поэтому здесь в нём ещё нетронутая дефолтная раскладка.
	_snapshot_default_codes()

func _ready() -> void:
	settings = _load()  # проходит через сеттер -> сразу применяет эффекты

func save() -> void:
	var err := ResourceSaver.save(settings, SETTINGS_PATH)
	if err != OK:
		push_error("SettingsManager: не удалось сохранить настройки, код ошибки %d" % err)

func reset() -> void:
	settings = DEFAULT_SETTINGS.copy()  # тоже через сеттер

func default_settings() -> RS_Settings:
	return DEFAULT_SETTINGS.copy()

func _load() -> RS_Settings:
	if ResourceLoader.exists(SETTINGS_PATH):
		var loaded := ResourceLoader.load(SETTINGS_PATH) as RS_Settings
		if loaded:
			return loaded
		push_warning("SettingsManager: файл настроек повреждён, загружаю дефолтные")
	return DEFAULT_SETTINGS.copy()

## Побочные эффекты, которые должны применяться немедленно при смене настроек,
## а не только на старте игры.
func _apply_runtime_effects() -> void:
	if settings == null:
		return
	Engine.max_fps = settings.max_fps
	_apply_keybinds()
	settings_changed.emit(settings)


# ---------------------------------------------------------------------------
# Управление: раскладка клавиш
# ---------------------------------------------------------------------------


## Раскатывает settings.keybinds поверх дефолтной раскладки. База каждый раз
## перезагружается из project.godot: в настройках лежат только ОТЛИЧИЯ, поэтому
## «Сброс» (пустой словарь) обязан вернуть управление к дефолту, а не оставить
## прошлые переопределения висеть в InputMap.
func _apply_keybinds() -> void:
	InputMap.load_from_project_settings()
	for action: StringName in settings.keybinds:
		if not InputMap.has_action(action):
			continue  # действие исчезло из project.godot — сейв старше проекта
		var event := code_to_event(settings.keybinds[action])
		if event == null:
			continue
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)


## Код действия по дефолтной раскладке project.godot ("" — действия нет или у
## него нет ни клавиши, ни кнопки мыши).
func default_code_for(action: StringName) -> String:
	return _default_codes.get(action, "")


## Читаемое имя ТЕКУЩЕЙ привязки действия — для подсказок в HUD ("F", "ЛКМ").
## Читает InputMap, а не сейв, поэтому остаётся верным сразу после
## переназначения. "" — у действия нет ни клавиши, ни кнопки мыши (тогда
## подсказке нечего показывать и префикс лучше не рисовать вовсе).
func action_display_name(action: StringName) -> String:
	var code := _first_code_of(action)
	return code_display_name(code) if code != "" else ""


## Отображаемое имя привязки для UI: "F", "ЛКМ", "—" для пустого/битого кода.
func code_display_name(code: String) -> String:
	var event := code_to_event(code)
	if event is InputEventKey:
		return OS.get_keycode_string(event.physical_keycode)
	if event is InputEventMouseButton:
		return MOUSE_BUTTON_NAMES.get(event.button_index, "Мышь %d" % event.button_index)
	return "—"


## Кодирует событие ввода в короткую строку для сейва: "key:70", "mouse:1".
## "" — событие непривязываемого типа (движение мыши, джойстик и т.п.).
##
## Не static, хотя от состояния не зависит: class_name у скрипта нет (его имя
## занято автолоадом), поэтому единственный способ дозваться до кодека — через
## инстанс автолоада, а статический вызов на инстансе парсер считает ошибкой.
func event_to_code(event: InputEvent) -> String:
	if event is InputEventKey:
		# physical_keycode: привязка к ФИЗИЧЕСКОЙ клавише, чтобы WASD не разъезжались
		# на не-QWERTY раскладках (так же заданы действия в project.godot).
		var key := event as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return "key:%d" % code
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	return ""


## Обратная операция к event_to_code. null, если строка не разбирается.
func code_to_event(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	match parts[0]:
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(parts[1]) as Key
			return key
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(parts[1]) as MouseButton
			return mouse
	return null


func _snapshot_default_codes() -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		_default_codes[action] = _first_code_of(action)


## Первая привязка действия, которую мы умеем кодировать (клавиша или кнопка
## мыши). Действия в project.godot имеют по одному событию, но перебор надёжнее.
func _first_code_of(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		var code := event_to_code(event)
		if code != "":
			return code
	return ""
