@tool
extends E_Body
## Тело-«ползун»: половина фигуры, рост ~0.85 м. Отдельный скрипт от e_body.gd
## нужен только затем, чтобы у пресета был свой class-владелец под будущее
## поведение; вся механика тела живёт в E_Body и в компонентах сцены.
##
## C_Jump у него нет НАМЕРЕННО: прыгать нечем, и системе прыжка не нужно про это
## знать — тело просто не попадёт в выборку (см. C_BodyTrait).

@onready var physical_bone_simulator: PhysicalBoneSimulator3D = $Skeleton3D/PhysicalBoneSimulator3D


func _ready():
	# E_Body — @tool ради form_of_scene/visual_of_scene для доковских инструментов,
	# а значит _ready() срабатывает и при простом открытии сцены в редакторе. Без
	# этой отсечки Jolt честно роняет риг под гравитацией прямо во вьюпорте, и при
	# каждом сохранении съехавшая поза костей уходит в файл — падение копится от
	# сессии к сессии.
	if Engine.is_editor_hint():
		return
	physical_bone_simulator.physical_bones_start_simulation()
