# res://src/systems/physics/s_flight.gd
# Группа: "physics". Свободный полёт — возможность бестелесного БФЖ.
#
# Гравитацию эта система не выключает: за неё это делает сам факт наличия
# C_Flight, потому что S_Gravity объявляет with_none([C_Flight]). Одна причина —
# одно место.
#
# Отличий от шага (S_Walk) ровно два, и оба — смысл механики, а не настройка:
#   - направление в базисе КАМЕРЫ: смотришь вниз — летишь вниз, и отдельные
#     клавиши «вверх/вниз» не нужны;
#   - скорость не выставляется мгновенно, а подтягивается к желаемой и гаснет при
#     отпущенных клавишах — отсюда «плывущее» ощущение бестелесности.
#
# Прыжка у летающего нет и не нужно: подниматься он умеет взглядом. Защёлку
# jump_pressed гасит S_Jump своей второй выборкой — здесь её трогать нельзя,
# иначе гашение окажется в двух местах и разъедется.
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
		# Полёт по взгляду, значит нужна камера. Летать «по корпусу» при её
		# отсутствии не пытаемся: это была бы другая механика, молча подменившая
		# эту.
		var player := entities[i] as E_Player
		if player == null or player.camera == null:
			continue

		var target := Vector3.ZERO
		if inp.move_direction != Vector3.ZERO:
			var basis := player.camera.global_transform.basis
			target = (basis * inp.move_direction).normalized() * flight.speed

		# Разгон и затухание — разные числа: набирать ход призрак должен охотнее,
		# чем останавливаться, иначе инерция читается как залипшее управление.
		var rate := flight.acceleration if target != Vector3.ZERO else flight.damping
		vel.velocity = vel.velocity.move_toward(target, rate * delta)
