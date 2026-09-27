## res://src/resources/world_generator/rs_room_wall_kit.gd
## Стены одного стиля для комнаты, собранной по маске сокетов (C_RoomShell): на
## каждую грань клетки по периметру спавн ставит одну деталь — с проёмом и дверью,
## если раскладка поставила туда дверь, иначе глухую.
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
## Глухая стена верхних уровней высокой комнаты: сокетов выше нижнего уровня нет.
## Пусто — у стиля нет высоких коробок.
@export var upper_wall: PackedScene
## Полотно в проём — сущность с дверным механизмом. Встаёт на границу клеток, в
## середину грани; C_DoorSlot ей выдаёт спавн.
@export var door: PackedScene


## Собирает комнату [param node_id] плана: на каждую грань нижнего уровня по
## периметру — стена с проёмом и дверью, если план поставил туда дверь, иначе
## глухая; на грани верхних уровней — глухая стена верха. Возвращает поставленные
## двери с их гранями.
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
func assemble(room: Node3D, node_id: StringName, plan: RS_LayerPlan) -> Dictionary[Node3D, Vector4i]:
	var doors: Dictionary[Node3D, Vector4i] = {}
	var door_faces: Dictionary = plan.door_faces.get(node_id, {})
	var cells := plan.room_cells(node_id)
	var bottom: int = plan.cells[node_id].y
	var to_room := room.transform.affine_inverse()
	for cell in cells:
		for side in plan.topology.side_count(cell):
			var next := plan.topology.neighbour(cell, side)
			if cells.has(next):
				continue
			var face := GridTopology.face(cell, side)
			var is_door := cell.y == bottom and door_faces.has(face)
			var piece := upper_wall
			if cell.y == bottom:
				piece = door_wall if is_door else blank_wall
			var turn := plan.embedding.turn_basis(RS_RoomLayout.north_piece_turns(side))
			if piece:
				var wall := piece.instantiate() as Node3D
				wall.transform = to_room * Transform3D(turn, plan.embedding.cell_origin(cell))
				room.add_child(wall)
			if is_door and door:
				var panel := door.instantiate() as Node3D
				var face_mid := (plan.embedding.cell_origin(cell) + plan.embedding.cell_origin(next)) * 0.5
				panel.transform = to_room * Transform3D(turn, face_mid)
				room.add_child(panel)
				doors[panel] = face
	return doors
