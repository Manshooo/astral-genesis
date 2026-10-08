# res://src/systems/physics/s_door_motion.gd
# Группа: "physics". Ведёт дверь (C_DoorMotion) по фазам: открывается → стоит
# открытой hold секунд → закрывается → закрыта. Полотно одиночной двери уезжает
# вверх, створки двустворчатой — вбок, в стены; обратно — той же кривой.
#
# Полотно — AnimatableBody3D из .glb двери, меш — его ребёнок. Двигать надо
# САМО тело, а не узел Visual над ним: тело с sync_to_physics следит только за
# своим ЛОКАЛЬНЫМ transform, и подъём родителя оно не видит — коллизия так и
# оставалась в проёме, хотя дверь выглядела открытой (так и было до этой правки).
# В физическом кадре — по той же причине: sync_to_physics переносит тело шагом
# физики, и сдвиг из _process давал бы полотну на кадр разойтись с коллизией.
# Отсюда же и выталкивание из проёма: запрос к space-state безопасен только из
# физического кадра (Jolt на своём потоке).
#
# Положение ставится абсолютным, от точки покоя, а не приращением: до шага
# физики тело откатывает свой узел к последней физической позиции, и приращения,
# пришедшие между шагами (физика у нас на отдельном потоке), терялись бы —
# дверь застревала бы недооткрытой. Точку покоя полотно помнит в метаданных:
# у полотна в арте она своя, и ноль вместо неё сбил бы дверь на первом кадре.
# Двери без AnimatableBody3D (арт без коллизии) двигается Visual целиком —
# двигать больше нечего.
#
# Одно полотно или створки — решает сама дверь числом тел в арте, а не настройка:
# арт и есть то, что знает, как дверь устроена, а разойдись они — и створки
# полезли бы вверх, в клетку уровня выше.
#
# Кривая — «быстро стартует, мягко садится»: гермозатвор, а не лифт. Закрытие
# проходит её в обратную сторону — трогается мягко и захлопывается.
class_name S_DoorMotion
extends System

const REST_META := &"door_rest"


func query() -> QueryBuilder:
	return q.with_all([C_DoorMotion])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var motion := entity.get_component(C_DoorMotion) as C_DoorMotion
		var step := delta / maxf(motion.duration, 0.001)
		if motion.phase == C_DoorMotion.Phase.OPENING:
			motion.progress = minf(1.0, motion.progress + step)
			if motion.progress >= 1.0:
				motion.phase = C_DoorMotion.Phase.OPEN
				motion.held = 0.0
			_place_leaves(entity, motion)
		elif motion.phase == C_DoorMotion.Phase.OPEN:
			motion.held += delta
			if motion.held >= motion.hold:
				close(entity)
		elif motion.phase == C_DoorMotion.Phase.CLOSING:
			_push_out(entity, motion, delta)
			motion.progress = maxf(0.0, motion.progress - step)
			if motion.progress <= 0.0:
				motion.phase = C_DoorMotion.Phase.CLOSED
			_place_leaves(entity, motion)


## Открывает дверь: полотно убирается с дороги, а интеракция гаснет — открытую
## дверь незачем подсвечивать, и подсказка в проходе мешала бы. Закрывающуюся
## дверь разворачивает с того места, где полотно сейчас: нажал на ходу — дверь
## пошла обратно, а не доехала и открылась заново.
##
## Статическая — зовёт RunManager.use_door, вне прохода ECS (interact() идёт
## через call_deferred). Возвращает false, если открывать нечем — у двери нет
## C_DoorMotion или она уже открывается или открыта.
static func open(door: Entity) -> bool:
	var motion := door.get_component(C_DoorMotion) as C_DoorMotion
	if motion == null:
		return false
	if motion.phase != C_DoorMotion.Phase.CLOSED and motion.phase != C_DoorMotion.Phase.CLOSING:
		return false
	motion.phase = C_DoorMotion.Phase.OPENING
	_set_interactive(door, false)
	_signal(door, motion, motion.opened_signal)
	return true


## Закрывает дверь. Интеракция возвращается сразу, а не по окончании хода: тот,
## кто передумал, успевает открыть дверь обратно, пока она едет.
static func close(door: Entity) -> void:
	var motion := door.get_component(C_DoorMotion) as C_DoorMotion
	if motion == null or motion.phase == C_DoorMotion.Phase.CLOSED:
		return
	motion.phase = C_DoorMotion.Phase.CLOSING
	_set_interactive(door, true)
	_signal(door, motion, motion.closed_signal)


static func _set_interactive(door: Entity, enabled: bool) -> void:
	var inter := door.get_component(C_Interactable) as C_Interactable
	if inter:
		inter.enabled = enabled


## Состояние двери — сигнал в её единственное событие, а не отдельное событие на
## каждое: что прозвучит на сигнал, решает проект звука. Инстанс заводится на
## первом сигнале и живёт с дверью. Нет рантайма или события — AudioManager
## вернёт null (и один раз скажет об этом в лог), дверь просто молчит; пробовать
## снова на следующем ходу дёшево — это раз в несколько секунд, не каждый кадр.
static func _signal(door: Entity, motion: C_DoorMotion, signal_name: String) -> void:
	if motion.sound == null:
		motion.sound = AudioManager.create_event_instance(motion.event_path)
		if motion.sound == null:
			return
		motion.sound.set_3d_attributes((door as Node as Node3D).global_position, Vector3.ZERO)
		motion.sound.start()
	motion.sound.send_signal(signal_name)


static func _place_leaves(entity: Entity, motion: C_DoorMotion) -> void:
	var leaves := leaves_of(entity)
	for leaf in leaves:
		if not leaf.has_meta(REST_META):
			leaf.set_meta(REST_META, leaf.position)
		var shift := open_offset(motion, leaf_side(leaf), leaves.size())
		leaf.position = (leaf.get_meta(REST_META) as Vector3) + shift * ease(motion.progress, 0.4)


## Выталкивает из проёма закрывающейся двери тех, кого она зажала бы: игрока,
## врага. Явно, вдоль нормали двери, к ближней стороне — помнить, откуда тело
## пришло, не нужно. На физику не полагаемся: створки сходятся вбок, к центру
## проёма, и сами тело только зажмут.
##
## Проём — объём InteractBody двери: он и так очерчивает проём между рамками, на
## который наводится игрок, а второй объём той же формы разошёлся бы с ним при
## первой правке арта. Сдвиг — шагом, пока тело в объёме: сколько ему выходить,
## зависит от его формы, а шаг доводит любую, не зная её.
static func _push_out(door: Entity, motion: C_DoorMotion, delta: float) -> void:
	var doorway := _doorway_shape(door)
	if doorway == null:
		return
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = doorway.shape
	params.transform = doorway.global_transform
	params.collision_mask = motion.push_mask
	var normal := doorway.global_basis.z.normalized()
	var space := doorway.get_world_3d().direct_space_state
	for hit in space.intersect_shape(params, 8):
		var body := hit.collider as CharacterBody3D
		if body == null:
			continue
		var side := signf((body.global_position - doorway.global_position).dot(normal))
		if side == 0.0:
			side = 1.0
		body.global_position += normal * side * motion.push_speed * delta


static func _doorway_shape(door: Entity) -> CollisionShape3D:
	var area := door.get_node_or_null(^"InteractBody")
	if area == null:
		return null
	for shape in area.find_children("*", "CollisionShape3D", true, false):
		var collision := shape as CollisionShape3D
		if collision.shape != null and not collision.disabled:
			return collision
	return null


## Что двигается у двери: тела полотна внутри Visual, а без них — сам Visual.
## Статическая — ею же проверка ищет полотно, чтобы убедиться, что открылось
## именно то, во что упирается игрок.
static func leaves_of(entity: Node) -> Array[Node3D]:
	var leaves: Array[Node3D] = []
	var visual := entity.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return leaves
	for body in visual.find_children("*", "AnimatableBody3D", true, false):
		leaves.append(body as Node3D)
	if leaves.is_empty():
		leaves.append(visual)
	return leaves


## Куда уезжает полотно открытой двери от точки покоя (в координатах его
## родителя): одиночное — вверх на lift, створка — вбок на slide, в сторону
## [param side] от центра проёма. Статическая — ею проверка считает, где полотно
## обязано оказаться, а не повторяет правило своей копией.
static func open_offset(motion: C_DoorMotion, side: float, leaf_count: int) -> Vector3:
	if leaf_count < 2:
		return Vector3(0.0, motion.lift, 0.0)
	return Vector3(side * motion.slide, 0.0, 0.0)


## С какой стороны от центра проёма стоит створка: −1 или +1 по X. По точке покоя
## тела, а если художник поставил origin створки в центр проёма (там X = 0) — по
## её форме коллизии: иначе такая створка не сдвинулась бы вовсе.
static func leaf_side(leaf: Node3D) -> float:
	var rest: Vector3 = leaf.get_meta(REST_META, leaf.position)
	if absf(rest.x) > 0.01:
		return signf(rest.x)
	for shape in leaf.find_children("*", "CollisionShape3D", true, false):
		var x := (shape as Node3D).position.x
		if absf(x) > 0.01:
			return signf(x)
	return 0.0
