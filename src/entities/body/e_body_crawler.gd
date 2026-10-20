@tool
extends E_Body
## Тело-«ползун»: половина фигуры, ~0.85 м. Свой скрипт — под будущее поведение. C_Jump нет НАМЕРЕННО (см. C_BodyTrait).

@onready var physical_bone_simulator: PhysicalBoneSimulator3D = $Skeleton3D/PhysicalBoneSimulator3D


func _ready():
	# E_Body — @tool, _ready() срабатывает и в редакторе: без отсечки Jolt роняет риг под гравитацией и поза костей сохраняется в файл.
	if Engine.is_editor_hint():
		return
	physical_bone_simulator.physical_bones_start_simulation()
