class_name S_InteractInput
extends System

func query() -> QueryBuilder:
	return q.with_all([C_Interactable, C_Highlighted])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if entities.is_empty():
		return
	if Input.is_action_just_pressed("interact"):
		var target = entities[0]
		assert(target.has_method("interact"), "Сущность '%s' имеет компонент C_Interactable, но не реализует функцию interact()" % target.name)
		target.interact()
