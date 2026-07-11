## res://src/entities/interactable/e_interactable_object.gd
## Базовая основа для всех интерактивных объектов (см.
## docs/astral-genesis/how-to/Взаимодействие.md для требований к коллайдеру/слою).
##
## Три способа расширения (можно комбинировать):
## 1. Data-driven: назначить actions[] в инспекторе - без кода вообще.
## 2. Signal: подписаться на `interacted` снаружи - для разовых сценарных триггеров.
## 3. Override: унаследовать скрипт и переопределить interact() полностью
##    (можно вызвать super.interact(), чтобы сохранить actions[]/signal и
##    добавить что-то до/после - см. e_incubator.gd).
##
## C_Interactable сюда НЕ добавляется через define_components() - он
## настраивается через component_resources в самой сцене (Inspector), иначе
## сработает известный баг: define_components() затирает Inspector-значения
## дублирующегося компонента.
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
