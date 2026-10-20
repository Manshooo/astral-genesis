## res://src/entities/interactable/e_interactable_object.gd
## Основа интерактивных объектов; требования к коллайдеру — [[Взаимодействие]]. Расширение: data-driven actions[],
## сигнал `interacted`, либо override interact() (super.interact() сохраняет actions[] и сигнал).[br]
## C_Interactable настраивается через component_resources сцены: define_components() затёр бы значения инспектора.
@tool
class_name E_InteractableObject
extends Entity

@export var actions: Array[RS_InteractionAction] = []

## Подписывайтесь сюда, если не хотите заводить ни action, ни отдельный класс.
signal interacted(entity: Entity)


func interact() -> void:
	for action in actions:
		if action:
			action.execute(self)
	interacted.emit(self)
