## res://addons/game_design_tool/world/overlays/rooms_overlay.gd
## Оверлей «Геометрия»: реальные сцены комнат на своих местах по
## RS_LayerPlan — тот же генератор и та же раскладка, что и у игры, только
## превью-сцена вместо игровой. Никакой отдельной «схемы отрисовки» для
## комнат нет и не нужно.
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
## Цвет свой — жёлто-оливковый (#cfc61b), не игровой синий: это разметка
## инструмента, а не подсветка интерактива в мире.
@tool
extends Node3D

const OUTLINE_MATERIAL: Material = preload("res://addons/game_design_tool/assets/selection_outline.tres")
const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")

var _rooms: Dictionary[StringName, Node] = {}
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


func set_selected(node_id: StringName) -> void:
	if _selected_id != &"" and _rooms.has(_selected_id):
		_apply_outline(_rooms[_selected_id], null)
	_selected_id = node_id
	if node_id != &"" and _rooms.has(node_id):
		_apply_outline(_rooms[node_id], OUTLINE_MATERIAL)


func _apply_outline(room: Node, material: Material) -> void:
	var entity := room as Entity
	if entity == null:
		return
	for geometry: GeometryInstance3D in RS_EntityVisuals.geometries(entity):
		geometry.material_overlay = material


## free(), не queue_free(): пересборка синхронная (сид меняется, глубина
## меняется — всё в один тик), и отложенное удаление оставило бы старые
## комнаты видимыми до конца кадра, наложенными на новые. Тот же приём, каким
## RS_RoomLayout/RS_RoomPresetLibrary уже освобождают инстансы после осмотра.
func clear() -> void:
	for room: Node in _rooms.values():
		room.free()
	_rooms.clear()
	_selected_id = &""
