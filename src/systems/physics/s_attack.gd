# res://src/systems/physics/s_attack.gd
# Группа: "physics" — кастует луч от камеры, а Jolt крутится на отдельном потоке,
# поэтому space-state безопасен только из _physics_process (как и детекторы).
#
# Ближний удар тела: по нажатию «attack» (E_Player._input взводит защёлку
# C_PlayerInput.attack_pressed) бьёт ближайшую живую цель под крестиком в
# пределах C_Attack.reach и проводит урон через единую воронку S_Health.
# Способность — компонент и своя система, как прыжок и бег: у тела без C_Attack
# нет и удара, а ветвления «что на мне надето» здесь нет.
#
# ВТОРАЯ ВЫБОРКА — про тех, у кого удара НЕТ, и она по той же причине, что у
# S_Jump и S_Sprint: защёлку нажатия гасит тот, кто её съел, обе половины в
# одном файле. Иначе нажатие призрака или ползуна выстрелило бы в тот миг, когда
# игрок вселится в тело с ударом. Сообщаем «нечем» только игроку ВО ПЛОТИ:
# призрак бить не умеет по замыслу (его способность — захват), и текст про
# «тело» ему был бы враньём.
class_name S_Attack
extends System

## Чем бьём — атрибуция удара для сводки забега (S_Health.Damage.means).
const MEANS := &"attack"

## Класс угрозы существ дна. Удар тела ниже этого класса по существу этого класса
## ослаблен (L5_RESISTANCE).
const L5_CLASS := 5

## Во сколько раз слабее бьёт тело класса ниже L5 по существу L5. L5 уничтожает
## только другой L5 ([[Игровой цикл — от и до]], §2, решение 15.10): чтобы пройти
## сбежавших к выходу, нужно тело с самого дна. Не ноль, а десятая доля: нулевой
## урон неотличим от бага («бью — ничего не происходит»), а так слабое тело
## хотя бы видимо царапает, и игрок понимает, что бьёт не тем. Число черновое,
## подгоняет game-balance.
const L5_RESISTANCE := 0.1

## Слой enemies (бит 2): на нём стоят и живые враги, и кости трупов.
const ENEMIES_BIT := 1 << 2

## Что луч удара видит: стены (static_colliders, бит 0) и enemies. Стены нужны
## затем, чтобы удар не доставал врага сквозь них; двери и прочая подвижная
## геометрия на moving_colliders в маске нет.
const RAY_MASK := (1 << 0) | ENEMIES_BIT

## Сколько «не-целей» (трупы-рэгдоллы, свои же кости) луч готов пройти насквозь.
## Предел — чтобы ошибка в данных не превратила один каст в сотню.
const MAX_PIERCED := 8


func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_PlayerInput, C_Attack]), _attack],
		[q.with_all([C_PlayerInput]).with_none([C_Attack]), _swallow],
	]


## ПОСЛЕ перемещения — по той же причине, что у детекторов: луч идёт от камеры, и
## целиться надо из точки, где тело стоит после этого тика.
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

		# Открытый экран (C_UIBlocked) удара не получает: защёлку съели, чтобы она
		# не дожила до закрытия меню, а бить сквозь меню нечем.
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

		# Через воронку, а не записью в C_Health.current: удар обязан оставить след
		# «кто, кому, сколько и чем» (см. S_Health.deal_damage).
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


## Сколько урона реально получит [param target] от этого удара.
##
## ЕДИНСТВЕННОЕ МЕСТО, где урон удара может зависеть от цели: правило «существо
## L5 почти неуязвимо для слабых» ([[Игровой цикл — от и до]], §2) лежит здесь, а
## не в каждой боевой системе отдельно. Класс нападающего — класс тела, в котором
## он сидит (C_Embodied.body_scene_path, тот же путь сцены, по которому считаются
## очки за захват); класс цели — класс трупа врага (E_Enemy.threat_class). Без
## тела (нет C_Embodied) нападающий — класс 0: бить он и так не умеет, но
## функция публичная, и «неизвестное тело» обязано быть слабым, а не сильным.
static func damage_against(attacker: Entity, target: Entity, attack: C_Attack) -> float:
	if target_class(target) >= L5_CLASS and attacker_class(attacker) < L5_CLASS:
		return attack.damage * L5_RESISTANCE
	return attack.damage


## Класс тела, в котором сидит [param attacker]; 0 — вне тела.
static func attacker_class(attacker: Entity) -> int:
	if attacker == null:
		return 0
	var embodied := attacker.get_component(C_Embodied) as C_Embodied
	if embodied == null:
		return 0
	return E_Body.class_of_scene(embodied.body_scene_path)


## Класс угрозы цели; 0 — это не враг (у прочего живого нет шкалы L0..L5).
static func target_class(target: Entity) -> int:
	var enemy := target as E_Enemy
	return enemy.threat_class() if enemy else 0


## Луч из камеры вперёд (−Z) на [param reach] метров: ближайшая живая цель удара
## или null.
##
## Цель — сущность с прочностью, которую нельзя захватить (C_BodySnatchable
## есть у трупов-тел: их не бьют, в них вселяются) и которая ещё не мертва.
## Всё остальное на слое enemies — труп-рэгдолл, свои же кости — луч проходит
## насквозь. А вот стена (коллайдер не на слое enemies) обрывает луч: за ней цели
## нет.
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
		# Стену узнаём по слою, а не по отсутствию сущности: сама комната — тоже
		# Entity, и «коллайдер без сущности» не нашёл бы ни одной стены.
		var collider := hit.collider as CollisionObject3D
		if collider == null or collider.collision_layer & ENEMIES_BIT == 0:
			return null
		var victim := _entity_of(collider)
		if victim != null and _is_victim(victim, attacker):
			return victim
		skip.append(hit.rid)
		params.exclude = skip
	return null


## Поднимается от коллайдера вверх по дереву до сущности (коллайдер обычно —
## дочерний CollisionShape3D или кость, а не сама сущность).
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
