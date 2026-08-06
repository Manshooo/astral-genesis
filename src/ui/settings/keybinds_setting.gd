# res://src/ui/settings/keybinds_setting.gd
## Блок переназначения клавиш в меню настроек. Строки (действие + кнопка с
## текущей привязкой) строятся в рантайме по SettingsManager.REBINDABLE_ACTIONS —
## список действий живёт там, а не в сцене.
##
## Для settings_menu это ОДИН контрол: раз он реализует get/set_setting_value и
## сигнал setting_changed, _collect_controls внутрь не спускается, и весь словарь
## keybinds ходит в черновик/из черновика целиком (как одно значение настройки).
class_name KeybindsSetting
extends VBoxContainer

## Ключ свойства в RS_Settings — тот же контракт, что у SliderSetting.
@export var setting_key: String = "keybinds"

signal setting_changed(control: KeybindsSetting)

## Что показывает кнопка, пока ждём нажатия.
const CAPTURE_HINT := "жми клавишу"

## Черновик переопределений: action → код события. Только ОТЛИЧИЯ от
## project.godot (см. RS_Settings.keybinds), поэтому пустой словарь = дефолт.
var _codes: Dictionary[StringName, String] = {}
var _buttons: Dictionary[StringName, Button] = {}
## Действие, для которого сейчас ловим нажатие (&"" — не ловим).
var _capturing: StringName = &""


func _ready() -> void:
	for action: StringName in SettingsManager.REBINDABLE_ACTIONS:
		_buttons[action] = _build_row(action)
	_refresh_buttons()


func _build_row(action: StringName) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = SettingsManager.REBINDABLE_ACTIONS[action]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(120, 0)
	button.pressed.connect(_begin_capture.bind(action))
	row.add_child(button)

	add_child(row)
	return button


# --- Контракт настройки (см. settings_menu._collect_controls) ---------------


func get_setting_value() -> Dictionary:
	return _codes.duplicate()  # новый словарь: черновик не должен делить его с нами


func set_setting_value(v: Variant) -> void:
	# Переливаем поэлементно, а не присваиваем: сюда прилетает и типизированный
	# Dictionary из RS_Settings, и пустой нетипизированный литерал.
	_codes.clear()
	if v is Dictionary:
		for action in (v as Dictionary):
			_codes[StringName(action)] = String((v as Dictionary)[action])
	_cancel_capture()
	_refresh_buttons()


# --- Захват нажатия --------------------------------------------------------


func _begin_capture(action: StringName) -> void:
	if _capturing != &"":
		return  # уже ловим другое действие
	_capturing = action
	_buttons[action].text = CAPTURE_HINT


## Ловим в _input, а не в _unhandled_input: иначе Esc успеет дойти до
## UIManager и закрыть экран настроек вместо отмены захвата, а нажатие на
## клавише-действии — до игровых систем.
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


## Ставит [param code] действию. Конфликт разрешаем СВОПОМ: если код уже занят
## другим действием, оно получает старую привязку переназначаемого. Так ни одно
## действие не остаётся без клавиши и не появляется дубликатов.
func _assign(action: StringName, code: String) -> void:
	if code == "":
		_cancel_capture()
		return

	var previous := _code_of(action)
	for other: StringName in SettingsManager.REBINDABLE_ACTIONS:
		if other != action and _code_of(other) == code:
			_set_code(other, previous)
	_set_code(action, code)

	_cancel_capture()
	setting_changed.emit(self)


## Пишем в черновик только ОТЛИЧИЯ от project.godot: совпало с дефолтом — убираем
## запись, иначе сейв обрастает переопределениями, которые ничего не меняют.
func _set_code(action: StringName, code: String) -> void:
	if code == SettingsManager.default_code_for(action):
		_codes.erase(action)
	else:
		_codes[action] = code


## Действующая привязка с учётом черновика: своё переопределение или дефолт.
func _code_of(action: StringName) -> String:
	var code: String = _codes.get(action, "")
	return code if code != "" else SettingsManager.default_code_for(action)


func _cancel_capture() -> void:
	_capturing = &""
	_refresh_buttons()


func _refresh_buttons() -> void:
	for action: StringName in _buttons:
		_buttons[action].text = SettingsManager.code_display_name(_code_of(action))
