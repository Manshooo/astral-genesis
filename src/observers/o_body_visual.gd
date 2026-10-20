# res://src/observers/o_body_visual.gd
# Наблюдатель: надевает на душу-риг визуал захваченного тела и снимает при развоплощении (как C_Highlighted → O_OutlineVisual).
# Меняем ТОЛЬКО меш, material_override и transform на том же узле: обводка пишет ему material_overlay, подмена узла оставила бы её на выброшенном.
class_name O_BodyVisual
extends Observer


func query() -> QueryBuilder:
	return q.with_all([C_BodyVisual]).on_added().on_removed()


func each(event: Variant, entity: Entity, payload: Variant = null) -> void:
	# Основной меш: облик подменяет ОДИН меш рига.
	var geo := RS_EntityVisuals.primary(entity) as MeshInstance3D
	if geo == null:
		return
	var visual := payload as C_BodyVisual
	if visual == null:
		return

	match event:
		Observer.Event.ADDED:
			# Прежний вид запоминаем ПЕРЕД подменой; заполненное не трогаем: при пересадке S_BodySnatch переносит сюда облик БФЖ.
			if visual.restore_mesh == null:
				visual.restore_mesh = geo.mesh
				visual.restore_material = geo.material_override
				visual.restore_transform = geo.transform
			geo.mesh = visual.mesh
			geo.material_override = visual.material_override
			_place(entity, geo, visual)
		Observer.Event.REMOVED:
			geo.mesh = visual.restore_mesh
			geo.material_override = visual.restore_material
			if _movable(entity, geo):
				geo.transform = visual.restore_transform


## Трансформ меша из visual относительно ПОДОШВЫ рига. Офсет берём из самого облика, не у рига: наблюдатели облика и
## габарита на разных компонентах, порядок задаёт очередь команд (E_Player.foot_offset дал бы габарит, который риг ещё носит).
func _place(entity: Entity, geo: GeometryInstance3D, visual: C_BodyVisual) -> void:
	if not _movable(entity, geo):
		return
	# Из «относительно подошвы» в «относительно корня рига».
	var lift := visual.foot_offset
	if lift == Vector3.ZERO:
		lift = (entity as E_Player).foot_offset()  # тело габарита не дало — риг остался собой
	var in_rig := visual.mesh_transform
	in_rig.origin -= lift
	# Меш не обязан висеть под корнем (C_VisualRoot): снимаем вклад цепочки родителей.
	var chain := RS_EntityVisuals.transform_relative_to(geo.get_parent(), entity)
	geo.transform = chain.affine_inverse() * in_rig


## Можно ли писать трансформ мешу: если сущность сама GeometryInstance3D, запись сдвинула бы рига целиком.
func _movable(entity: Entity, geo: GeometryInstance3D) -> bool:
	return geo != (entity as Node) and entity is E_Player
