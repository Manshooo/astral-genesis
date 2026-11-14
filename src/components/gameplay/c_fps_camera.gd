# res://src/components/gameplay/c_fps_camera.gd
# Камера в глазах формы (только игрок): из неё пока идут лучи игры. Взгляд игрока — в C_ThirdPersonCamera.
# Уходит вместе с наследием первого лица (шаг 5 карточки [[Вид от третьего лица]]).
class_name C_FPSCamera
extends Component

## Где глаза рига без движения головы облика (камера в координатах рига): ставит O_BodyForm, S_FirstPersonMotion
## кладёт поверх смещение головы. INF — ещё не известна, берётся с камеры.
var eye_position := Vector3.INF
