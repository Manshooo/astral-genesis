## res://src/resources/rs_entity_visuals.gd
## Как найти визуальную геометрию сущности — общее правило для обводки (O_OutlineVisual) и облика тела (O_BodyVisual). Только статика.
@tool
class_name RS_EntityVisuals
extends RefCounted


## Все меши сущности: сам узел, если геометрия, плюс поддерево (имя узла ничего не значит). С C_VisualRoot — от указанного узла.
static func geometries(entity: Entity) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	var root := _search_root(entity)
	if root == null:
		return found

	var self_geo := root as GeometryInstance3D
	if self_geo:
		found.append(self_geo)
	# owned=false: иначе меши из инстанцированной под-сцены (.glb) не находятся.
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		found.append(node as GeometryInstance3D)
	return found


## Основной меш — там, где красить «всё» бессмысленно (облик тела подменяет ОДИН меш рига).
static func primary(entity: Entity) -> GeometryInstance3D:
	var all := geometries(entity)
	return all[0] if not all.is_empty() else null


## AnimationTree облика тела или врага (в их сцене он один) или null.
static func animation_tree(entity: Node) -> AnimationTree:
	var found := animation_trees(entity)
	return found[0] if not found.is_empty() else null


## Все AnimationTree сущности. Сейчас у каждой одно — облик (BodyAnimation); список терпит и несколько.
static func animation_trees(entity: Node) -> Array[AnimationTree]:
	var found: Array[AnimationTree] = []
	if entity == null:
		return found
	for node in entity.find_children("*", "AnimationTree", true, false):
		found.append(node as AnimationTree)
	return found


## Разыгрывает облик по ключу места — hash([сид забега, id тела]): тот же сид даёт те же лица, а слой, собранный
## заново, — тех же учёных. Свой ГСЧ, как у начинки комнаты: бросок из общего сдвинул бы весь граф.
static func roll_look(look: C_Look, key: Variant) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	look.material_index = rng.randi_range(0, look.materials.size() - 1) if not look.materials.is_empty() else -1
	look.alternative_index = rng.randi_range(0, look.alternatives.size() - 1) if not look.alternatives.is_empty() else -1


## Надевает разыгранный облик на [param appearance] (узел Visual или инстанс сцены облика): материал — на всю
## геометрию, из альтернатив виден один. Не разыгранный — как в сцене.
static func dress(appearance: Node, look: C_Look) -> void:
	if appearance == null or look == null:
		return
	if look.material_index >= 0 and look.material_index < look.materials.size():
		var material := look.materials[look.material_index]
		var geometry := appearance.find_children("*", "GeometryInstance3D", true, false)
		if appearance is GeometryInstance3D:
			geometry.append(appearance)
		for geo in geometry:
			(geo as GeometryInstance3D).material_override = material
	if look.alternative_index >= 0 and look.alternative_index < look.alternatives.size():
		for i in look.alternatives.size():
			var variant := appearance.find_child(look.alternatives[i], true, false) as Node3D
			if variant != null:
				variant.visible = i == look.alternative_index


## Тело или враг на своём месте: облик разыгрывается по ключу места (если ещё не разыгран) и надевается; копии
## материалов для растворения вблизи камеры выдаются заново — облик их подменил.
static func dress_actor(entity: Entity, key: Variant) -> void:
	var look := entity.get_component(C_Look) as C_Look if entity != null else null
	if look == null:
		return
	if not look.is_rolled():
		roll_look(look, key)
	dress(entity.get_node_or_null(E_Body.VISUAL_NODE), look)
	fade_actor(entity)


## Чужие тела и враги гаснут вблизи камеры попиксельно: ближе x их не видно, дальше y плотные. Камера от третьего
## лица их не обходит, а проходит насквозь (решение 05.11).
const ACTOR_FADE := Vector2(0.4, 1.4)


## Тело или враг — копии материалов с пиксельным растворением вблизи камеры. Не общими материалами: меши ходока и
## ползуна лежат в бинарных .res со встроенным материалом.
static func fade_actor(entity: Node) -> void:
	fade_near_camera(entity, BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER, ACTOR_FADE.x, ACTOR_FADE.y)


## Всей геометрии [param appearance] — копии материалов, которые гаснут дизером по расстоянию до камеры: ближе
## [param near] не видно, дальше [param far] плотно. Общие материалы не трогаются — облик тела делит их с врагами.
## Материал не BaseMaterial3D остаётся как есть. Вики: [[Камера от третьего лица]].
static func fade_near_camera(appearance: Node, mode: BaseMaterial3D.DistanceFadeMode, near: float, far: float) -> void:
	for node in appearance.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.material_override != null:
			mesh.material_override = _faded(mesh.material_override, mode, near, far)
			continue
		for i in mesh.get_surface_override_material_count():
			var active := mesh.get_active_material(i)
			if active != null:
				mesh.set_surface_override_material(i, _faded(active, mode, near, far))


static func _faded(material: Material, mode: BaseMaterial3D.DistanceFadeMode, near: float, far: float) -> Material:
	var base := material as BaseMaterial3D
	if base == null:
		return material
	var copy := base.duplicate() as BaseMaterial3D
	copy.distance_fade_mode = mode
	copy.distance_fade_min_distance = near
	copy.distance_fade_max_distance = far
	return copy


## Снимает рэгдолл с облика, который никогда не падает (враг — его гибель отдаёт труп, риг): кости рэгдолла лежат
## на static_colliders, и капсула носителя упиралась бы в собственное тело.
static func strip_ragdoll(appearance: Node) -> void:
	for simulator in appearance.find_children("*", "PhysicalBoneSimulator3D", true, false):
		simulator.get_parent().remove_child(simulator)
		simulator.free()


## Трансформ узла относительно корня: произведение локальных по цепочке. global_transform не годится — detached-инстанс
## (E_Body.visual_of_scene). Узел == корень → IDENTITY.
static func transform_relative_to(node: Node, root: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial:
			result = spatial.transform * result
		current = current.get_parent()
	return result


## Откуда начинать поиск: C_VisualRoot либо сама сущность.
static func _search_root(entity: Entity) -> Node:
	if entity == null:
		return null
	var override := entity.get_component(C_VisualRoot) as C_VisualRoot
	if override and not override.path.is_empty():
		var node := entity.get_node_or_null(override.path)
		if node:
			return node
		push_warning(
			"RS_EntityVisuals: у «%s» C_VisualRoot указывает на несуществующий узел «%s»"
			% [entity.name, override.path]
		)
	return entity
