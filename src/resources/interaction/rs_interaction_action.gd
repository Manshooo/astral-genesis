## res://src/resources/interaction/rs_interaction_action.gd
## Один переиспользуемый "кирпичик" поведения для интерактивных объектов.
## Наследники описывают ОДНО конкретное действие (открыть UI, дать предмет,
## включить рубильник) и назначаются в инспекторе через
## E_InteractableObject.actions - без необходимости писать entity-скрипт
## под каждый новый объект.
##
## Не подходит, если логике нужно состояние, живущее дольше одного вызова
## (таймеры, накопление прогресса) - для этого заводите отдельный компонент
## + систему, а action оставляйте простым триггером.
class_name RS_InteractionAction
extends Resource

## [param entity] интерактивная entity, на которой висит действие.
## [param interactor] кто взаимодействует (обычно игрок). Не обязателен -
## большинству действий не нужен.
func execute(entity: Entity, interactor: Node = null) -> void:
	push_warning(
		"RS_InteractionAction.execute() не переопределён в %s" % get_script().resource_path
	)
