## res://src/entities/interactable/e_interactable_object.gd
## Базовая основа для всех интерактивных объектов (см.
## docs/astral-genesis/how-to/Взаимодействие.md для требований к коллайдеру/слою).
##
## Три способа расширения (можно комбинировать):[br]
## 1. Data-driven: назначить actions[] в инспекторе - без кода вообще.[br]
## 2. Signal: подписаться на `interacted` снаружи - для разовых сценарных триггеров.[br]
## 3. Override: унаследовать скрипт и переопределить interact() полностью[br]
##    (можно вызвать super.interact(), чтобы сохранить actions[]/signal и[br]
##    добавить что-то до/после - см. e_incubator.gd).[br]
## [br]
## C_Interactable сюда не добавляется через define_components() - он
## настраивается через component_resources в самой сцене (Inspector), иначе
## define_components() затирает Inspector-значения дублирующегося компонента.
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
