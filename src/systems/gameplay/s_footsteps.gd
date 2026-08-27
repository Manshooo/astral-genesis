# res://src/systems/gameplay/s_footsteps.gd
# Группа: "gameplay". Отмеряет шаги идущего тела и просит AudioManager сыграть
# звук — по одному звуку на пройденный шаг.
#
# Путь, а не таймер: частота шагов обязана следовать скорости, иначе крадущееся
# тело топает как бегущее. Скорость берётся из C_Velocity — то есть фактическая,
# уже с перками и с тем, что тело реально выдаёт, а не из желаемого ввода.
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

		# В воздухе (прыжок, полёт, падение) путь не копится: шаг — это касание
		# земли, а не пройденное расстояние само по себе.
		if speed < MIN_SPEED or not body.is_on_floor():
			# Взводим на полный шаг, чтобы первый же шаг после остановки прозвучал
			# сразу, а не через два метра тишины — иначе начало движения читается
			# как рассинхрон звука с картинкой.
			steps.travelled = steps.stride
			continue

		steps.travelled += speed * delta
		if steps.travelled < steps.stride:
			continue

		# Вычитание, а не обнуление: переработка сверх шага переходит в следующий,
		# и на большой скорости частота не «съезжает» вниз от округления к кадру.
		steps.travelled -= steps.stride
		AudioManager.play_event_3d(steps.event_path, body.global_position)
