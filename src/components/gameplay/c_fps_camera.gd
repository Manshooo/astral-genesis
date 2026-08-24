# res://src/components/gameplay/c_fps_camera.gd
# Только для entity с FP-камерой (игрок).
# NPC этот компонент не имеют → S_FPSLook их игнорирует.
class_name C_FPSCamera
extends Component

# Накопленный pitch (вверх/вниз). S_FPSLook обновляет каждый кадр.
@export var pitch: float = 0.0
