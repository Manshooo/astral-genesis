## res://src/resources/interaction/rs_interaction_action.gd
## Переиспользуемый «кирпичик» поведения интерактива: одно действие, назначается через E_InteractableObject.actions.
## Для состояния дольше вызова (таймеры, прогресс) — компонент + система.
class_name RS_InteractionAction
extends Resource

## [param entity] — интерактив с действием, [param interactor] — кто взаимодействует (обычно игрок, не обязателен).
func execute(_entity: Entity, _interactor: Node = null) -> void:
	push_warning(
		"RS_InteractionAction.execute() не переопределён в %s" % get_script().resource_path
	)
