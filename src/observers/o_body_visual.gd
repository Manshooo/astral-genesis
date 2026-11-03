# res://src/observers/o_body_visual.gd
# Наблюдатель: надевает на душу-риг облик захваченного тела и снимает при развоплощении (как C_Highlighted → O_OutlineVisual).
# Облик-сцену риг инстанцирует узлом WORN_NODE и анимирует своим BodyAnimation; меш БФЖ при этом прячется, а не подменяется.
# Тело без сцены облика отдаёт ОДИН меш — его пишем на тот же узел: обводка пишет ему слой, подмена узла оставила бы её на выброшенном.
class_name O_BodyVisual
extends Observer

## Надетый облик под ригом.
const WORN_NODE := &"WornBody"

## Руки-муляж под камерой рига.
const FP_ARMS_NODE := &"FpArms"

## AnimationTree рига в e_player.tscn: спит, пока облик не надет.
const TREE_NODE := ^"BodyAnimation"


func query() -> QueryBuilder:
	return q.with_all([C_BodyVisual]).on_added().on_removed()


func each(event: Variant, entity: Entity, payload: Variant = null) -> void:
	var visual := payload as C_BodyVisual
	if visual == null:
		return
	# Прошлый облик снимаем ДО поиска меша БФЖ: руки-муляж на камере стоят в дереве раньше него. Пересадка коалесцирует
	# remove+add, так что и при ADDED снимаем сами.
	_take_off(entity)
	# Основной меш — вид БФЖ: облик-сцена его прячет, облик-меш подменяет.
	var geo := RS_EntityVisuals.primary(entity) as MeshInstance3D
	if geo == null:
		return

	match event:
		Observer.Event.ADDED:
			# Прежний вид запоминаем ПЕРЕД подменой; заполненное не трогаем: при пересадке S_BodySnatch переносит сюда облик БФЖ.
			if visual.restore_mesh == null:
				visual.restore_mesh = geo.mesh
				visual.restore_material = geo.material_override
				visual.restore_transform = geo.transform
			if visual.scene != null:
				_restore(entity, geo, visual)
				geo.visible = false
				_put_on(entity, visual)
			else:
				geo.visible = true
				geo.mesh = visual.mesh
				geo.material_override = visual.material_override
				_place(entity, geo, visual)
		Observer.Event.REMOVED:
			geo.visible = true
			_restore(entity, geo, visual)


func _restore(entity: Entity, geo: GeometryInstance3D, visual: C_BodyVisual) -> void:
	(geo as MeshInstance3D).mesh = visual.restore_mesh
	geo.material_override = visual.restore_material
	if _movable(entity, geo):
		geo.transform = visual.restore_transform


## Инстанс облика под ригом: голова и руки только тенью, рэгдолл снят, клипы — деревом тела на узле рига.
func _put_on(entity: Entity, visual: C_BodyVisual) -> void:
	var rig := entity as Node as Node3D
	if rig == null:
		return
	var worn := visual.scene.instantiate() as Node3D
	worn.name = WORN_NODE
	RS_EntityVisuals.strip_ragdoll(worn)
	RS_EntityVisuals.hide_from_wearer(worn)
	for geo: GeometryInstance3D in worn.find_children("*", "GeometryInstance3D", true, false):
		if visual.material_overrides.has(geo.name):
			geo.material_override = visual.material_overrides[geo.name]
	rig.add_child(worn)
	worn.transform = _in_rig(entity, visual)

	var player := entity as E_Player
	if visual.fp_arms != null and player != null and player.camera != null:
		var arms := visual.fp_arms.instantiate()
		arms.name = FP_ARMS_NODE
		player.camera.add_child(arms)

	var tree := rig.get_node_or_null(TREE_NODE) as AnimationTree
	if tree == null or visual.tree_root == null:
		return
	for key in tree.get_animation_library_list():
		tree.remove_animation_library(key)
	for key in visual.libraries:
		tree.add_animation_library(key, visual.libraries[key])
	tree.tree_root = visual.tree_root
	tree.root_node = tree.get_path_to(worn)
	tree.active = true


func _take_off(entity: Entity) -> void:
	var rig := entity as Node
	var tree := rig.get_node_or_null(TREE_NODE) as AnimationTree
	if tree != null:
		tree.active = false
		tree.tree_root = null
	_drop(rig, WORN_NODE)
	var player := entity as E_Player
	if player != null and player.camera != null:
		_drop(player.camera, FP_ARMS_NODE)


func _drop(holder: Node, node_name: StringName) -> void:
	var old := holder.get_node_or_null(NodePath(node_name))
	if old != null:
		holder.remove_child(old)
		old.queue_free()


## Трансформ облика из visual относительно ПОДОШВЫ рига. Офсет берём из самого облика, не у рига: наблюдатели облика и
## габарита на разных компонентах, порядок задаёт очередь команд (E_Player.foot_offset дал бы габарит, который риг ещё носит).
func _in_rig(entity: Entity, visual: C_BodyVisual) -> Transform3D:
	var lift := visual.foot_offset
	if lift == Vector3.ZERO and entity is E_Player:
		lift = (entity as E_Player).foot_offset()  # тело габарита не дало — риг остался собой
	var in_rig := visual.mesh_transform
	in_rig.origin -= lift
	return in_rig


func _place(entity: Entity, geo: GeometryInstance3D, visual: C_BodyVisual) -> void:
	if not _movable(entity, geo):
		return
	# Меш не обязан висеть под корнем (C_VisualRoot): снимаем вклад цепочки родителей.
	var chain := RS_EntityVisuals.transform_relative_to(geo.get_parent(), entity)
	geo.transform = chain.affine_inverse() * _in_rig(entity, visual)


## Можно ли писать трансформ мешу: если сущность сама GeometryInstance3D, запись сдвинула бы рига целиком.
func _movable(entity: Entity, geo: GeometryInstance3D) -> bool:
	return geo != (entity as Node) and entity is E_Player
