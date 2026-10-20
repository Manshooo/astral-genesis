## Наблюдатель: переводит меши выделенной сущности на слой обводки и снимает обратно; контур рисует S_OutlineMask
## постэффектом по маске слоя (толщина в пикселях экрана, составной объект целиком — в отличие от material_overlay).
## Красим ВСЕ меши сущности; где их искать — RS_EntityVisuals.
class_name O_OutlineVisual
extends Observer

## Слой видимости под маску обводки (project.godot → layer_20). Посторонних мешей на нём быть не должно; число одно на двоих — S_OutlineMask берёт отсюда cull_mask.
const OUTLINE_LAYER := 1 << 19


func query() -> QueryBuilder:
	return q.with_all([C_Highlighted]).on_added().on_removed()


func each(event: Variant, entity: Entity, _payload: Variant = null) -> void:
	var geometries := RS_EntityVisuals.geometries(entity)
	if geometries.is_empty():
		# Интерактивный объект без мешей — ошибка сцены, о ней надо знать.
		if event == Observer.Event.ADDED:
			push_warning(
				"O_OutlineVisual: у «%s» нет ни одного GeometryInstance3D — обводить нечего"
				% entity.name
			)
		return

	# Бит выставляем и снимаем, не запоминая маску: слой зарезервирован за обводкой; остальные слои меша не трогаем.
	var lit: bool = event == Observer.Event.ADDED
	for geometry in geometries:
		if lit:
			geometry.layers |= OUTLINE_LAYER
		else:
			geometry.layers = geometry.layers & ~OUTLINE_LAYER
