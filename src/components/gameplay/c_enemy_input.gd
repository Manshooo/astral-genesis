class_name C_EnemyInput
extends Component
## Желаемое движение врага — заполняет S_EnemyAI, читает S_Walk.
##
## НЕ C_PlayerInput. Первая версия вешала на врага именно C_PlayerInput, чтобы
## бесплатно въехать в S_Walk — и это сломало добрый десяток мест
## (RunManager.travel_to, S_InteractionDetector, HUD), которые находят «игрока»
## запросом «у кого есть C_PlayerInput» без уточнения C_BodySnatch: с двумя
## такими сущностями в мире `execute_one()` мог вернуть врага вместо игрока, и
## переход через дверь/интеракция молча промахивались мимо настоящего игрока.
## Отдельный компонент той же формы даёт S_Walk то же движение, ничего не
## путая с игроком.

@export var move_direction := Vector3.ZERO
