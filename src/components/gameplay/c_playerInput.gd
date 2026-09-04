# res://src/components/gameplay/c_playerInput.gd
class_name C_PlayerInput
extends Component

# Направление движения от клавиатуры. Заполняет S_PlayerInput.
@export var move_direction := Vector3.ZERO
@export var jump_pressed := false
@export var mouse_delta := Vector2.ZERO

# Удерживается ли сейчас ускорение. НЕПРЕРЫВНОЕ состояние, а не защёлка: бег
# длится, пока клавишу держат, и снять его надо ровно тогда, когда отпустили.
# Заполняет S_PlayerInput — там же, где move_direction, по той же причине
# (опрос удерживаемого ввода живёт в группе "input", а не в каждой системе).
@export var sprint_held := false

# Защёлка НАЖАТИЯ ускорения — нужна не бегу, а отказу в нём. Бег сам обходится
# sprint_held, но сообщить «это тело не умеет бегать» надо один раз на нажатие,
# а не каждый кадр удержания; фронт даёт ровно это. Ставит E_Player._input
# (там же, где jump_pressed), гасит S_Sprint — обе половины защёлки в одном
# файле, см. шапку S_Jump.
@export var sprint_pressed := false
