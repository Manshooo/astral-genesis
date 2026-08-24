# res://src/systems/physics/s_enemy_ai.gd
# Группа: "physics" — пишет в C_EnemyInput.move_direction, который в этом же
# физкадре читает S_Walk (Runs.Before), и оба целиком полагаются на
# move_and_slide() из S_Movement, так что порядок обязан остаться внутри
# одного физпрохода.
#
# ВРАГ ДВИЖЕТСЯ ТЕМ ЖЕ СПОСОБОМ, ЧТО ИГРОК, НО НЕ ЕГО КАНАЛОМ: C_EnemyInput —
# отдельный компонент той же формы, что C_PlayerInput, который S_Walk умеет
# читать через свою вторую выборку. НЕ C_PlayerInput: первая версия вешала его
# на врага ради бесплатного доступа к S_Walk, и это сломало добрый десяток
# мест, которые находят «игрока» просто по наличию C_PlayerInput
# (RunManager.travel_to, S_InteractionDetector, HUD) — с двумя такими
# сущностями в мире `execute_one()` мог вернуть врага, и переход через дверь
# молча промахивался мимо настоящего игрока (найдено живым прогоном).
#
# ЦЕЛЬ — ТОЛЬКО ВОПЛОЩЁННЫЙ БФЖ (у него есть C_Health, то есть есть что
# терять). Призрака враг не замечает: гнаться за тем, кого нельзя ранить, была
# бы декорацией, а не угрозой, а «тело — это риск» само по себе держит тему
# версии — выбор тела под давлением. Ищем по C_BodySnatch — этот компонент
# уникален для игрока (E_Player.define_components()), в отличие от
# C_PlayerInput/C_EnemyInput, которые теперь у разных сущностей порознь.
#
# Без линии обзора и навигации: комнаты небольшие и открытые, а простая
# погоня по прямой — весь заявленный объём задачи. Если враг решит идти
# сквозь стену на цель за ней, его тем не менее остановит move_and_slide —
# просто выглядеть это будет как «уткнулся в стену», а не как баг геометрии.
class_name S_EnemyAI
extends System


func deps() -> Dictionary[int, Array]:
	return {Runs.Before: [S_Walk]}


func query() -> QueryBuilder:
	return q.with_all([C_EnemyAI, C_EnemyInput, C_Velocity, C_Walk])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	var target := _find_target()
	var target_node: Node3D = null
	if target != null:
		target_node = target as Node as Node3D

	for entity in entities:
		var ai := entity.get_component(C_EnemyAI) as C_EnemyAI
		var inp := entity.get_component(C_EnemyInput) as C_EnemyInput
		var node := entity as Node as Node3D
		if node == null:
			continue

		ai.attack_cooldown_left = maxf(0.0, ai.attack_cooldown_left - delta)

		if target_node == null:
			ai.state = C_EnemyAI.State.IDLE
			inp.move_direction = Vector3.ZERO
			continue

		var offset := target_node.global_position - node.global_position
		offset.y = 0.0
		var distance := offset.length()

		if distance > ai.aggro_range:
			ai.state = C_EnemyAI.State.IDLE
			inp.move_direction = Vector3.ZERO
			continue

		ai.state = C_EnemyAI.State.CHASING
		node.look_at(node.global_position + offset, Vector3.UP)

		if distance <= ai.attack_range:
			# Стоим на месте и бьём — S_Walk на нулевом move_direction тоже
			# погасит остаточную горизонтальную скорость, отдельно обнулять
			# vel.velocity здесь не нужно.
			inp.move_direction = Vector3.ZERO
			_attack(target, ai)
		else:
			# Только что довернулись к цели (look_at выше) — вперёд для тела
			# и есть «к цели», как договорено для взгляда всех тел (−Z).
			inp.move_direction = Vector3.FORWARD


func _attack(target: Entity, ai: C_EnemyAI) -> void:
	if ai.attack_cooldown_left > 0.0:
		return
	ai.attack_cooldown_left = ai.attack_interval

	# Прямая запись C_Health.current — намеренно: S_Health (группа "gameplay")
	# только клэмпит и объявляет смерть, а урон — дело боевых систем, как
	# прямо сказано в его собственном комментарии.
	var health := target.get_component(C_Health) as C_Health
	health.current -= ai.attack_damage


## Единственная цель на всех врагов сразу — одна выборка вне цикла, а не
## sub_systems() с собственным проходом по каждому врагу.
func _find_target() -> Entity:
	return ECS.world.query.with_all([C_BodySnatch, C_Embodied, C_Health]).execute_one()
