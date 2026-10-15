# res://src/systems/physics/s_enemy_ai.gd
# Группа: "physics" — пишет в C_EnemyInput.move_direction, который в этом же
# физкадре читает S_Walk (Runs.Before), и оба целиком полагаются на
# move_and_slide() из S_Movement, так что порядок обязан остаться внутри
# одного физпрохода. Лучи обзора тоже бросаются отсюда: space-state Jolt
# безопасен только из физпотока.
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
# ОБНАРУЖЕНИЕ — линия видимости и угол обзора (C_EnemyAI.view_angle). Замечает
# цель ТОЛЬКО тот, кто её видит: в радиусе, в конусе перед собой (вплотную — и
# со спины) и без стены на луче от глаз к глазам цели. Луч бросается раз в
# sight_interval, а не каждый кадр; между проверками враг живёт прежним
# результатом. Конус нужен, чтобы заметить, а не чтобы удержать: уже
# встревоженный враг (гонится или ищет) смотрит на цель, и ему хватает луча.
#
# ПАМЯТЬ. Потерявший цель из виду идёт туда, где видел её последний раз
# (SEARCHING), стоит там linger_time и сдаётся (IDLE). Увидел снова на пути —
# гонится дальше. Враг не знает, куда цель делась потом: ни слуха, ни следов.
#
# ПУТЬ идёт по навмешу слоя (LayerNavigation: запекается на спавне слоя из
# коллизии, а не в редакторе) — NavigationServer3D.map_get_path, не каждый кадр
# (repath_interval), по точкам. Пока навмеш не готов или цели на нём нет, карта
# отдаёт пустой путь, и враг идёт по прямой, как шёл без навигации: упрётся в
# стену через move_and_slide(), но не встанет столбом.
#
# move_direction остаётся в МИРОВОМ базисе: враг довёрнут к точке пути look_at
# (глобальный поворот), и «вперёд» (−Z тела) уже направлено к ней. S_Walk
# переводит его в мир через global_transform — родитель врага (комната) бывает
# повёрнут.
class_name S_EnemyAI
extends System

## Чем враг бьёт — атрибуция удара для сводки забега (S_Health.Damage.means).
## Одно значение на всех врагов: разных атак у них пока нет, а когда появятся,
## различать их будет по этому же полю.
const MEANS := &"enemy_melee"

## Куда целится луч, если цель — не E_Player (нет камеры): глаза на этой высоте
## над ногами. У игрока берётся его камера, то есть глаза текущего тела.
const FALLBACK_TARGET_EYE := 1.5


func deps() -> Dictionary[int, Array]:
	return {Runs.Before: [S_Walk]}


func query() -> QueryBuilder:
	# C_Dead исключён: S_Health вешает его, как только HP упало до нуля, а труп на
	# место врага встаёт отложенно (O_EnemyDeath) — в это окно мёртвый не должен
	# ни бить, ни идти.
	return q.with_all([C_EnemyAI, C_EnemyInput, C_Velocity, C_Walk]).with_none([C_Dead])


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
			_stand_down(ai, inp)
			continue

		var offset := target_node.global_position - node.global_position
		offset.y = 0.0
		var distance := offset.length()

		var fresh_check := _update_sight(ai, node, target, target_node, offset, distance, delta)
		_update_state(ai, target_node, fresh_check, delta)

		match ai.state:
			C_EnemyAI.State.CHASING:
				if distance <= ai.attack_range:
					# Стоим на месте и бьём — S_Walk на нулевом move_direction тоже
					# погасит остаточную горизонтальную скорость, отдельно обнулять
					# vel.velocity здесь не нужно.
					if distance > 0.001:
						node.look_at(node.global_position + offset, Vector3.UP)
					inp.move_direction = Vector3.ZERO
					_attack(entity, target, ai)
				else:
					# К месту, где видели цель в последний раз (обновляется с каждой
					# проверкой обзора), а не к её нынешнему: между проверками враг
					# не должен знать о цели больше, чем увидел.
					_steer(ai, node, inp, ai.last_seen_position, delta)
			C_EnemyAI.State.SEARCHING:
				_search(ai, node, inp, delta)
			_:
				inp.move_direction = Vector3.ZERO


## Цели нет (душа без тела, мир без игрока): враг забывает всё и стоит.
func _stand_down(ai: C_EnemyAI, inp: C_EnemyInput) -> void:
	ai.state = C_EnemyAI.State.IDLE
	ai.sees_target = false
	ai.path = PackedVector3Array()
	inp.move_direction = Vector3.ZERO


# --- Обнаружение ---


## Раз в sight_interval выясняет, видит ли враг цель. Между проверками результат
## тот же: цель за пятую долю секунды не успевает уйти далеко, а луч на каждый
## кадр каждого врага был бы расходом без выгоды. true — проверка была на ЭТОМ
## кадре: место «видел последний раз» обновляется только по свежей проверке, иначе
## устаревший результат подглядывал бы за целью, которую враг уже не видит.
func _update_sight(
	ai: C_EnemyAI,
	node: Node3D,
	target: Entity,
	target_node: Node3D,
	offset: Vector3,
	distance: float,
	delta: float,
) -> bool:
	ai.sight_left -= delta
	if ai.sight_left > 0.0:
		return false
	# Разброс периода — чтобы враги, увидевшие игрока в один кадр, не бросали
	# лучи пачкой раз в период до конца забега.
	ai.sight_left = ai.sight_interval * randf_range(0.8, 1.2)
	ai.sees_target = _can_see(ai, node, target, target_node, offset, distance)
	return true


func _can_see(
	ai: C_EnemyAI,
	node: Node3D,
	target: Entity,
	target_node: Node3D,
	offset: Vector3,
	distance: float,
) -> bool:
	if distance > ai.aggro_range:
		return false

	# Конус — только чтобы ЗАМЕТИТЬ, и не вплотную: см. шапку.
	if ai.state == C_EnemyAI.State.IDLE and distance > ai.awareness_range:
		var facing := -node.global_basis.z
		facing.y = 0.0
		if facing.angle_to(offset) > deg_to_rad(ai.view_angle) * 0.5:
			return false

	var from := node.global_position + Vector3.UP * ai.eye_height
	var to := _eye_of(target, target_node)
	var ray := PhysicsRayQueryParameters3D.create(from, to, ai.sight_mask)
	ai.sight_rays += 1
	var hit := node.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty()


## Глаза цели: у игрока — его камера (глаза текущего тела, высота берётся из
## сцены тела), иначе фиксированная высота над ногами.
func _eye_of(target: Entity, target_node: Node3D) -> Vector3:
	var player := target as E_Player
	if player != null and player.camera != null:
		return player.camera.global_position
	return target_node.global_position + Vector3.UP * FALLBACK_TARGET_EYE


## Переходы состояния по итогу обзора. Увидел — гонится и запоминает место;
## гнавшийся и потерявший — идёт искать; искавший, у кого вышло время, сдаётся.
func _update_state(
	ai: C_EnemyAI, target_node: Node3D, fresh_check: bool, delta: float
) -> void:
	if ai.sees_target:
		ai.state = C_EnemyAI.State.CHASING
		if fresh_check:
			ai.last_seen_position = target_node.global_position
		return

	match ai.state:
		C_EnemyAI.State.CHASING:
			ai.state = C_EnemyAI.State.SEARCHING
			ai.search_left = ai.search_timeout
			ai.arrived = false
			ai.repath_left = 0.0
		C_EnemyAI.State.SEARCHING:
			ai.search_left -= delta
			if ai.search_left <= 0.0:
				ai.state = C_EnemyAI.State.IDLE
				ai.path = PackedVector3Array()


# --- Движение ---


## Идёт на место, где видел цель, а дойдя — стоит и ждёт: время поиска сжимается
## до linger_time, и по его выходу _update_state сдаёт врага в IDLE.
func _search(ai: C_EnemyAI, node: Node3D, inp: C_EnemyInput, delta: float) -> void:
	if not ai.arrived:
		var rest := ai.last_seen_position - node.global_position
		rest.y = 0.0
		if rest.length() <= ai.arrive_distance:
			ai.arrived = true
			ai.search_left = minf(ai.search_left, ai.linger_time)
		else:
			_steer(ai, node, inp, ai.last_seen_position, delta)
			return
	inp.move_direction = Vector3.ZERO


## Шаг к [param goal]: по точкам пути навмеша, а без пути — по прямой.
func _steer(
	ai: C_EnemyAI, node: Node3D, inp: C_EnemyInput, goal: Vector3, delta: float
) -> void:
	ai.repath_left -= delta
	if ai.repath_left <= 0.0:
		ai.repath_left = ai.repath_interval
		var map := node.get_world_3d().navigation_map
		# До первой синхронизации карта на запрос отвечает ошибкой в лог, а не
		# пустым путём: пока она не отработала, пути просто нет.
		if NavigationServer3D.map_get_iteration_id(map) == 0:
			ai.path = PackedVector3Array()
		else:
			ai.path = NavigationServer3D.map_get_path(map, node.global_position, goal, true)
		# Первая точка пути — сам враг.
		ai.path_index = 1

	var aim := goal
	if ai.path.size() > 1:
		while ai.path_index < ai.path.size() - 1 \
				and _flat_distance(node.global_position, ai.path[ai.path_index]) < ai.waypoint_reach:
			ai.path_index += 1
		if ai.path_index < ai.path.size() \
				and _flat_distance(node.global_position, ai.path[ai.path_index]) >= ai.waypoint_reach:
			aim = ai.path[ai.path_index]
		# Иначе дошли до конца пути: он кончается у ближайшей к цели точки навмеша,
		# а сама цель в паре шагов — доходим по прямой.

	var heading := aim - node.global_position
	heading.y = 0.0
	if heading.length_squared() < 0.0001:
		inp.move_direction = Vector3.ZERO
		return
	node.look_at(node.global_position + heading, Vector3.UP)
	inp.move_direction = Vector3.FORWARD


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _attack(entity: Entity, target: Entity, ai: C_EnemyAI) -> void:
	if ai.attack_cooldown_left > 0.0:
		return
	ai.attack_cooldown_left = ai.attack_interval

	# Через воронку, а не записью в C_Health.current: удар обязан оставить след
	# «кто, кому, сколько и чем» — из него собирается сводка забега, и на нём же
	# вырастет всё, что реагирует на урон (см. S_Health.deal_damage).
	S_Health.deal_damage(target, ai.attack_damage, entity, MEANS)


## Единственная цель на всех врагов сразу — одна выборка вне цикла, а не
## sub_systems() с собственным проходом по каждому врагу.
func _find_target() -> Entity:
	return ECS.world.query.with_all([C_BodySnatch, C_Embodied, C_Health]).execute_one()
