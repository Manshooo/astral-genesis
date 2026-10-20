## res://src/resources/world_generator/rs_room_wall_kit.gd
## Стены одного стиля для комнаты по маске сокетов (C_RoomShell): на каждую грань периметра — деталь с проёмом и дверью или глухая; у монолита со стенами
## в меше (walls_in_shell) — полотно на дверь и заглушка на невыбранный сокет. Данными, как кит коридора. Детали нарисованы на СЕВЕРНОЙ грани
## с origin в центре клетки на полу ([[Метрики и кит]] §3); спавн ставит их в центр и поворачивает (RS_RoomLayout.north_piece_turns).
@tool  # читается рантаймом и проверками сцен в редакторе
class_name RS_RoomWallKit
extends Resource

## Стена с проёмом — на сокет, ставший дверью.
@export var door_wall: PackedScene
## Глухая стена — на сокет, оставшийся стеной.
@export var blank_wall: PackedScene
## Глухая стена верхних уровней высокой комнаты; пусто — высоких коробок нет. Дверь выше нижнего уровня — та же door_wall.
@export var upper_wall: PackedScene
## Полотно в проём — сущность с дверным механизмом на середине грани; C_DoorSlot выдаёт спавн.
@export var door: PackedScene
## Заглушка невыбранного сокета коробки со стенами в меше; на дверь нарочно не похожа (заваренных дверей нет). Пусто — таких коробок нет.
@export var plug: PackedScene
## Дверь наружу — на грань выхода (C_RoomShell.exit_sockets). Своя сцена: без C_DoorSlot (привязка заварила бы её как лишнюю), действие — A_FinishRun.
@export var exit_door: PackedScene


## Собирает комнату node_id плана: на каждую грань периметра — стена с проёмом и дверью, если план поставил дверь, иначе глухая (blank_wall внизу, верх — upper_wall).
## Возвращает поставленные двери с гранями. Одна сборка на игру (LayerStreamer) и предпросмотр. Деталь ставится в центр клетки, дверь — на середину грани
## ([[Метрики и кит]] §2 п. 7); место считается в мире и переводится в координаты корня room обратным преобразованием (корень уже повёрнут). У коробки со стенами
## в меше — только объявленные сокеты: полотно на дверь, заглушка на остальные. Грань выхода в возвращаемые двери не попадает (не ребро графа).
func assemble(room: Node3D, node_id: StringName, plan: RS_LayerPlan) -> Dictionary[Node3D, Vector4i]:
	var shell := RS_RoomLayout.shell_of(room)
	var exits := _exit_faces(shell, node_id, plan)
	if shell and shell.walls_in_shell:
		return _assemble_walled(room, node_id, plan, shell, exits)
	var doors: Dictionary[Node3D, Vector4i] = {}
	var door_faces: Dictionary = plan.door_faces.get(node_id, {})
	var cells := plan.room_cells(node_id)
	var bottom: int = plan.cells[node_id].y
	for cell in cells:
		for side in plan.topology.side_count(cell):
			if cells.has(plan.topology.neighbour(cell, side)):
				continue
			var face := GridTopology.face(cell, side)
			var is_door := door_faces.has(face)
			var is_exit := exits.has(face)
			var piece := upper_wall
			if is_door or is_exit:
				piece = door_wall
			elif cell.y == bottom:
				piece = blank_wall
			if piece:
				_place(room, piece, face, plan, false)
			if is_door and door:
				doors[_place(room, door, face, plan, true)] = face
			elif is_exit and exit_door:
				_place(room, exit_door, face, plan, true)
	return doors


## Грани выхода в плане — тем же face_in_plan, что и сокеты: выход поворачивается с комнатой.
func _exit_faces(shell: C_RoomShell, node_id: StringName, plan: RS_LayerPlan) -> Array[Vector4i]:
	var faces: Array[Vector4i] = []
	if shell == null:
		return faces
	var turns: int = plan.turns.get(node_id, 0)
	for socket in shell.exit_sockets:
		faces.append(RS_RoomLayout.face_in_plan(socket, shell.size, turns, plan.cells[node_id]))
	return faces


## Сокеты переводятся в грани плана тем же face_in_plan, по которому раскладка тянет коридор, — иначе полотно встало бы в глухую стену, а заглушка — в проём.
func _assemble_walled(room: Node3D, node_id: StringName, plan: RS_LayerPlan, shell: C_RoomShell, exits: Array[Vector4i]) -> Dictionary[Node3D, Vector4i]:
	var doors: Dictionary[Node3D, Vector4i] = {}
	var door_faces: Dictionary = plan.door_faces.get(node_id, {})
	var turns: int = plan.turns.get(node_id, 0)
	for socket in RS_RoomLayout.sockets_of_shell(shell):
		var face := RS_RoomLayout.face_in_plan(socket, shell.size, turns, plan.cells[node_id])
		if not door_faces.has(face):
			if plug:
				_place(room, plug, face, plan, false)
		elif door:
			doors[_place(room, door, face, plan, true)] = face
	# Проём выхода коробка рисует сама.
	if exit_door:
		for face in exits:
			_place(room, exit_door, face, plan, true)
	return doors


## Ставит деталь с северной грани на грань face плана: в центр клетки или (at_middle) на середину грани, где сходятся стена и торец коридора.
func _place(room: Node3D, piece: PackedScene, face: Vector4i, plan: RS_LayerPlan, at_middle: bool) -> Node3D:
	var cell := GridTopology.face_cell(face)
	var origin := plan.embedding.cell_origin(cell)
	if at_middle:
		origin = (origin + plan.embedding.cell_origin(plan.topology.neighbour(cell, face.w))) * 0.5
	var turn := plan.embedding.turn_basis(RS_RoomLayout.north_piece_turns(face.w))
	var node := piece.instantiate() as Node3D
	node.transform = room.transform.affine_inverse() * Transform3D(turn, origin)
	room.add_child(node)
	return node
