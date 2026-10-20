class_name C_DoorSlot
extends Component
## Авторский маркер дверного проёма в префабе комнаты; slot_id стабилен в префабе (&"north", &"down_a") —
## по нему проём сопоставляется ребру графа независимо от порядка нод.
@export var slot_id: StringName = &""
