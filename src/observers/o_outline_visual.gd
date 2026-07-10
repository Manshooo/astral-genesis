class_name O_OutlineVisual
extends Observer

const OUTLINE_MATERIAL: Material = preload("res://assets/shared/materials/outline.tres")

func query() -> QueryBuilder:
	return q.with_all([C_Highlighted]).on_added().on_removed()

func each(event: Variant, entity: Entity, _payload: Variant = null) -> void:
	var geo := _find_geometry(entity)
	if geo == null:
		return

	match event:
		Observer.Event.ADDED:
			geo.material_overlay = OUTLINE_MATERIAL
		Observer.Event.REMOVED:
			geo.material_overlay = null

func _find_geometry(entity: Entity) -> GeometryInstance3D:
	var node: Node = entity
	var self_geo := node as GeometryInstance3D
	if self_geo:
		return self_geo
	return node.get_node_or_null("MeshInstance3D") as GeometryInstance3D
