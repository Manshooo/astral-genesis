# res://src/systems/gameplay/s_room_presence.gd
# Группа "gameplay". Сообщает забегу, где стоит игрок: текущий узел меняется по присутствию, не по двери. Чья клетка — решает план слоя
# (RS_LayerPlan.node_at), контрольная точка и room_changed — RunManager; здесь только выборка и позиция. Не "physics": рейкастов нет.
class_name S_RoomPresence
extends System


## Игрок — по C_PlayerInput (враг ходит через C_EnemyInput, чтобы такие выборки его не цепляли).
func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		# Entity наследует Node — до Node3D двойной каст; вне дерева global_position ругается (кадр после add_entity, см. S_VoidFall).
		var node := entity as Node as Node3D
		if node == null or not node.is_inside_tree():
			continue
		RunManager.note_presence(node.global_position)
