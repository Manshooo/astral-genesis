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
@tool
extends Node3D

var _rooms: Dictionary[StringName, Node] = {}


func rebuild(layer_nodes: Array[RS_LevelNode], plan: RS_LayerPlan) -> void:
	clear()
	for node_data: RS_LevelNode in layer_nodes:
		if node_data.room_scene_path == "" or not ResourceLoader.exists(node_data.room_scene_path):
			continue
		var room := (load(node_data.room_scene_path) as PackedScene).instantiate()
		var spatial := room as Node3D
		if spatial:
			spatial.position = plan.positions.get(node_data.id, Vector3.ZERO)
		add_child(room)
		_rooms[node_data.id] = room


## free(), не queue_free(): пересборка синхронная (сид меняется, глубина
## меняется — всё в один тик), и отложенное удаление оставило бы старые
## комнаты видимыми до конца кадра, наложенными на новые. Тот же приём, каким
## RS_RoomLayout/RS_RoomPresetLibrary уже освобождают инстансы после осмотра.
func clear() -> void:
	for room: Node in _rooms.values():
		room.free()
	_rooms.clear()
