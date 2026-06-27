extends Node3D

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	# Активируем камеру
	camera.make_current()
	
	# Запускаем анимацию камеры
	_animate_camera()

func _animate_camera() -> void:
	var tween = create_tween()
	tween.set_loops()  # бесконечный цикл
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Лёгкое покачивание — смещение позиции
	var base_pos = camera.position
	tween.tween_property(camera, "position",
		base_pos + Vector3(2.0, 0.5, 1.0), 6.0)
	tween.tween_property(camera, "position",
		base_pos, 6.0)
