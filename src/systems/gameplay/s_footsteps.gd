# res://src/systems/gameplay/s_footsteps.gd
# Группа: "gameplay". Озвучивает ходьбу тела через byProd — тем способом, каким
# собрано само событие (см. C_Footsteps.Playback): разовым звуком на каждый
# отмеренный шаг или одной петлёй, которой правится темп.
#
# Скорость берётся из C_Velocity — то есть фактическая, уже с перками и с тем,
# что тело реально выдаёт, а не из желаемого ввода.
#
# Группа "gameplay", а не "physics": is_on_floor() — это ЧТЕНИЕ флага, который
# посчитал move_and_slide() в S_Movement, а не запрос к space-state; правило про
# «рейкасты только в physics» сюда не распространяется. Тик реже физического
# здесь даже уместнее: шаг длиной около двух метров не нуждается в разрешении
# в шестьдесят сэмплов на секунду.
class_name S_Footsteps
extends System

## Ниже этой горизонтальной скорости (м/с) шаг не отмеряется: тело либо стоит,
## либо его слегка сносит физикой по инерции, и топать здесь не за что.
const MIN_SPEED := 0.3


func query() -> QueryBuilder:
	return q.with_all([C_Footsteps, C_Velocity])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var steps := entity.get_component(C_Footsteps) as C_Footsteps
		var vel := entity.get_component(C_Velocity) as C_Velocity

		# Entity наследует Node, поэтому до CharacterBody3D — через двойной каст.
		# Незанятое тело в мире — StaticBody3D: оно никуда не идёт, и шагов у него
		# быть не может, сколько бы компонент на нём ни висел.
		var body := entity as Node as CharacterBody3D
		if body == null:
			continue

		var speed := Vector2(vel.velocity.x, vel.velocity.z).length()

		# В воздухе (прыжок, полёт, падение) шагов нет: шаг — это касание земли,
		# а не пройденное расстояние само по себе.
		var walking := speed >= MIN_SPEED and body.is_on_floor()

		if steps.playback == C_Footsteps.Playback.LOOP:
			_loop(steps, speed, walking)
		else:
			_per_step(steps, body, speed, walking, delta)


## Разовое событие: путь копится, и на каждый отмеренный шаг уходит свой звук.
func _per_step(
	steps: C_Footsteps, body: CharacterBody3D, speed: float, walking: bool, delta: float
) -> void:
	if not walking:
		# Взводим на полный шаг, чтобы первый же шаг после остановки прозвучал
		# сразу, а не через два метра тишины — иначе начало движения читается
		# как рассинхрон звука с картинкой.
		steps.travelled = steps.stride
		return

	steps.travelled += speed * delta
	if steps.travelled < steps.stride:
		return

	# Вычитание, а не обнуление: переработка сверх шага переходит в следующий,
	# и на большой скорости частота не «съезжает» вниз от округления к кадру.
	steps.travelled -= steps.stride
	AudioManager.play_event_3d(steps.event_path, body.global_position)


## Зацикленное событие: один инстанс живёт ровно пока тело идёт, темп следует
## скорости. Частота шагов здесь не отмеряется путём, а задаётся самой записью —
## отмерять её второй раз снаружи значило бы спорить с тем, что склеил звуковик.
func _loop(steps: C_Footsteps, speed: float, walking: bool) -> void:
	if not walking:
		if steps.loop_active:
			steps.loop_active = false
			if steps.loop_instance != null:
				steps.loop_instance.stop()
				# Ссылка роняется здесь, а не копится «на потом»: пока её держат,
				# держат и голос. Освобождение делает деструктор биндинга.
				steps.loop_instance = null
		return

	if not steps.loop_active:
		steps.loop_active = true
		# null возвращается штатно — нет расширения, нет рантайма, нет события с
		# таким именем. Тогда тело идёт молча до следующей остановки: спрашивать
		# то же самое каждый кадр не за чем, ответ не переменится.
		steps.loop_instance = AudioManager.create_event_instance(steps.event_path)
		if steps.loop_instance != null:
			steps.loop_instance.start()

	if steps.loop_instance == null or steps.tempo_parameter.is_empty():
		return

	var reference := maxf(steps.tempo_reference_speed, 0.001)
	var tempo := clampf(speed / reference, 0.0, steps.tempo_maximum)
	steps.loop_instance.set_parameter(steps.tempo_parameter, tempo)
