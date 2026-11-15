# res://src/components/gameplay/c_fps_camera.gd
# База глаз формы на риге игрока. Взгляд игрока — в C_ThirdPersonCamera; сама камера в глазах кадр не рисует и
# уходит вместе с обликом души первого лица (шаг 6 карточки [[Вид от третьего лица]]).
class_name C_FPSCamera
extends Component

## Где глаза рига (камера в координатах рига): ставит O_BodyForm, по ней встаёт опора камеры от третьего лица.
## INF — ещё не известна, берётся с камеры.
var eye_position := Vector3.INF
