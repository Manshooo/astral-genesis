class_name C_EnemyInput
extends Component
## Желаемое движение врага — заполняет S_EnemyAI, читает S_Walk.
## НЕ C_PlayerInput: тот — маркер игрока, и с двумя такими сущностями execute_one() вернул бы врага вместо игрока.

@export var move_direction := Vector3.ZERO
