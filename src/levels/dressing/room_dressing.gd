# res://src/levels/dressing/room_dressing.gd
# Обстановка комнаты по сиду: узлы с методом dress(rng) -> bool (PlaceSetting, PropJitter) получают свой ГСЧ и решают,
# где встать и остаться ли. ГСЧ от hash([сид, слой, узел, путь]), не общий: граф не сдвигается (GENERATOR_VERSION не
# нужен), слой, собранный заново, обставлен так же, и правка одного пропа не перемешивает остальные. Вики: [[Расстановка пропов в комнатах]].
class_name RoomDressing
extends RefCounted

const METHOD := &"dress"


## ГСЧ узла обстановки — функция от (сид, слой, узел графа, путь в комнате), без состояния.
static func rng_for(run_seed: int, depth: int, node_id: StringName, path: NodePath) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, depth, String(node_id), String(path)])
	return rng


## Обставляет комнату ДО add_entity: убранный стул не должен попасть в навмеш слоя, сдвинутый — встать коллайдером
## на старое место. Узел, ответивший false, снимается сразу, а не queue_free: навмеш запекается в том же кадре.
static func dress_room(room: Node, node_id: StringName, depth: int, run_seed: int) -> void:
	for node in room.find_children("*", "Node3D", true, false):
		if not is_instance_valid(node) or not node.has_method(METHOD):
			continue
		var keep: bool = node.call(METHOD, rng_for(run_seed, depth, node_id, room.get_path_to(node)))
		if not keep:
			node.get_parent().remove_child(node)
			node.free()
