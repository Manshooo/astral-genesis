# res://src/systems/physics/s_flight.gd
# Группа "physics". Свободный полёт — возможность бестелесного БФЖ. Гравитацию выключает сам C_Flight (S_Gravity: with_none). Отличий от S_Walk два: направление по ВЗГЛЯДУ
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
		var player := entities[i] as E_Player
		if player == null:
			continue

		var target := Vector3.ZERO
		if inp.move_direction != Vector3.ZERO:
			# По взгляду игрока — рыскание рига и тангаж, а не базис камеры в глазах: её наводят в точку под
			# прицелом, и у близкой стены или решётки «вперёд» уходило бы круто вверх или вниз.
			var look := player.get_component(C_FPSCamera) as C_FPSCamera
			var pitch := look.pitch if look != null else 0.0
			var basis := Basis.from_euler(Vector3(pitch, (player as Node as Node3D).global_rotation.y, 0.0))
			target = (basis * inp.move_direction).normalized() * flight.speed

		# Разгон и затухание — разные числа: набирать ход охотнее, чем останавливаться.
		var rate := flight.acceleration if target != Vector3.ZERO else flight.damping
		vel.velocity = vel.velocity.move_toward(target, rate * delta)
