class_name C_Health
extends Component

@export var maximum := 100.0
@export var current := 100.0

func _init(max_health: float = 100.0):
	maximum = max_health
	current = max_health
