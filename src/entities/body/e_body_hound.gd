@tool
extends Entity

@onready var physical_bone_simulator: PhysicalBoneSimulator3D = $Skeleton3D/PhysicalBoneSimulator3D

func _ready():
	physical_bone_simulator.physical_bones_start_simulation()
