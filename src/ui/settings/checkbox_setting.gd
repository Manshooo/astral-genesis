# res://src/ui/settings/checkbox_setting.gd
## Настройка-флажок: кольцо с точкой души (вид — тема CheckBox) и подпись «Вкл/Выкл» рядом (§5 «Меню — спека»): кольцо без точки на тёмном не всякий прочтёт как «выключено».
class_name CheckboxSetting
extends CheckBox

@export var setting_key: String = ""

signal setting_changed(control: CheckboxSetting)


func _ready() -> void:
	toggled.connect(_on_toggled)
	_refresh_text()


func _on_toggled(_pressed: bool) -> void:
	_refresh_text()
	setting_changed.emit(self)


func get_setting_value() -> bool:
	return button_pressed


func set_setting_value(v: Variant) -> void:
	# set_pressed_no_signal: значение из черновика — не правка игрока, setting_changed зажёг бы «Применить».
	set_pressed_no_signal(bool(v))
	_refresh_text()


func _refresh_text() -> void:
	text = "SETTINGS_ON" if button_pressed else "SETTINGS_OFF"
