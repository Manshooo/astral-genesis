# res://src/components/physics/c_velocity.gd
# Чистые данные: пишут системы возможностей (S_Walk/S_Jump/S_Flight/S_Gravity), применяет S_Movement.
class_name C_Velocity
extends Component

@export var velocity := Vector3.ZERO

## На земле ли тело — качество тела, его пишет S_Movement после move_and_slide(); читают анимация и шаги. Сход со
## ступеньки на кадр-другой землю не отнимает (S_Movement.AIR_GRACE), отрыв вверх отнимает сразу.
var grounded := true
var air_time := 0.0
