class_name S_InteractInput
extends System

func query() -> QueryBuilder:
	return q.with_all([C_Interactable, C_Highlighted])

func process(entities: Array[Entity], components: Array, delta: float) -> void:
	if entities.is_empty():
		return
	if Input.is_action_just_pressed("interact"):
		var target = entities[0]
		if target.has_method("open_skill_menu"):
			target.open_skill_menu()
