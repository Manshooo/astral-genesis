class_name O_OutlineVisual
extends Observer

const OUTLINE_MATERIAL: Material = preload("res://assets/shared/materials/outline.tres")

func query() -> QueryBuilder:
	return q.with_all([C_Highlighted]).on_added().on_removed()

func each(event: Variant, entity: Entity, _payload: Variant = null) -> void:
	var mesh := _find_mesh(entity)
	if mesh == null:
		print('mesh is null')
		return
	print('mesh is not null')
		
	match event:
		Observer.Event.ADDED:
			mesh.material_overlay = OUTLINE_MATERIAL
		Observer.Event.REMOVED:
			mesh.material_overlay = null

func _find_mesh(entity: Entity) -> MeshInstance3D:
	var node: Node = entity
	var self_mesh := node as MeshInstance3D
	if self_mesh:
		return self_mesh
	return node.get_node_or_null("MeshInstance3D") as MeshInstance3D
