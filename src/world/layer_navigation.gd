# res://src/world/layer_navigation.gd
# Навмеш загруженного слоя: запекается при спавне из коллизии, по которой враги и
# ходят, и стоит в картах навигации, пока слой в дереве.
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
# НАВМЕШ НА КАЖДЫЙ РАЗМЕР ВРАГА, по шаблону из PROFILES, и у каждого своя карта —
# так Godot и предлагает водить агентов разного размера (navigation_different_
# actor_types): агент описан только радиусом и высотой, и один навмеш по самому
# крупному выбросил бы всё под нависаниями, куда мелкий враг пролез бы. Геометрия
# разбирается ОДИН раз — дорогая часть на главном потоке от числа размеров не
# растёт, — а запекания идут в потоке друг за другом по тем же данным, не разом:
# одни исходные данные двум потокам одновременно не отдаём. Какой шаблон у врага —
# поле C_EnemyAI.nav_profile; карту для него S_EnemyAI спрашивает у map_for.
#
# РЕГИОН ЖИВЁТ УЗЛОМ ПОД КОРНЕМ МИРА, а не RID'ом сервера: тот, кто его создал
# (LayerStreamer, часть автолоада RunManager), переживает смену сцены, а регион
# пережил бы её вместе с ним — и навмеш прошлого забега стоял бы в новом на тех же
# координатах. Узел уходит вместе со сценой мира. Карты, наоборот, создаются здесь
# (map_create) и освобождаются здесь же — в clear() и при удалении объекта: карта,
# не освобождённая до выхода, печатает утечку RID.
#
# Пока навмеш не готов (запекание идёт, а карта синхронизируется только на одном
# из следующих физкадров после появления региона), map_for не находит региона или
# карта пуста, и путь врагу не отдаётся: S_EnemyAI в этом случае идёт по прямой,
# как шёл без навигации.
#
# Параметры агента, маска геометрии и режим разбора — в шаблонах data/enemy_navmesh*.tres,
# а не в коде: радиус и высота обязаны покрывать тела врагов (dev/enemy_nav_check
# сверяет их со сценами). Разбор идёт по первому шаблону, поэтому маска и режим
# разбора у всех шаблонов общие — это проверка тоже сверяет.
class_name LayerNavigation
extends RefCounted

## Навмеш одного размера готов и стоит в своей карте (карта подхватит его на одном
## из следующих физкадров).
signal baked(region: NavigationRegion3D)

## Шаблоны навмеша по размерам врагов. Первый — обычный, по нему и разбирается
## геометрия.
const PROFILES: Array[String] = [
	"res://data/enemy_navmesh.tres",
	"res://data/enemy_navmesh_large.tres",
]
## Группа регионов слоя — по ней map_for находит карту шаблона.
const GROUP := &"layer_navigation"
const PROFILE_META := &"nav_profile"

## Регионы запечённого слоя по пути шаблона; шаблона нет — не готов или снят.
var regions: Dictionary[String, NavigationRegion3D] = {}
## Сколько заняли разбор геометрии (главный поток) и все запекания подряд (поток),
## мкс — для замера на реальном слое и для профайлера.
var parse_usec := 0
var bake_usec := 0

## Номер запекания: слой мог смениться, пока поток считал, и тогда результат —
## чужой. Сравнивается в _on_baked.
var _serial := 0
var _bake_started := 0
var _maps: Array[RID] = []


## Карта навигации шаблона [param profile] в мире узла [param node]; пустой RID —
## навмеша этого размера сейчас нет (слой ещё запекается или снят).
static func map_for(node: Node, profile: NavigationMesh) -> RID:
	if profile == null or not node.is_inside_tree():
		return RID()
	for region in node.get_tree().get_nodes_in_group(GROUP):
		if region.get_meta(PROFILE_META, "") == profile.resource_path:
			return (region as NavigationRegion3D).get_navigation_map()
	return RID()


## Начинает запекание навмешей по коллизии всего, что стоит под [param root] (корень
## мира: комнаты и тайлы коридоров слоя). Возвращается сразу — разбор синхронный,
## запекание в потоке; о готовности каждого размера говорит [signal baked].
func bake(root: Node) -> void:
	clear()
	if root == null or not root.is_inside_tree():
		return
	var source := NavigationMeshSourceGeometryData3D.new()
	var started := Time.get_ticks_usec()
	NavigationServer3D.parse_source_geometry_data(_template(0), source, root)
	parse_usec = Time.get_ticks_usec() - started
	if not source.has_data():
		push_warning("LayerNavigation: под корнем нет геометрии для навмеша")
		return

	_bake_started = Time.get_ticks_usec()
	_bake_profile(0, source, root)


## Снимает навмеши слоя и обесценивает запекание, которое ещё идёт: его результат
## придёт на главный поток позже и будет отброшен. free(), а не queue_free(): как и
## тайлы коридора, старый регион не должен дожить до нового слоя на тех же клетках.
func clear() -> void:
	_serial += 1
	for region: NavigationRegion3D in regions.values():
		if is_instance_valid(region):
			region.free()
	regions.clear()
	_free_maps()


## Готов ли навмеш: регион каждого размера есть, и карта уже применила его полигоны.
## Регион появляется сразу после запекания, а карта подхватывает его на одном из
## следующих физкадров — итерации карты строятся асинхронно, и номер итерации
## региона (region_get_iteration_id) растёт раньше, чем карта начинает отвечать.
## Поэтому спрашиваем саму карту: ближайшая к вершине навмеша точка карты — эта же
## вершина. Пустая карта на такой запрос отвечает нулём.
func is_ready() -> bool:
	if regions.size() < PROFILES.size():
		return false
	for region: NavigationRegion3D in regions.values():
		if not is_instance_valid(region) or not region.is_inside_tree():
			return false
		var vertices := region.navigation_mesh.get_vertices()
		if vertices.is_empty():
			return false
		var map := region.get_navigation_map()
		# Свежая карта до первой синхронизации на запрос отвечает ошибкой в лог.
		if NavigationServer3D.map_get_iteration_id(map) == 0:
			return false
		var probe := region.global_transform * vertices[0]
		var near := NavigationServer3D.map_get_closest_point(map, probe)
		if near.distance_to(probe) >= region.navigation_mesh.cell_size:
			return false
	return true


## Цикл здесь, а не вызов _free_maps(): на PREDELETE методы своего скрипта уже не
## вызываются (вызов уходит в «null instance»), а поля ещё читаются.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for map in _maps:
			NavigationServer3D.free_rid(map)


## Копия шаблона под ячейку карт: навмеш с другой ячейкой карта не склеивает и
## сыплет предупреждениями, а карты создаются с ячейкой проекта по умолчанию.
func _template(index: int) -> NavigationMesh:
	var mesh := (load(PROFILES[index]) as NavigationMesh).duplicate() as NavigationMesh
	mesh.cell_size = ProjectSettings.get_setting("navigation/3d/default_cell_size")
	mesh.cell_height = ProjectSettings.get_setting("navigation/3d/default_cell_height")
	return mesh


func _bake_profile(index: int, source: NavigationMeshSourceGeometryData3D, root: Node) -> void:
	var mesh := _template(index)
	NavigationServer3D.bake_from_source_geometry_data_async(
		mesh, source, _on_baked.bind(_serial, index, mesh, source, root)
	)


func _on_baked(
	serial: int, index: int, mesh: NavigationMesh,
	source: NavigationMeshSourceGeometryData3D, root: Node
) -> void:
	if serial != _serial or not is_instance_valid(root) or not root.is_inside_tree():
		return
	if mesh.get_polygon_count() == 0:
		push_warning("LayerNavigation: навмеш '%s' запёкся пустым — проверь маску геометрии" % PROFILES[index])
	else:
		var map := NavigationServer3D.map_create()
		NavigationServer3D.map_set_cell_size(map, mesh.cell_size)
		NavigationServer3D.map_set_cell_height(map, mesh.cell_height)
		NavigationServer3D.map_set_active(map, true)
		_maps.append(map)

		var region := NavigationRegion3D.new()
		region.name = "LayerNavigation_%s" % PROFILES[index].get_file().get_basename()
		region.navigation_mesh = mesh
		region.set_navigation_map(map)
		region.set_meta(PROFILE_META, PROFILES[index])
		region.add_to_group(GROUP)
		root.add_child(region)
		regions[PROFILES[index]] = region
		baked.emit(region)

	if index + 1 < PROFILES.size():
		_bake_profile(index + 1, source, root)
	else:
		bake_usec = Time.get_ticks_usec() - _bake_started


func _free_maps() -> void:
	for map in _maps:
		NavigationServer3D.free_rid(map)
	_maps.clear()
