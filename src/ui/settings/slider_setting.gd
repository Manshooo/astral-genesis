# res://src/ui/settings/slider_setting.gd
## Настройка-слайдер. Повесить на HSlider, выставить setting_key в инспекторе.
class_name SliderSetting
extends HSlider

@export var setting_key: String = ""
## Множитель для отображения (например mouse_sensitivity хранится как 0.002, а на слайдере — 2.0)
@export var display_multiplier: float = 1.0
@export var display_format: String = "%.1f"
@export var value_label_path: NodePath

signal setting_changed(control: SliderSetting)

var _value_label: Label = null

func _ready() -> void:
	if value_label_path != NodePath():
		_value_label = get_node_or_null(value_label_path)
	value_changed.connect(_on_value_changed)

func get_setting_value() -> float:
	return value / display_multiplier

func set_setting_value(v: Variant) -> void:
	value = float(v) * display_multiplier
	_refresh_label()

func _on_value_changed(_v: float) -> void:
	_refresh_label()
	setting_changed.emit(self)

func _refresh_label() -> void:
	if _value_label:
		_value_label.text = display_format % value
