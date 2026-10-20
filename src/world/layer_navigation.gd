# res://src/world/layer_navigation.gd
# Навмеш загруженного слоя: запекается при спавне из коллизии, по которой враги и ходят (навмеш на детали кита разошёлся бы со стеной), стоит в картах, пока слой в дереве.
# Два шага: разбор геометрии (parse_source_geometry_data) — на главном потоке один раз (SceneTree не потокобезопасен), запекания по размерам врагов (PROFILES, карта на каждый размер) — в потоке по тем же
# данным по очереди. Регион живёт узлом под корнем мира, не RID'ом (пережил бы смену сцены), карты создаёт и освобождает этот класс (иначе утечка RID). Пока навмеш не готов, map_for пуст и S_EnemyAI идёт
# по прямой. Параметры агента, маска и режим разбора — в data/enemy_navmesh*.tres; разбор по первому шаблону, маска и режим общие (сверяет dev/enemy_nav_check). Вики: [[Цикл забега]].
class_name LayerNavigation
extends RefCounted

## Навмеш одного размера готов и стоит в своей карте (карта подхватит его на одном из следующих физкадров).
signal baked(region: NavigationRegion3D)

## Шаблоны навмеша по размерам врагов; первый — обычный, по нему разбирается геометрия.
const PROFILES: Array[String] = [
	"res://data/enemy_navmesh.tres",
	"res://data/enemy_navmesh_large.tres",
]
## Группа регионов слоя — по ней map_for находит карту шаблона.
const GROUP := &"layer_navigation"
const PROFILE_META := &"nav_profile"

## Регионы запечённого слоя по пути шаблона; нет — не готов или снят.
var regions: Dictionary[String, NavigationRegion3D] = {}
## Сколько заняли разбор (главный поток) и все запекания (поток), мкс — для замера и профайлера.
var parse_usec := 0
var bake_usec := 0

## Номер запекания: слой мог смениться, пока поток считал (сравнивается в _on_baked).
var _serial := 0
var _bake_started := 0
var _maps: Array[RID] = []


## Карта навигации шаблона profile в мире node; пустой RID — навмеша этого размера сейчас нет.
static func map_for(node: Node, profile: NavigationMesh) -> RID:
	if profile == null or not node.is_inside_tree():
		return RID()
	for region in node.get_tree().get_nodes_in_group(GROUP):
		if region.get_meta(PROFILE_META, "") == profile.resource_path:
			return (region as NavigationRegion3D).get_navigation_map()
	return RID()


## Начинает запекание по коллизии всего под root (корень мира); возвращается сразу — разбор синхронный, запекание в потоке, готовность — [signal baked].
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


## Снимает навмеши слоя и обесценивает идущее запекание. free(), не queue_free(): старый регион не должен дожить до нового слоя на тех же клетках.
func clear() -> void:
	_serial += 1
	for region: NavigationRegion3D in regions.values():
		if is_instance_valid(region):
			region.free()
	regions.clear()
	_free_maps()


## Готов ли навмеш: регион каждого размера есть и карта применила полигоны. Регион появляется сразу, карта подхватывает позже (итерации асинхронны) — спрашиваем саму карту: ближайшая к вершине точка — эта же вершина; пустая отвечает нулём.
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
		# Свежая карта до первой синхронизации отвечает ошибкой в лог.
		if NavigationServer3D.map_get_iteration_id(map) == 0:
			return false
		var probe := region.global_transform * vertices[0]
		var near := NavigationServer3D.map_get_closest_point(map, probe)
		if near.distance_to(probe) >= region.navigation_mesh.cell_size:
			return false
	return true


## Цикл здесь, а не _free_maps(): на PREDELETE методы скрипта уже не вызываются («null instance»), поля читаются.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for map in _maps:
			NavigationServer3D.free_rid(map)


## Копия шаблона под ячейку карт: навмеш с другой ячейкой карта не склеивает и сыплет предупреждениями.
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
