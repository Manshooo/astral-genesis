# res://src/observers/o_body_visual.gd
# Наблюдатель: надевает на душу-риг визуал захваченного тела и снимает его при
# развоплощении. Тот же приём развязки логики и представления, что
# C_Highlighted → O_OutlineVisual: система захвата про меши ничего не знает, она
# только вешает C_BodyVisual.
#
# Меняем ТОЛЬКО меш и material_override на том же самом узле — не подменяя и не
# пересоздавая его. Обводка пишет тому же узлу material_overlay, и подмена узла
# оставила бы её висеть на выброшенном меше.
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
			geo.mesh = visual.mesh
			geo.material_override = visual.material_override
		Observer.Event.REMOVED:
			geo.mesh = visual.restore_mesh
			geo.material_override = visual.restore_material
