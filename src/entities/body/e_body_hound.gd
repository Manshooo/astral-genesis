@tool
extends E_Body
## Тело-«гончая»: ростовая фигура с собачьей головой, ~1.93 м.
##
## Единственное, что скрипт добавляет к E_Body, — запуск рэгдолла на старте:
## тело в комнате должно лежать трупом, а не стоять в bind-позе. Это временно и
## держится на скелете сцены; когда у тел появятся анимации, поза мёртвого будет
## их частью, а не физикой.

@onready var physical_bone_simulator: PhysicalBoneSimulator3D = $Skeleton3D/PhysicalBoneSimulator3D


func _ready():
	physical_bone_simulator.physical_bones_start_simulation()
