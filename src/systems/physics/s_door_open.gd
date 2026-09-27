# res://src/systems/physics/s_door_open.gd
# Группа: "physics". Убирает полотно открытой двери (C_DoorOpen) с дороги:
# одиночное поднимает, створки двустворчатой разводит от центра проёма в стены.
#
# Полотно — AnimatableBody3D из .glb двери, меш — его ребёнок. Двигать надо
# САМО тело, а не узел Visual над ним: тело с sync_to_physics следит только за
# своим ЛОКАЛЬНЫМ transform, и подъём родителя оно не видит — коллизия так и
# оставалась в проёме, хотя дверь выглядела открытой (так и было до этой правки).
# В физическом кадре — по той же причине: sync_to_physics переносит тело шагом
# физики, и сдвиг из _process давал бы полотну на кадр разойтись с коллизией.
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
# Кривая — «быстро стартует, мягко садится»: гермозатвор, а не лифт.
class_name S_DoorOpen
extends System

const REST_META := &"door_rest"


func query() -> QueryBuilder:
	return q.with_all([C_DoorOpen])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var door := entity.get_component(C_DoorOpen) as C_DoorOpen
		if door.progress >= 1.0:
			continue
		door.progress = minf(1.0, door.progress + delta / maxf(door.duration, 0.001))
		var leaves := leaves_of(entity)
		for leaf in leaves:
			if not leaf.has_meta(REST_META):
				leaf.set_meta(REST_META, leaf.position)
			var shift := open_offset(door, leaf_side(leaf), leaves.size())
			leaf.position = (leaf.get_meta(REST_META) as Vector3) + shift * ease(door.progress, 0.4)


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
static func open_offset(door: C_DoorOpen, side: float, leaf_count: int) -> Vector3:
	if leaf_count < 2:
		return Vector3(0.0, door.lift, 0.0)
	return Vector3(side * door.slide, 0.0, 0.0)


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
