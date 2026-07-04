# res://src/ui/settings/checkbox_setting.gd
class_name CheckboxSetting
extends CheckButton

@export var setting_key: String = ""

signal setting_changed(control: CheckboxSetting)

func _ready() -> void:
	toggled.connect(func(_p): setting_changed.emit(self))

func get_setting_value() -> bool:
	return button_pressed

func set_setting_value(v: Variant) -> void:
	button_pressed = bool(v)
