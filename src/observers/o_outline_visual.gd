class_name O_OutlineVisual
extends Observer

const OUTLINE_MATERIAL: Material = preload("res://assets/shared/materials/outline.tres")

func query() -> QueryBuilder:
	return q.with_all([C_Highlighted]).on_added().on_removed()

func each(event: Variant, entity: Entity, _payload: Variant = null) -> void:
	var mesh := entity.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	match event:
		Observer.Event.ADDED:
			mesh.material_overlay = OUTLINE_MATERIAL
		Observer.Event.REMOVED:
			mesh.material_overlay = null
