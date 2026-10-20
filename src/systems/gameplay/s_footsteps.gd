# res://src/systems/gameplay/s_footsteps.gd
# Группа "gameplay". Озвучивает ходьбу через byProd тем способом, каким собрано событие (C_Footsteps.Playback): разовый звук на шаг или петля с темпом.
# Скорость — из C_Velocity (фактическая). Не "physics": is_on_floor() — чтение флага move_and_slide(), не запрос к space-state. Вики: [[Звук]] §3.
class_name S_Footsteps
extends System

## Ниже этой горизонтальной скорости (м/с) шаг не отмеряется.
const MIN_SPEED := 0.3


func query() -> QueryBuilder:
	return q.with_all([C_Footsteps, C_Velocity])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var steps := entity.get_component(C_Footsteps) as C_Footsteps
		var vel := entity.get_component(C_Velocity) as C_Velocity

		# Entity наследует Node — до CharacterBody3D через двойной каст. Незанятое тело (StaticBody3D) шагов не имеет.
		var body := entity as Node as CharacterBody3D
		if body == null:
			continue

		var speed := Vector2(vel.velocity.x, vel.velocity.z).length()

		# В воздухе шагов нет: шаг — касание земли.
		var walking := speed >= MIN_SPEED and body.is_on_floor()

		if steps.playback == C_Footsteps.Playback.LOOP:
			_loop(steps, speed, walking)
		else:
			_per_step(steps, body, speed, walking, delta)


## Разовое событие: путь копится, на каждый отмеренный шаг — свой звук.
func _per_step(
	steps: C_Footsteps, body: CharacterBody3D, speed: float, walking: bool, delta: float
) -> void:
	if not walking:
		# Взводим на полный шаг: первый шаг после остановки звучит сразу.
		steps.travelled = steps.stride
		return

	steps.travelled += speed * delta
	if steps.travelled < steps.stride:
		return

	# Вычитание, а не обнуление: переработка сверх шага переходит в следующий.
	steps.travelled -= steps.stride
	AudioManager.play_event_3d(steps.event_path, body.global_position)


## Зацикленное событие: один инстанс, пока тело идёт, темп следует скорости; частоту задаёт сама запись.
func _loop(steps: C_Footsteps, speed: float, walking: bool) -> void:
	if not walking:
		if steps.loop_active:
			steps.loop_active = false
			if steps.loop_instance != null:
				steps.loop_instance.stop()
				# Ссылку роняем сразу: пока её держат, держат и голос (освобождает деструктор биндинга).
				steps.loop_instance = null
		return

	if not steps.loop_active:
		steps.loop_active = true
		# null — штатно (нет расширения, рантайма, события): тело идёт молча, спрашивать каждый кадр незачем.
		steps.loop_instance = AudioManager.create_event_instance(steps.event_path)
		if steps.loop_instance != null:
			steps.loop_instance.start()

	if steps.loop_instance == null or steps.tempo_parameter.is_empty():
		return

	var reference := maxf(steps.tempo_reference_speed, 0.001)
	var tempo := clampf(speed / reference, 0.0, steps.tempo_maximum)
	steps.loop_instance.set_parameter(steps.tempo_parameter, tempo)
