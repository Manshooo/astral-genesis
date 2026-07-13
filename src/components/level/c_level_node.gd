class_name C_LevelNode
extends Component

@export var node_id: StringName = &""
@export var doors: Array[NodePath] = []

# TODO: компонент по идее сам должен шерстить Doors и добавлять в себя узлы/ссылки на узлы.
# Сейчас я вручную добавляю комнатам ссылки на двери. И вообще, как будто "дверь" должна быть отдельной сущнностью
# Как сейчас в hub, но и там я добавил эту структуру нодов. Не знаю как лучше сделать
func _ready() -> void:
	pass
