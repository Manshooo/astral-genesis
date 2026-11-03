# res://src/components/gameplay/c_fps_camera.gd
# Маркер FP-камеры (только игрок); NPC без неё S_FPSLook игнорирует.
class_name C_FPSCamera
extends Component

## Накопленный pitch; S_FPSLook обновляет каждый кадр.
@export var pitch: float = 0.0

## Где глаза рига без движения головы облика (камера в координатах рига): ставит O_BodyForm, S_FirstPersonMotion
## кладёт поверх смещение головы. INF — ещё не известна, берётся с камеры.
var eye_position := Vector3.INF
