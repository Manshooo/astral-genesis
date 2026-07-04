extends Control

var caller_node: Control = null

@onready var apply_button: Button = $Panel/MarginContainer/VBox/Buttons/Apply
@onready var settings_list: Control = $Panel/MarginContainer/VBox

var _controls: Array = []

## Черновик — независимая копия настроек. Все контролы читают/пишут ТОЛЬКО сюда.
## SettingsManager.settings трогается один-единственный раз — в _on_apply_pressed().
var _draft: RS_Settings
var _baseline: Dictionary = {}

func _ready() -> void:
	_collect_controls(settings_list)
	_load_values()

func _collect_controls(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("get_setting_value") and child.has_method("set_setting_value"):
			_controls.append(child)
			if child.has_signal("setting_changed"):
				child.setting_changed.connect(_on_any_setting_changed)
		else:
			_collect_controls(child)

func _load_values() -> void:
	_draft = SettingsManager.settings.duplicate()
	_apply_draft_to_controls()
	_capture_baseline()

func _apply_draft_to_controls() -> void:
	for control in _controls:
		var key: String = control.setting_key
		if key != "" and key in _draft:
			control.set_setting_value(_draft.get(key))

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

## disabled+flat по умолчанию ("невидимая" кнопка), становится обычной активной
## кнопкой, как только черновик отличается от последнего применённого состояния.
func _update_apply_button() -> void:
	var dirty := _has_unsaved_changes()
	apply_button.disabled = not dirty
	apply_button.flat = not dirty

func _on_any_setting_changed(control: Variant) -> void:
	_draft.set(control.setting_key, control.get_setting_value())
	_update_apply_button()

func _on_apply_pressed() -> void:
	SettingsManager.settings = _draft
	SettingsManager.save()
	_load_values()  # новый _draft = свежая копия применённых настроек, baseline сбрасывается

func _on_back_pressed() -> void:
	# Черновик просто отбрасывается — SettingsManager.settings не трогали ни разу
	# во время редактирования, так что откатывать физически нечего.
	_go_back()

func _on_reset_pressed() -> void:
	_draft = SettingsManager.default_settings()
	_apply_draft_to_controls()
	_update_apply_button()  # baseline НЕ трогаем — Reset это тоже "незафиксированное" изменение

func _go_back() -> void:
	if caller_node:
		caller_node.show()
	queue_free()
