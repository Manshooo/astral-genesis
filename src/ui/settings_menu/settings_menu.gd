# res://src/ui/settings_menu.gd
extends Control

# Откуда пришли — чтобы знать куда вернуться
var caller_node: Control = null

@onready var sensitivity_slider: HSlider = $Panel/MarginContainer/VBox/Sensitivity/HSlider
@onready var sensitivity_label: Label   = $Panel/MarginContainer/VBox/Sensitivity/Value
@onready var speed_slider: HSlider      = $Panel/MarginContainer/VBox/Speed/HSlider
@onready var speed_label: Label         = $Panel/MarginContainer/VBox/Speed/Value
@onready var jump_slider: HSlider       = $Panel/MarginContainer/VBox/Jump/HSlider
@onready var jump_label: Label          = $Panel/MarginContainer/VBox/Jump/Value
@onready var fov_slider: HSlider        = $Panel/MarginContainer/VBox/FOV/HSlider
@onready var fov_label: Label           = $Panel/MarginContainer/VBox/FOV/Value

func _ready() -> void:
	_load_values()

func _load_values() -> void:
	var s := SettingsManager.settings

	sensitivity_slider.value = s.mouse_sensitivity * 1000.0  # 0.002 → 2.0 удобнее для слайдера
	speed_slider.value       = s.move_speed
	jump_slider.value        = s.jump_velocity
	fov_slider.value         = s.fov

	_update_labels()

func _update_labels() -> void:
	sensitivity_label.text = "%.1f" % sensitivity_slider.value
	speed_label.text       = "%.0f" % speed_slider.value
	jump_label.text        = "%.1f" % jump_slider.value
	fov_label.text         = "%.0f" % fov_slider.value

# --- Сигналы слайдеров ---

func _on_sensitivity_changed(value: float) -> void:
	SettingsManager.settings.mouse_sensitivity = value / 1000.0
	sensitivity_label.text = "%.1f" % value

func _on_speed_changed(value: float) -> void:
	SettingsManager.settings.move_speed = value
	speed_label.text = "%.0f" % value

func _on_jump_changed(value: float) -> void:
	SettingsManager.settings.jump_velocity = value
	jump_label.text = "%.1f" % value

func _on_fov_changed(value: float) -> void:
	SettingsManager.settings.fov = value
	fov_label.text = "%.0f" % value

# --- Кнопки ---

func _on_apply_pressed() -> void:
	SettingsManager.save()
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
