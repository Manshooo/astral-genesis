## res://addons/game_design_tool/world/overlays/rooms_overlay.gd
## Оверлей «Геометрия»: реальные сцены комнат и куски кита коридоров на местах по
## RS_LayerPlan; кит ставит тот же RS_CorridorKit.instantiate, что и игра.
## [[Редакторские инструменты]] §«Коридоры и сетка во вьюпорте».
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
			spatial.transform = view.plan.room_transform(node_data.id)
			# Те же стены, что поставит игра (LayerStreamer).
			var shell := RS_RoomLayout.shell_of(room)
			if shell and shell.walls:
				shell.walls.assemble(spatial, node_data.id, view.plan)
		add_child(room)
		_rooms[node_data.id] = room
	if view.kit != null and view.plan != null:
		_build_tiles(view)


## Для проверки инструмента.
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
		var tile := view.kit.instantiate(view.plan.corridor_tiles[cell], view.plan.door_mask(cell))
		if tile == null:
			continue
		# Позиция до add_child — как у игры (LayerStreamer._spawn_corridor).
		tile.position = view.plan.embedding.cell_origin(cell)
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


## free(), не queue_free(): пересборка синхронна, старые комнаты не должны дожить до новых.
func clear() -> void:
	for room: Node in _rooms.values():
		room.free()
	_rooms.clear()
	for tiles: Array in _tiles.values():
		for tile: Node in tiles:
			tile.free()
	_tiles.clear()
	_selected_id = &""
