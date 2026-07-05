# res://src/resources/rs_settings.gd
# Чистые данные — никакой логики.
class_name RS_Settings
extends Resource

@export_group("Mouse")
@export var mouse_sensitivity: float = 0.0015  ## Умножается на 1000
@export var pitch_limit: float = 1.4           ## ~80° в радианах

@export_group("Movement")
@export var move_speed: float = 5.0
@export var jump_velocity: float = 6.0
@export var gravity: float = 9.8

@export_group("Camera")
@export var fov: float = 103.0

@export_group("Graphics")
@export var max_fps: int = 60
