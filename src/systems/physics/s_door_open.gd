# res://src/systems/physics/s_door_open.gd
# Группа: "physics". Поднимает полотно открытой двери (C_DoorOpen).
#
# Полотно — AnimatableBody3D из .glb двери, меш — его ребёнок. Двигать надо
# САМО тело, а не узел Visual над ним: тело с sync_to_physics следит только за
# своим ЛОКАЛЬНЫМ transform, и подъём родителя оно не видит — коллизия так и
# оставалась в проёме, хотя дверь выглядела открытой (так и было до этой правки).
# В физическом кадре — по той же причине: sync_to_physics переносит тело шагом
# физики, и сдвиг из _process давал бы полотну на кадр разойтись с коллизией.
#
# Высота ставится абсолютной, от точки покоя, а не приращением: до шага физики
# тело откатывает свой узел к последней физической позиции, и приращения,
# пришедшие между шагами (физика у нас на отдельном потоке), терялись бы —
# дверь застревала бы недоподнятой. Точку покоя полотно помнит в метаданных:
# у полотна в арте она своя, и ноль вместо неё сбил бы дверь на первом кадре.
# Двери без AnimatableBody3D (арт без коллизии) поднимается Visual целиком —
# двигать больше нечего.
#
# Кривая — «быстро стартует, мягко садится»: гермозатвор, а не лифт.
class_name S_DoorOpen
extends System

const REST_META := &"door_rest_y"


func query() -> QueryBuilder:
	return q.with_all([C_DoorOpen])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var door := entity.get_component(C_DoorOpen) as C_DoorOpen
		if door.progress >= 1.0:
			continue
		door.progress = minf(1.0, door.progress + delta / maxf(door.duration, 0.001))
		var height := door.lift * ease(door.progress, 0.4)
		for leaf in leaves_of(entity):
			if not leaf.has_meta(REST_META):
				leaf.set_meta(REST_META, leaf.position.y)
			leaf.position.y = float(leaf.get_meta(REST_META)) + height


## Что поднимается у двери: тела полотна внутри Visual, а без них — сам Visual.
## Статическая — ею же проверка ищет полотно, чтобы убедиться, что поднялось
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
