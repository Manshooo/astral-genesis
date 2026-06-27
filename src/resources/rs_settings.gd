# res://src/resources/rs_settings.gd
# Чистые данные — никакой логики.
# Создай файл через инспектор: ПКМ на папку → New Resource → RS_Settings
# Сохрани как res://data/settings.tres
class_name RS_Settings
extends Resource

@export_group("Mouse")
@export var mouse_sensitivity: float = 0.002
@export var pitch_limit: float = 1.4       # ~80° в радианах

@export_group("Movement")
@export var move_speed: float = 5.0
@export var jump_velocity: float = 6.0
@export var gravity: float = 9.8

@export_group("Camera")
@export var fov: float = 90.0
