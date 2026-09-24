## res://addons/game_design_tool/world/overlays/rooms_overlay.gd
## Оверлей «Геометрия»: реальные сцены комнат и куски кита коридоров на своих
## местах по RS_LayerPlan — тот же генератор, та же раскладка и тот же кит, что
## и у игры, только превью-сцена вместо игровой. Никакой отдельной «схемы
## отрисовки» здесь нет и не нужно: схему плана рисует оверлей «Коридоры».
##
## Тайлы ставит тот же RS_CorridorKit.instantiate, что и RunManager: поставь их
## превью по-своему — и показывало бы не тот коридор, что построит игра. Кита
## нет (LayerView.kit == null) — ставятся одни комнаты.
##
## Комнаты НЕ регистрируются в ECS (World.add_entity не зовётся): у Entity
## _initialize вызывается только явно из World.add_entity, поэтому просто
## инстанцировать сцену и положить её в дерево безопасно — компоненты
## остаются detached (RS_RoomLayout уже умеет читать двери и с detached-
## инстансов), а тела в комнатах сами отсекают физическую симуляцию по
## Engine.is_editor_hint() (см. e_body_*.gd) — редактор и так их не запустит.
##
## Обводка выделенной комнаты — НЕ свой шейдер, а material_overlay на каждом
## GeometryInstance3D, тем же приёмом и через тот же RS_EntityVisuals.geometries,
## каким O_OutlineVisual красит интерактивы в игре (см. [[Взаимодействие]]):
## каждая сцена комнаты — Entity (room_template.gd/hub.gd/test_room.gd), так
## что переиспользование готовое, не подгонка чужого кода под другую задачу.
## Тайл коридора не Entity, у него обводятся все меши поддерева; выделенная
## ветка обводится целиком, всеми своими тайлами. Цвет свой — жёлто-оливковый
## (#cfc61b), не игровой синий: это разметка инструмента, а не подсветка
## интерактива в мире.
@tool
extends Node3D

const OUTLINE_MATERIAL: Material = preload("res://addons/game_design_tool/assets/selection_outline.tres")
const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")

var _rooms: Dictionary[StringName, Node] = {}
## ветка -> её тайлы.
var _tiles: Dictionary[StringName, Array] = {}
var _selected_id: StringName = &""


func rebuild(view: LayerView) -> void:
	clear()
	for node_data: RS_LevelNode in view.nodes:
		if node_data.room_scene_path == "" or not ResourceLoader.exists(node_data.room_scene_path):
			continue
		var room := (load(node_data.room_scene_path) as PackedScene).instantiate()
		var spatial := room as Node3D
		if spatial:
			spatial.position = view.plan.positions.get(node_data.id, Vector3.ZERO)
		add_child(room)
		_rooms[node_data.id] = room
	if view.kit != null and view.plan != null:
		_build_tiles(view)


## Сколько тайлов коридора стоит — для проверки инструмента.
func tile_count() -> int:
	var count := 0
	for tiles: Array in _tiles.values():
		count += tiles.size()
	return count


func set_selected(node_id: StringName) -> void:
	_outline(_selected_id, null)
	_selected_id = node_id
	_outline(node_id, OUTLINE_MATERIAL)


func _build_tiles(view: LayerView) -> void:
	for cell: Vector3i in view.plan.corridor_tiles:
		var tile := view.kit.instantiate(view.plan.corridor_tiles[cell])
		if tile == null:
			continue
		# Позиция до add_child — как у игры (LayerStreamer._spawn_corridor).
		tile.position = view.plan.cell_position(Vector2i(cell.x, cell.z), cell.y)
		add_child(tile)
		var branch: StringName = view.plan.node_by_cell.get(cell, &"")
		if not _tiles.has(branch):
			_tiles[branch] = []
		_tiles[branch].append(tile)


func _outline(node_id: StringName, material: Material) -> void:
	if node_id == &"":
		return
	if _rooms.has(node_id):
		var entity := _rooms[node_id] as Entity
		if entity != null:
			for geometry: GeometryInstance3D in RS_EntityVisuals.geometries(entity):
				geometry.material_overlay = material
	for tile: Node in _tiles.get(node_id, []):
		for geometry: GeometryInstance3D in tile.find_children("*", "GeometryInstance3D", true, false):
			geometry.material_overlay = material


## free(), не queue_free(): пересборка синхронная (сид меняется, глубина
## меняется — всё в один тик), и отложенное удаление оставило бы старые
## комнаты видимыми до конца кадра, наложенными на новые. Тот же приём, каким
## RS_RoomLayout/RS_RoomPresetLibrary уже освобождают инстансы после осмотра.
func clear() -> void:
	for room: Node in _rooms.values():
		room.free()
	_rooms.clear()
	for tiles: Array in _tiles.values():
		for tile: Node in tiles:
			tile.free()
	_tiles.clear()
	_selected_id = &""
