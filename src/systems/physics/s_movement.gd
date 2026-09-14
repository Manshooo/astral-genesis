# res://src/systems/physics/s_movement.gd
# Группа: "physics". Применяет C_Velocity к CharacterBody3D через
# move_and_slide(). Работает для ВСЕХ entity с C_Velocity: игрок, NPC, враги —
# всем одинаково. Ничего не знает об игроке или AI — только физика.
class_name S_Movement
extends System

## Высота порога, которую move_and_slide() перешагивает сам, без прыжка —
## дверные пороги и мелкие ступеньки комнатной геометрии ниже этого не должны
## останавливать ходьбу (см. врез ниже).
const STEP_HEIGHT := 0.16


func query() -> QueryBuilder:
	return q.with_all([C_Velocity]).iterate([C_Velocity])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	var velocity_comps: Array = components[0]

	for i in entities.size():
		var vel := velocity_comps[i] as C_Velocity

		var node: Node = entities[i]
		var body := node as CharacterBody3D
		if not body:
			continue

		var was_on_floor := body.is_on_floor()
		var pre_move_position := body.global_position
		var intended_speed := Vector2(vel.velocity.x, vel.velocity.z).length()

		body.velocity = vel.velocity
		body.move_and_slide()

		# move_and_slide() трактует ЛЮБОЙ вертикальный выступ как стену — годно
		# для настоящих стен, но дверной порог или кромка ступеньки высотой в
		# несколько сантиметров стеной не является нигде, кроме физики. Признак
		# «уткнулись в порог, а не решили остановиться» — заметная недостача
		# горизонтального пути при непустом намерении двигаться; сравниваем с
		# половиной ожидаемого, чтобы не путать с честным скольжением вдоль
		# наклонной стены. Только для тех, кто СТОЯЛ на полу — в воздухе (прыжок,
		# полёт) перешагивать нечего и незачем. vel.velocity.y > 0 отдельно —
		# это как раз прыжок, ЗАДАННЫЙ этим же кадром (S_Jump идёт перед
		# S_Movement): манёвр внутри себя гасит вертикальную скорость до
		# отрицательной ради снапа на пол (см. _try_step) и тем самым сожрал бы
		# только что начавшийся прыжок целиком.
		if was_on_floor and intended_speed > 0.01 and vel.velocity.y <= 0.0:
			var moved := Vector2(
				body.global_position.x - pre_move_position.x,
				body.global_position.z - pre_move_position.z
			).length()
			if moved < intended_speed * delta * 0.5:
				_try_step(body, vel.velocity, pre_move_position)

		vel.velocity = body.velocity


## Порог/ступенька ниже STEP_HEIGHT — не стена: приподнимаем тело над ней,
## повторяем то же горизонтальное движение (уже НАД препятствием) и опускаем
## обратно на пол. Тот же приём, что «step offset» в других движках, только
## руками через move_and_collide() — у CharacterBody3D его нет из коробки.
##
## Манёвр самокорректируется, если ступеньки не было или она выше STEP_HEIGHT:
## подняться, не сдвинуться дальше (упёрлись в ту же стену выше) и опуститься
## обратно — тело окажется там же, где его и оставил обычный move_and_slide()
## чуть выше. Поэтому неудачную попытку не нужно откатывать отдельным путём.
func _try_step(body: CharacterBody3D, velocity: Vector3, pre_move_position: Vector3) -> void:
	var post_slide_position := body.global_position
	body.global_position = pre_move_position

	var up := body.move_and_collide(Vector3.UP * STEP_HEIGHT)
	var risen: float = STEP_HEIGHT if up == null else up.get_travel().y
	if risen < 0.01:
		# Ни сантиметра — прямо над головой потолок, поднимать нечего.
		# Оставляем тело там, где его и притормозил обычный move_and_slide().
		body.global_position = post_slide_position
		return

	body.velocity = velocity
	body.move_and_slide()
	# Спускаем чуть больше, чем поднимали: гарантированно долетаем до
	# настоящей поверхности (пол ступеньки или тот же пол, если ступеньки не
	# было), а не отматываем назад фиксированное расстояние.
	body.move_and_collide(Vector3.DOWN * (risen + 0.05))

	# move_and_collide() выше НЕ обновляет is_on_floor() — этот флаг считает
	# только move_and_slide(), а последним его вызовом был слайд НА ВЕСУ (тело
	# приподнято на risen). Без обновления флаг до конца кадра лгал бы «в
	# воздухе», даже когда манёвр сработал вхолостую и тело реально стоит на
	# полу (упёрлись в настоящую стену, а не ступеньку) — S_Jump в следующем
	# кадре отказывал бы в прыжке стоя на земле. Горизонталь уже отработана
	# выше, поэтому здесь ноль. Скорость по Y — принудительный маленький
	# толчок вниз, а не остаток body.velocity.y: на полу он уже погашен
	# предыдущим контактом и часто ровно 0, а move_and_slide() с velocity=ZERO
	# снап на пол не считает вовсе. (Гасить положительную vy сюда не может —
	# process() выше не запускает манёвр на кадре с активным прыжком.)
	body.velocity = Vector3(0.0, minf(body.velocity.y, -0.1), 0.0)
	body.move_and_slide()
