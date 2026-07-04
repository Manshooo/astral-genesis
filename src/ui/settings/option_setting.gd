extends Control

var caller_node: Control = null

@onready var apply_button: Button = $Panel/MarginContainer/VBox/Buttons/Apply
@onready var settings_list: Control = $Panel/MarginContainer/VBox  # контейнер со всеми рядами настроек

var _controls: Array = []
var _baseline: Dictionary = {}

func _ready() -> void:
	_collect_controls(settings_list)
	_load_values()

## Рекурсивно находит все узлы, реализующие интерфейс настройки, независимо
## от того, во что они вложены (HBoxContainer, отдельный "ряд" и т.п.)
func _collect_controls(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("get_setting_value") and child.has_method("set_setting_value"):
			_controls.append(child)
			if child.has_signal("setting_changed"):
				child.setting_changed.connect(_on_any_setting_changed)
		else:
			_collect_controls(child)

func _load_values() -> void:
	var s := SettingsManager.settings
	for control in _controls:
		var key: String = control.setting_key
		if key != "" and key in s:
			control.set_setting_value(s.get(key))
	_capture_baseline()

func _capture_baseline() -> void:
	_baseline.clear()
	for control in _controls:
		_baseline[control.setting_key] = control.get_setting_value()
	_update_apply_button()

func _has_unsaved_changes() -> bool:
	for control in _controls:
		var current = control.get_setting_value()
		var base = _baseline.get(control.setting_key)
		if not _values_equal(current, base):
			return true
	return false

func _values_equal(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return is_equal_approx(a, b)
	return a == b

func _update_apply_button() -> void:
	apply_button.disabled = not _has_unsaved_changes()

func _on_any_setting_changed(control: Variant) -> void:
	SettingsManager.settings.set(control.setting_key, control.get_setting_value())
	_update_apply_button()

func _on_apply_pressed() -> void:
	SettingsManager.save()
	_capture_baseline()
	_go_back()

func _on_back_pressed() -> void:
	SettingsManager.settings = SettingsManager._load()
	_go_back()

func _on_reset_pressed() -> void:
	SettingsManager.reset()
	_load_values()

func _go_back() -> void:
	if caller_node:
		caller_node.show()
	queue_free()
