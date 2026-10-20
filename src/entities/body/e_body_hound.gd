@tool
extends E_Body
## Тело-«гончая»: ростовая фигура с собачьей головой, ~1.93 м. Скрипт запускает рэгдолл на старте (временно, до анимаций).

@onready var physical_bone_simulator: PhysicalBoneSimulator3D = $Skeleton3D/PhysicalBoneSimulator3D


func _ready():
	# E_Body — @tool, _ready() срабатывает и в редакторе: без отсечки Jolt роняет риг под гравитацией и поза костей сохраняется в файл.
	if Engine.is_editor_hint():
		return
	physical_bone_simulator.physical_bones_start_simulation()
