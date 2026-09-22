# res://src/systems/gameplay/s_room_presence.gd
# Группа: "gameplay". Сообщает забегу, где стоит игрок, — и этого достаточно,
# чтобы текущий узел графа менялся по присутствию, а не по нажатию двери.
#
# Существует ради коридоров: когда между комнатами можно пройти ногами, дверь
# просто открывается, а «вошёл в комнату» — это шаг через её границу. Решать,
# чья это клетка, система не берётся: правило одно на игру и инструменты и живёт
# в плане слоя (RS_LayerPlan.node_at), а контрольная точка, посещённые комнаты и
# room_changed — в RunManager. Здесь только выборка игрока и его позиция.
#
# Группа gameplay, а не physics: рейкастов нет, читается одна координата, и
# отставание на кадр от физики для «в какой я клетке» ничего не значит.
class_name S_RoomPresence
extends System


## Игрок — по C_PlayerInput, как и везде в проекте (враг ходит через
## C_EnemyInput именно затем, чтобы такие выборки его не цепляли).
func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		# Entity наследует Node — до Node3D через двойной каст. Вне дерева
		# global_position ругается в консоль, а сущность бывает вне его ровно
		# кадр после add_entity (см. S_VoidFall).
		var node := entity as Node as Node3D
		if node == null or not node.is_inside_tree():
			continue
		RunManager.note_presence(node.global_position)
