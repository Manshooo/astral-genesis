## res://src/resources/world_generator/rs_room_wall_kit.gd
## Стены одного стиля для комнаты, собранной по маске сокетов (C_RoomShell): на
## каждую грань клетки по периметру спавн ставит одну деталь — с проёмом и дверью,
## если раскладка поставила туда дверь, иначе глухую. У монолита со стенами в меше
## (C_RoomShell.walls_in_shell) — только полотно на дверь и заглушку на
## невыбранный сокет.
##
## Данными, а не путями в коде, по той же причине, что и кит коридора
## (RS_CorridorKit): новый стиль — новый ресурс, а не правка спавна. Детали стен
## нарисованы на СЕВЕРНОЙ грани клетки с origin в её центре на полу ([[Метрики и
## кит]] §3) — спавн ставит их в центр клетки и поворачивает к нужной стороне
## (RS_RoomLayout.north_piece_turns).
@tool  # читается рантаймом и проверками сцен в редакторе
class_name RS_RoomWallKit
extends Resource

## Стена с проёмом — на сокет, ставший дверью.
@export var door_wall: PackedScene
## Глухая стена — на сокет, оставшийся стеной.
@export var blank_wall: PackedScene
## Глухая стена верхних уровней высокой комнаты. Пусто — у стиля нет высоких
## коробок. Дверь выше нижнего уровня (объявленный сокет, C_RoomShell.door_sockets)
## ставится той же door_wall: деталь рисуется от пола своей клетки.
@export var upper_wall: PackedScene
## Полотно в проём — сущность с дверным механизмом. Встаёт на границу клеток, в
## середину грани; C_DoorSlot ей выдаёт спавн.
@export var door: PackedScene
## Заглушка невыбранного сокета коробки со стенами в меше
## (C_RoomShell.walls_in_shell): панель на проём, рамку и карман вокруг рисует
## сама коробка. Ставится как стена-сокет — в центр клетки с поворотом к стороне.
## На дверь нарочно не похожа: заваренных дверей в игре нет. Пусто — у стиля нет
## таких коробок.
@export var plug: PackedScene


## Собирает комнату [param node_id] плана: на каждую грань по периметру — стена с
## проёмом и дверью, если план поставил туда дверь, иначе глухая: на нижнем
## уровне — blank_wall, выше — глухая стена верха. Возвращает поставленные двери с
## их гранями.
##
## Одна сборка на игру (LayerStreamer) и на предпросмотр «Генератора мира» — по той
## же причине, что и RS_CorridorKit.instantiate: собери они комнату каждый
## по-своему, превью показывало бы не ту комнату, что построит игра.
##
## Детали ставятся в центр клетки и поворачиваются к стороне; дверь — на середину
## грани, на границу клеток: туда, где сходятся стена комнаты и торец коридора
## ([[Метрики и кит]] §2 п. 7). Грани плана — в сторонах мира, поэтому место
## детали считается в мире и переводится в координаты корня [param room] его
## обратным преобразованием: корень уже стоит на своём месте и повёрнут
## (RS_LayerPlan.room_transform), и стены обязаны встать в стороны мира при любом
## повороте комнаты. Входить в дерево корню не обязательно.
##
## У коробки со стенами в меше (C_RoomShell.walls_in_shell) стены уже стоят, и
## сборка обходит только её объявленные сокеты: на дверь — одно полотно, без
## стены с проёмом (проём в меше), на остальные — заглушка.
func assemble(room: Node3D, node_id: StringName, plan: RS_LayerPlan) -> Dictionary[Node3D, Vector4i]:
	var shell := RS_RoomLayout.shell_of(room)
	if shell and shell.walls_in_shell:
		return _assemble_walled(room, node_id, plan, shell)
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
			var piece := upper_wall
			if is_door:
				piece = door_wall
			elif cell.y == bottom:
				piece = blank_wall
			if piece:
				_place(room, piece, face, plan, false)
			if is_door and door:
				doors[_place(room, door, face, plan, true)] = face
	return doors


## Сокеты переводятся в грани плана тем же face_in_plan, по которому раскладка
## тянет к ним коридор (RS_RoomLayout.sockets_in_plan), — разойдись они, и
## полотно встало бы в глухую стену меша, а заглушка — в проём, куда пришёл
## коридор.
func _assemble_walled(room: Node3D, node_id: StringName, plan: RS_LayerPlan, shell: C_RoomShell) -> Dictionary[Node3D, Vector4i]:
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
	return doors


## Ставит деталь, нарисованную на северной грани, на грань [param face] плана:
## в центр клетки или, если [param at_middle], на середину грани — туда, где
## сходятся стена комнаты и торец коридора (так встаёт полотно двери).
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
