# res://src/systems/physics/s_phasing.gd
# Группа "physics". Бестелесность души: пока висит C_Phasing, из МАСКИ снят бит permeable (душа проходит решётки), а из СЛОЯ —
# solid_actors (враги проходят сквозь душу и не толкают её); когда возможность уснула (C_SoulTrait), оба бита возвращаются.
# Система каждый кадр, а не наблюдатель: маску правит кто угодно, восстановить её можно только повторным утверждением (пишем, когда отличается). Обе половины правила в одном файле, как у S_Jump.
class_name S_Phasing
extends System


## Вторая выборка ограничена C_PlayerInput: фазируется только игрок, утверждать маску всем с C_Velocity значило бы переписывать авторские маски будущих врагов.
func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_Phasing]), _pass_through],
		[q.with_all([C_PlayerInput]).with_none([C_Phasing]), _solid],
	]


func _pass_through(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		_set_solid(entity, false)


func _solid(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		_set_solid(entity, true)


func _set_solid(entity: Entity, solid: bool) -> void:
	var body := entity as Node as CollisionObject3D
	if body == null:
		return
	var mask := body.collision_mask | C_Phasing.PERMEABLE_BIT if solid else body.collision_mask & ~C_Phasing.PERMEABLE_BIT
	var layer := body.collision_layer | C_Phasing.SOLID_ACTOR_BIT if solid else body.collision_layer & ~C_Phasing.SOLID_ACTOR_BIT
	if body.collision_mask != mask:
		body.collision_mask = mask
	if body.collision_layer != layer:
		body.collision_layer = layer
