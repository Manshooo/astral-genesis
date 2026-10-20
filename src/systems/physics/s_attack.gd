# res://src/systems/physics/s_attack.gd
# Группа "physics": луч от камеры (Jolt на своём потоке). Ближний удар тела по «attack» (защёлка C_PlayerInput.attack_pressed): ближайшая живая цель под крестиком в пределах
# C_Attack.reach, урон через воронку S_Health. Способность — компонент и своя система. Вторая выборка — те, у кого удара НЕТ: защёлку гасит тот, кто её съел (см. S_Jump);
# «нечем» сообщаем только игроку ВО ПЛОТИ (призрак бить не умеет по замыслу).
class_name S_Attack
extends System

## Чем бьём — атрибуция для сводки забега (S_Health.Damage.means).
const MEANS := &"attack"

## Класс угрозы существ дна; удар тела ниже этого класса по такому существу ослаблен (L5_RESISTANCE).
const L5_CLASS := 5

## Во сколько раз слабее бьёт тело ниже L5 по существу L5 ([[Игровой цикл — от и до]] §2, решение 15.10): десятая доля, не ноль — нулевой урон неотличим от бага. Число черновое.
const L5_RESISTANCE := 0.1

## Слой enemies (бит 2): живые враги и кости трупов.
const ENEMIES_BIT := 1 << 2

## Что видит луч удара: стены (бит 0, чтобы не доставать сквозь них) и enemies; двери на moving_colliders в маске нет.
const RAY_MASK := (1 << 0) | ENEMIES_BIT

## Сколько «не-целей» (трупы-рэгдоллы, свои кости) луч проходит насквозь — предел против ошибки в данных.
const MAX_PIERCED := 8


func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_PlayerInput, C_Attack]), _attack],
		[q.with_all([C_PlayerInput]).with_none([C_Attack]), _swallow],
	]


## ПОСЛЕ перемещения: луч идёт от камеры, целиться надо из точки после тика.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_Movement]}


func _attack(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var attack := entity.get_component(C_Attack) as C_Attack
		attack.cooldown_left = maxf(0.0, attack.cooldown_left - delta)

		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		if not inp.attack_pressed:
			continue
		inp.attack_pressed = false

		# Открытый экран (C_UIBlocked) удара не получает; защёлку съели, чтобы не дожила до закрытия меню.
		if entity.has_component(C_UIBlocked):
			continue
		if attack.cooldown_left > 0.0:
			continue  # рука ещё не вернулась: нажатие пропало, а не встало в очередь
		attack.cooldown_left = attack.interval

		var player := entity as E_Player
		if player == null or player.camera == null:
			continue
		var target := find_target(entity, player.camera, attack.reach)
		if target == null:
			continue

		# Через воронку: удар обязан оставить след «кто, кому, сколько и чем» (S_Health.deal_damage).
		S_Health.deal_damage(target, damage_against(entity, target, attack), entity, MEANS)
		ECS.world.emit_event(&"attack_hit", entity, target)
		C_ScreenMessage.show_on(entity, "HUD_MSG_HIT", cmd)


## Бить нечем — гасим защёлку.
func _swallow(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		if not inp.attack_pressed:
			continue
		inp.attack_pressed = false

		if entity.has_component(C_Embodied):
			C_ScreenMessage.show_on(entity, "HUD_MSG_NO_ATTACK", cmd)


## Сколько урона реально получит target. ЕДИНСТВЕННОЕ МЕСТО, где урон зависит от цели: «существо L5 почти неуязвимо для слабых» ([[Игровой цикл — от и до]] §2). Класс нападающего — класс тела
## (C_Embodied.body_scene_path), цели — класс трупа врага (E_Enemy.threat_class); без тела — класс 0 (неизвестное тело слабое).
static func damage_against(attacker: Entity, target: Entity, attack: C_Attack) -> float:
	if target_class(target) >= L5_CLASS and attacker_class(attacker) < L5_CLASS:
		return attack.damage * L5_RESISTANCE
	return attack.damage


## Класс тела, в котором сидит attacker; 0 — вне тела.
static func attacker_class(attacker: Entity) -> int:
	if attacker == null:
		return 0
	var embodied := attacker.get_component(C_Embodied) as C_Embodied
	if embodied == null:
		return 0
	return E_Body.class_of_scene(embodied.body_scene_path)


## Класс угрозы цели; 0 — не враг.
static func target_class(target: Entity) -> int:
	var enemy := target as E_Enemy
	return enemy.threat_class() if enemy else 0


## Луч из камеры вперёд (−Z) на reach м: ближайшая живая цель или null. Цель — сущность с прочностью без C_BodySnatchable (в трупы вселяются, их не бьют);
## прочее на слое enemies (рэгдоллы, свои кости) луч проходит насквозь, стена обрывает.
static func find_target(attacker: Entity, cam: Camera3D, reach: float) -> Entity:
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * reach
	var space := cam.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK)
	var skip: Array[RID] = []
	var attacker_body := attacker as Node as CollisionObject3D
	if attacker_body != null:
		skip.append(attacker_body.get_rid())
	params.exclude = skip
	for _i in MAX_PIERCED:
		var hit := space.intersect_ray(params)
		if hit.is_empty():
			return null
		# Стену узнаём по слою, не по отсутствию сущности: комната — тоже Entity.
		var collider := hit.collider as CollisionObject3D
		if collider == null or collider.collision_layer & ENEMIES_BIT == 0:
			return null
		var victim := _entity_of(collider)
		if victim != null and _is_victim(victim, attacker):
			return victim
		skip.append(hit.rid)
		params.exclude = skip
	return null


## Вверх по дереву от коллайдера до сущности.
static func _entity_of(collider: Object) -> Entity:
	var node := collider as Node
	while node:
		if node is Entity:
			return node as Entity
		node = node.get_parent()
	return null


static func _is_victim(candidate: Entity, attacker: Entity) -> bool:
	return (
		candidate != attacker
		and candidate.has_component(C_Health)
		and not candidate.has_component(C_BodySnatchable)
		and not candidate.has_component(C_Dead)
	)
