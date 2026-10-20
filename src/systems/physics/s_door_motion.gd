# res://src/systems/physics/s_door_motion.gd
# Группа "physics". Ведёт дверь (C_DoorMotion) по фазам: открывается → стоит hold секунд → закрывается; одиночное полотно вверх, створки вбок, обратно той же кривой.
# Двигаем само AnimatableBody3D полотна, не Visual над ним: sync_to_physics следит за ЛОКАЛЬНЫМ transform (иначе коллизия оставалась в проёме); в физкадре по той же причине
# и ради запроса к space-state при выталкивании. Положение — абсолютное от точки покоя (в метаданных), не приращением: до шага физики тело откатывает узел. Без AnimatableBody3D
# двигается Visual целиком. Одно полотно или створки решает число тел в арте. Кривая — быстро стартует, мягко садится (закрытие — в обратную сторону). Вики: [[Цикл забега]] (двери).
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


## Открывает дверь: полотно с дороги, интеракция гаснет. Закрывающуюся разворачивает с текущего места. Статическая — зовёт RunManager.use_door вне прохода ECS.
## false — открывать нечем (нет C_DoorMotion) или уже открывается/открыта.
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


## Закрывает дверь; интеракция возвращается сразу — передумавший успевает открыть обратно.
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


## Состояние двери — сигнал в её единственное событие; что прозвучит, решает проект звука. Инстанс заводится на первом сигнале и живёт с дверью; null от AudioManager — дверь молчит, пробуем снова на следующем ходу.
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


## Выталкивает из проёма закрывающейся двери тех, кого она зажала бы (игрока, врага): вдоль нормали к ближней стороне; створки сходятся вбок и тело только зажмут.
## Проём — объём InteractBody двери (второй объём разошёлся бы); сдвиг шагом, пока тело в объёме.
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


## Что двигается у двери: тела полотна в Visual, без них — сам Visual. Статическая — ею проверка ищет полотно.
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


## Куда уезжает полотно открытой двери от точки покоя: одиночное — вверх на lift, створка — вбок на slide в сторону side. Статическая — ею проверка считает ожидаемое положение.
static func open_offset(motion: C_DoorMotion, side: float, leaf_count: int) -> Vector3:
	if leaf_count < 2:
		return Vector3(0.0, motion.lift, 0.0)
	return Vector3(side * motion.slide, 0.0, 0.0)


## С какой стороны от центра проёма створка (−1 или +1 по X): по точке покоя, а при origin в центре — по форме коллизии.
static func leaf_side(leaf: Node3D) -> float:
	var rest: Vector3 = leaf.get_meta(REST_META, leaf.position)
	if absf(rest.x) > 0.01:
		return signf(rest.x)
	for shape in leaf.find_children("*", "CollisionShape3D", true, false):
		var x := (shape as Node3D).position.x
		if absf(x) > 0.01:
			return signf(x)
	return 0.0
