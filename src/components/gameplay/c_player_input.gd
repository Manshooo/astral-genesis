# res://src/components/gameplay/c_player_input.gd
# Намерения игрока за кадр — единственный канал от устройств ввода к механикам.
# ЕЩЁ И МАРКЕР ИГРОКА: `with_all([C_PlayerInput]).execute_one()` значит «найти игрока» — врагу
# этот компонент не вешать (у него C_EnemyInput, см. S_Walk).
class_name C_PlayerInput
extends Component

# Направление движения; заполняет S_PlayerInput.
@export var move_direction := Vector3.ZERO
@export var jump_pressed := false
@export var mouse_delta := Vector2.ZERO

# Удерживается ли ускорение: непрерывное состояние, не защёлка. Заполняет S_PlayerInput.
@export var sprint_held := false

# Защёлка НАЖАТИЯ ускорения — для отказа «тело не умеет бегать» раз на нажатие. Ставит
# E_Player._input, гасит S_Sprint (обе половины в одном файле, см. S_Jump).
@export var sprint_pressed := false

# Защёлка НАЖАТИЯ удара: ставит E_Player._input, гасит S_Attack. Темп держит C_Attack.interval.
@export var attack_pressed := false

# Защёлка нажатия клавиши слота способности: номер 1–4, 0 — не нажато. Ставит E_Player._input, гасит S_Abilities.
@export var ability_pressed := 0


## Отпустить всё УДЕРЖИВАЕМОЕ (направление, бег, взгляд): так выглядит ввод под блокирующим экраном
## (C_UIBlocked). Зовут S_PlayerInput каждый кадр блока и UIManager в момент блокировки. Защёлки не трогаем.
func release_held() -> void:
	move_direction = Vector3.ZERO
	mouse_delta = Vector2.ZERO
	sprint_held = false
