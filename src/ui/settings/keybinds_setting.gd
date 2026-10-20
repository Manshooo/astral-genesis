# res://src/ui/settings/keybinds_setting.gd
## Блок переназначения клавиш: две колонки UI_KeyRow (§9 «Меню — спека») по SettingsManager.REBINDABLE_ACTIONS и строка-сообщение (как отменить ожидание, кто с кем поменялся). Сетка (зазор 56, §4) и сообщение — дети в
## settings_menu.tscn, кодом создаются только строки из key_row.tscn. Для settings_menu это ОДИН контрол (get/set_setting_value и setting_changed): словарь keybinds ходит в черновик целиком.
class_name KeybindsSetting
extends VBoxContainer

## Ключ свойства в RS_Settings — тот же контракт, что у SliderSetting.
@export var setting_key: String = "keybinds"

signal setting_changed(control: KeybindsSetting)

## Сколько держится сообщение об обмене клавишами.
const SWAP_MESSAGE_SECONDS := 3.0

const KEY_ROW_SCENE := preload("res://src/ui/menu/key_row.tscn")

## Черновик переопределений: action → код; только ОТЛИЧИЯ от project.godot, пустой = дефолт.
var _codes: Dictionary[StringName, String] = {}
var _rows: Dictionary[StringName, UI_KeyRow] = {}
## Действие, для которого ловим нажатие (&"" — не ловим).
var _capturing: StringName = &""
var _status_serial := 0

@onready var _grid: GridContainer = $Grid
@onready var _status: Label = $Status


func _ready() -> void:
	for action: StringName in SettingsManager.REBINDABLE_ACTIONS:
		var row: UI_KeyRow = KEY_ROW_SCENE.instantiate()
		_grid.add_child(row)
		row.set_action(tr(SettingsManager.REBINDABLE_ACTIONS[action]))
		row.pressed.connect(_begin_capture.bind(action))
		_rows[action] = row
	_refresh_rows()


# --- Контракт настройки (см. settings_menu._collect_controls) ---


func get_setting_value() -> Dictionary:
	return _codes.duplicate()  # новый словарь: черновик не должен делить его с нами


func set_setting_value(v: Variant) -> void:
	# Переливаем поэлементно: прилетает и типизированный Dictionary из RS_Settings, и пустой литерал.
	_codes.clear()
	if v is Dictionary:
		for action in (v as Dictionary):
			_codes[StringName(action)] = String((v as Dictionary)[action])
	_cancel_capture()


# --- Захват нажатия ---


func _begin_capture(action: StringName) -> void:
	if _capturing != &"":
		return  # уже ловим другое действие
	_capturing = action
	_rows[action].set_waiting(true)
	_show_status(tr("SETTINGS_REBIND_CANCEL") % "Esc", 0.0)


## Ловим в _input, не в _unhandled_input: иначе Esc дошёл бы до UIManager и закрыл экран настроек вместо отмены захвата.
func _input(event: InputEvent) -> void:
	if _capturing == &"":
		return

	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.is_echo():
			return
		if key.keycode == KEY_ESCAPE:
			_cancel_capture()  # отмена, привязка не меняется
		else:
			_assign(_capturing, SettingsManager.event_to_code(key))
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed:
			return
		_assign(_capturing, SettingsManager.event_to_code(mouse))
	else:
		return  # движение мыши и прочее захват не завершает

	get_viewport().set_input_as_handled()


## Ставит code действию. Конфликт — СВОПОМ: занятый другим код получает старую привязку; ни одно действие не остаётся без клавиши.
func _assign(action: StringName, code: String) -> void:
	if code == "":
		_cancel_capture()
		return

	var previous := _code_of(action)
	var swapped: StringName = &""
	for other: StringName in SettingsManager.REBINDABLE_ACTIONS:
		if other != action and _code_of(other) == code:
			_set_code(other, previous)
			swapped = other
	_set_code(action, code)

	_cancel_capture()
	if swapped != &"":
		_rows[swapped].flash()
		_rows[action].flash()
		_show_status(tr("SETTINGS_REBIND_SWAPPED") % [
			tr(SettingsManager.REBINDABLE_ACTIONS[action]),
			tr(SettingsManager.REBINDABLE_ACTIONS[swapped]),
		], SWAP_MESSAGE_SECONDS)
	setting_changed.emit(self)


## В черновик — только ОТЛИЧИЯ от project.godot: совпало с дефолтом — запись убирается.
func _set_code(action: StringName, code: String) -> void:
	if code == SettingsManager.default_code_for(action):
		_codes.erase(action)
	else:
		_codes[action] = code


## Действующая привязка с учётом черновика: переопределение или дефолт.
func _code_of(action: StringName) -> String:
	var code: String = _codes.get(action, "")
	return code if code != "" else SettingsManager.default_code_for(action)


func _cancel_capture() -> void:
	if _capturing != &"" and _status:
		_show_status("", 0.0)
	_capturing = &""
	_refresh_rows()


func _refresh_rows() -> void:
	for action: StringName in _rows:
		_rows[action].set_waiting(false)
		_rows[action].set_key(SettingsManager.code_display_name(_code_of(action)))


## Строка под колонками; [param seconds] > 0 — сама гаснет. Таймер с process_always (настройки поверх паузы); номер вызова не даёт старому таймеру стереть новое.
func _show_status(line: String, seconds: float) -> void:
	_status_serial += 1
	_status.text = line
	if seconds <= 0.0:
		return
	var serial := _status_serial
	await get_tree().create_timer(seconds, true).timeout
	if is_instance_valid(_status) and serial == _status_serial:
		_status.text = ""
