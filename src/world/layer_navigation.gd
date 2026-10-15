# res://src/world/layer_navigation.gd
# Навмеш загруженного слоя: запекается при спавне из коллизии, по которой враги и
# ходят, и стоит в карте навигации, пока слой в дереве.
#
# ЗАПЕКАНИЕ НА СПАВНЕ, а не навмеш на кусок кита: стены сборной комнаты ставятся на
# спавне по маске сокетов, коридоры собираются из тайлов, и всё это повёрнуто, —
# готовой геометрии слоя до спавна нет, а навмеш на каждую деталь кита пришлось бы
# держать в синхроне с её мешем и стыковать по рёбрам. Здесь источник один —
# настоящая коллизия, та самая, в которую враг упрётся физически, так что навмеш
# не может разойтись со стеной.
#
# ДВА ШАГА, и только второй уходит в поток. Разбор геометрии
# (NavigationServer3D.parse_source_geometry_data) обходит SceneTree, а тот не
# потокобезопасен, — он идёт на главном потоке и стоит времени на входе в слой.
# Запекание (bake_from_source_geometry_data_async) работает над уже снятыми
# данными в потоке; результат приходит отложенным вызовом на главный поток.
#
# РЕГИОН ЖИВЁТ УЗЛОМ ПОД КОРНЕМ МИРА, а не RID'ом сервера: тот, кто его создал
# (LayerStreamer, часть автолоада RunManager), переживает смену сцены, а регион в
# карте окна пережил бы её вместе с ним — и навмеш прошлого забега стоял бы в
# новом на тех же координатах. Узел уходит вместе со сценой мира.
#
# Пока навмеш не готов (запекание идёт, а карта синхронизируется только на
# следующем физкадре после появления региона), карта пуста, и путь врагу не
# отдаётся: S_EnemyAI в этом случае идёт по прямой, как шёл без навигации.
#
# Параметры агента, маска геометрии и режим разбора — в data/enemy_navmesh.tres, а
# не в коде: радиус и высота обязаны покрывать тела врагов (dev/enemy_nav_check
# сверяет их со сценами). Размер ячейки берётся у карты, а не из шаблона: навмеш с
# другой ячейкой карта не склеивает и сыплет предупреждениями.
class_name LayerNavigation
extends RefCounted

## Навмеш готов и стоит в карте (карта подхватит его на следующем физкадре).
signal baked(region: NavigationRegion3D)

const TEMPLATE_PATH := "res://data/enemy_navmesh.tres"

## Регион запечённого слоя; null — не готов или снят.
var region: NavigationRegion3D
## Сколько заняли разбор геометрии (главный поток) и запекание (поток), мкс —
## для замера на реальном слое и для профайлера.
var parse_usec := 0
var bake_usec := 0

## Номер запекания: слой мог смениться, пока поток считал, и тогда результат —
## чужой. Сравнивается в _on_baked.
var _serial := 0
var _bake_started := 0


## Начинает запекание навмеша по коллизии всего, что стоит под [param root] (корень
## мира: комнаты и тайлы коридоров слоя). Возвращается сразу — разбор синхронный,
## запекание в потоке; о готовности говорит [signal baked].
func bake(root: Node) -> void:
	clear()
	if root == null or not root.is_inside_tree():
		return
	var mesh := (load(TEMPLATE_PATH) as NavigationMesh).duplicate() as NavigationMesh
	var map := root.get_viewport().find_world_3d().navigation_map
	mesh.cell_size = NavigationServer3D.map_get_cell_size(map)
	mesh.cell_height = NavigationServer3D.map_get_cell_height(map)

	var source := NavigationMeshSourceGeometryData3D.new()
	var started := Time.get_ticks_usec()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	parse_usec = Time.get_ticks_usec() - started
	if not source.has_data():
		push_warning("LayerNavigation: под корнем нет геометрии для навмеша")
		return

	_bake_started = Time.get_ticks_usec()
	NavigationServer3D.bake_from_source_geometry_data_async(
		mesh, source, _on_baked.bind(_serial, mesh, root)
	)


## Снимает навмеш слоя и обесценивает запекание, которое ещё идёт: его результат
## придёт на главный поток позже и будет отброшен. free(), а не queue_free(): как и
## тайлы коридора, старый регион не должен дожить до нового слоя на тех же клетках.
func clear() -> void:
	_serial += 1
	if is_instance_valid(region):
		region.free()
	region = null


## Готов ли навмеш: регион есть, и карта уже применила его полигоны. Регион
## появляется сразу после запекания, а карта подхватывает его на одном из
## следующих физкадров — итерации карты строятся асинхронно, и номер итерации
## региона (region_get_iteration_id) растёт раньше, чем карта начинает отвечать.
## Поэтому спрашиваем саму карту: ближайшая к вершине навмеша точка карты — эта же
## вершина. Пустая карта на такой запрос отвечает нулём.
func is_ready() -> bool:
	if not is_instance_valid(region) or not region.is_inside_tree():
		return false
	var vertices := region.navigation_mesh.get_vertices()
	if vertices.is_empty():
		return false
	var probe := region.global_transform * vertices[0]
	var near := NavigationServer3D.map_get_closest_point(region.get_navigation_map(), probe)
	return near.distance_to(probe) < region.navigation_mesh.cell_size


func _on_baked(serial: int, mesh: NavigationMesh, root: Node) -> void:
	if serial != _serial or not is_instance_valid(root) or not root.is_inside_tree():
		return
	bake_usec = Time.get_ticks_usec() - _bake_started
	if mesh.get_polygon_count() == 0:
		push_warning("LayerNavigation: навмеш слоя запёкся пустым — проверь маску геометрии")
		return
	region = NavigationRegion3D.new()
	region.name = "LayerNavigation"
	region.navigation_mesh = mesh
	root.add_child(region)
	baked.emit(region)
