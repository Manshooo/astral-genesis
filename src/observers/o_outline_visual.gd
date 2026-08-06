## Наблюдатель: рисует обводку, пока на сущности висит C_Highlighted.
##
## Красит ВСЕ меши сущности, а не один: составной объект (рама + полотно + ручка)
## должен подсвечиваться целиком, а не наполовину. Где их искать — знает
## RS_EntityVisuals, там же лежит объяснение, почему правило больше не завязано
## на имя узла.
class_name O_OutlineVisual
extends Observer

const OUTLINE_MATERIAL: Material = preload("res://assets/shared/materials/outline_alt.tres")


func query() -> QueryBuilder:
	return q.with_all([C_Highlighted]).on_added().on_removed()


func each(event: Variant, entity: Entity, _payload: Variant = null) -> void:
	var geometries := RS_EntityVisuals.geometries(entity)
	if geometries.is_empty():
		# Раньше промах был МОЛЧАЛИВЫМ: наблюдатель просто выходил, и отладка
		# «почему не подсвечивается» начиналась с нуля. Объект интерактивный, но
		# рисовать нечего — это ошибка сцены, о ней надо знать.
		if event == Observer.Event.ADDED:
			push_warning(
				"O_OutlineVisual: у «%s» нет ни одного GeometryInstance3D — обводить нечего"
				% entity.name
			)
		return

	var overlay: Material = OUTLINE_MATERIAL if event == Observer.Event.ADDED else null
	for geometry in geometries:
		geometry.material_overlay = overlay
