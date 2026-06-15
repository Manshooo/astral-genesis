extends Node3D

# В новом сценарии нам нужен только доступ к дочерней ноде, где находится камера.
@onready var camera_node := $Camera3D

var yaw: float = 0
var pitch: float = 0
const MIN_PITCH: float = -1.4
const MAX_PITCH: float = 1.4

# Подключаем функцию обработки ввода, чтобы она срабатывала каждый кадр (или только при движении)
func _input(event: InputEvent):
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		var sens = SettingsManager.get_mouse_sensitivity()

		# 1. Обновление углов
		yaw -= event.relative.x * sens
		pitch -= event.relative.y * sens
		
		# Ограничение вертикального наклона (Pitch)
		pitch = clamp(pitch, MIN_PITCH, MAX_PITCH)

		# 2. Применение вращения Yaw (Горизонтальное вращение игрока/mount)
		# Вращаем всю ноду cameramount на оси Y
		rotation.y = deg_to_rad(yaw) # Используем радианы для Godot

		# 3. Применение вращения Pitch (Вертикальный наклон камеры)
		# Мы вращаем дочернюю камеру относительно её родителя (cameramount).
		# Это предотвращает "падание" или смещение горизонтального обзора при наклоне вверх/вниз.
		camera_node.rotation.x = deg_to_rad(pitch)
