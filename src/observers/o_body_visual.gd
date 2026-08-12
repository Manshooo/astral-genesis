# res://src/observers/o_body_visual.gd
# Наблюдатель: надевает на душу-риг визуал захваченного тела и снимает его при
# развоплощении. Тот же приём развязки логики и представления, что
# C_Highlighted → O_OutlineVisual: система захвата про меши ничего не знает, она
# только вешает C_BodyVisual.
#
# Меняем ТОЛЬКО меш, material_override и transform на том же самом узле — не
# подменяя и не пересоздавая его. Обводка пишет тому же узлу material_overlay, и
# подмена узла оставила бы её висеть на выброшенном меше.
class_name O_BodyVisual
extends Observer


func query() -> QueryBuilder:
	return q.with_all([C_BodyVisual]).on_added().on_removed()


func each(event: Variant, entity: Entity, payload: Variant = null) -> void:
	# Основной меш, а не «все»: облик тела подменяет ОДИН меш рига, красить
	# поддерево целиком тут бессмысленно.
	var geo := RS_EntityVisuals.primary(entity) as MeshInstance3D
	if geo == null:
		return
	var visual := payload as C_BodyVisual
	if visual == null:
		return

	match event:
		Observer.Event.ADDED:
			# Запоминаем прежний вид ПЕРЕД подменой — вернуть его больше неоткуда.
			# Уже заполненное не трогаем: при пересадке из тела в тело
			# S_BodySnatch переносит сюда облик БФЖ, и перезаписать его обликом
			# прошлого тела значило бы больше никогда не вернуться к призраку.
			if visual.restore_mesh == null:
				visual.restore_mesh = geo.mesh
				visual.restore_material = geo.material_override
				visual.restore_transform = geo.transform
			geo.mesh = visual.mesh
			geo.material_override = visual.material_override
			_place(entity, geo, visual.mesh_transform)
		Observer.Event.REMOVED:
			geo.mesh = visual.restore_mesh
			geo.material_override = visual.restore_material
			if _movable(entity, geo):
				geo.transform = visual.restore_transform


## Ставит мешу трансформ [param wanted], заданный относительно ПОДОШВЫ рига
## (см. C_BodyVisual.mesh_transform).
func _place(entity: Entity, geo: GeometryInstance3D, wanted: Transform3D) -> void:
	if not _movable(entity, geo):
		return
	# Из «относительно подошвы» в «относительно корня рига»: у рига origin в
	# центре его коллайдера, у тела — в ступнях.
	var in_rig := wanted
	in_rig.origin -= (entity as E_Player).foot_offset()
	# Меш не обязан висеть прямо под корнем сущности (C_VisualRoot умеет увести
	# поиск вглубь), а transform задаётся относительно РОДИТЕЛЯ — снимаем вклад
	# цепочки родителей, иначе их масштаб/сдвиг применился бы вторым слоем.
	var chain := RS_EntityVisuals.transform_relative_to(geo.get_parent(), entity)
	geo.transform = chain.affine_inverse() * in_rig


## Можно ли вообще писать трансформ найденному мешу.
##
## Если сущность сама GeometryInstance3D, primary() вернёт её же — тогда transform
## меша это transform ВСЕГО объекта, и запись сдвинула бы рига целиком. Риг игрока
## не таков (CharacterBody3D с дочерним мешем), но правило поиска геометрии общее
## на всех. E_Player в условии, потому что подошву спрашиваем именно у него.
func _movable(entity: Entity, geo: GeometryInstance3D) -> bool:
	return geo != (entity as Node) and entity is E_Player
