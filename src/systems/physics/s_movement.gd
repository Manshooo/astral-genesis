# res://src/systems/physics/s_movement.gd
# Группа "physics". Применяет C_Velocity к CharacterBody3D через move_and_slide() — всем одинаково, об игроке и ИИ не знает.
class_name S_Movement
extends System

## Высота порога, которую move_and_slide() перешагивает сам: пороги и мелкие ступеньки ниже не останавливают ходьбу.
const STEP_HEIGHT := 0.16


func query() -> QueryBuilder:
	return q.with_all([C_Velocity]).iterate([C_Velocity])


## ПОСЛЕ всех, кто пишет скорость, иначе применится скорость прошлого тика. Порядок нод не помогает: GECS сортирует группу по Кану, и система с входящей зависимостью уезжает в КОНЕЦ очереди — за S_Movement.
func deps() -> Dictionary[int, Array]:
	return {
		Runs.After: [S_Phasing, S_Gravity, S_EnemyAI, S_Sprint, S_Walk, S_Jump, S_Flight]
	}


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

		# move_and_slide() трактует ЛЮБОЙ вертикальный выступ как стену. Признак «уткнулись в порог» — недостача горизонтального пути при намерении двигаться (меньше половины ожидаемого, чтобы не путать
		# со скольжением вдоль наклонной стены). Только для стоявших на полу; vel.y > 0 — прыжок этого кадра (S_Jump раньше), манёвр погасил бы его.
		if was_on_floor and intended_speed > 0.01 and vel.velocity.y <= 0.0:
			var moved := Vector2(
				body.global_position.x - pre_move_position.x,
				body.global_position.z - pre_move_position.z
			).length()
			if moved < intended_speed * delta * 0.5:
				_try_step(body, vel.velocity, pre_move_position)

		vel.velocity = body.velocity


## Порог ниже STEP_HEIGHT — не стена: приподнимаем тело, повторяем движение над препятствием, опускаем (ручной «step offset» через move_and_collide). Самокорректируется:
## неудачная попытка возвращает тело туда же, где оставил move_and_slide() — отдельный откат не нужен.
func _try_step(body: CharacterBody3D, velocity: Vector3, pre_move_position: Vector3) -> void:
	var post_slide_position := body.global_position
	body.global_position = pre_move_position

	var up := body.move_and_collide(Vector3.UP * STEP_HEIGHT)
	var risen: float = STEP_HEIGHT if up == null else up.get_travel().y
	if risen < 0.01:
		# Ни сантиметра — над головой потолок; оставляем тело там, где его притормозил move_and_slide().
		body.global_position = post_slide_position
		return

	body.velocity = velocity
	body.move_and_slide()
	# Спускаем чуть больше, чем поднимали: гарантированно долетаем до поверхности.
	body.move_and_collide(Vector3.DOWN * (risen + 0.05))

	# move_and_collide() НЕ обновляет is_on_floor(): последний move_and_slide() был НА ВЕСУ, флаг лгал бы «в воздухе» (S_Jump отказывал бы в прыжке на земле). Горизонталь отработана выше — ноль;
	# Y — принудительный толчок вниз, а не остаток velocity.y (на полу он 0, а снап без скорости вниз не считается).
	body.velocity = Vector3(0.0, minf(body.velocity.y, -0.1), 0.0)
	body.move_and_slide()
