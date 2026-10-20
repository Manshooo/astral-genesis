# res://src/systems/physics/s_flight.gd
# Группа "physics". Свободный полёт — возможность бестелесного БФЖ. Гравитацию выключает сам C_Flight (S_Gravity: with_none). Отличий от S_Walk два: направление в базисе КАМЕРЫ
# (смотришь вниз — летишь вниз) и скорость подтягивается к желаемой, гаснет при отпущенных клавишах. Защёлку jump_pressed гасит S_Jump — здесь не трогать.
class_name S_Flight
extends System


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_Velocity, C_Flight]).iterate(
		[C_PlayerInput, C_Velocity, C_Flight]
	)


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	var input_comps: Array = components[0]
	var velocity_comps: Array = components[1]
	var flight_comps: Array = components[2]

	for i in entities.size():
		var inp := input_comps[i] as C_PlayerInput
		var vel := velocity_comps[i] as C_Velocity
		var flight := flight_comps[i] as C_Flight
		# Полёт по взгляду — нужна камера; «по корпусу» без неё была бы другая механика.
		var player := entities[i] as E_Player
		if player == null or player.camera == null:
			continue

		var target := Vector3.ZERO
		if inp.move_direction != Vector3.ZERO:
			var basis := player.camera.global_transform.basis
			target = (basis * inp.move_direction).normalized() * flight.speed

		# Разгон и затухание — разные числа: набирать ход охотнее, чем останавливаться.
		var rate := flight.acceleration if target != Vector3.ZERO else flight.damping
		vel.velocity = vel.velocity.move_toward(target, rate * delta)
