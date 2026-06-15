# entities/player/player.gd
class_name E_Player
extends Entity

@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape := $CollisionShape3D

func on_ready():
	# Connect scene nodes to components
	var c_mesh = get_component(C_Mesh) as C_Mesh
	if c_mesh:
		c_mesh.mesh_instance = mesh_instance

	# Sync editor-placed transform to component
	# Only valid when scene root is Node3D
	var c_trs = get_component(C_Transform) as C_Transform
	if c_trs:
		c_trs.transform = self.global_transform
