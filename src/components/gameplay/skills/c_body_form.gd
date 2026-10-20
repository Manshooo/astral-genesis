class_name C_BodyForm
extends Component
## Габарит и уровень глаз захваченного тела на душе-риге: S_BodySnatch вешает, O_BodyForm применяет,
## O_ExpelFromBody снимает. Не поля C_BodyVisual (форма — геймплей, не картинка) и не C_BodyTrait:
## это узлы сцены рига, правит их наблюдатель.

## Форма коллизии тела; null — габарита нет, риг остаётся призрачным.
@export var shape: Shape3D

## Высота глаз над подошвой, м (маркер Eyes в сцене тела). Отрицательное = маркера нет: O_BodyForm берёт
## долю капсулы, а не ноль (камера в полу).
@export var eye_height: float = -1.0

## Что вернуть при развоплощении: заполняет O_BodyForm (призрачная форма живёт в e_player.tscn).
@export var restore_shape: Shape3D
@export var restore_camera: Transform3D


## Насколько origin рига окажется ВЫШЕ подошвы в этой форме. Нужна ДО применения формы (захват ставит
## риг раньше), иначе E_Player.foot_offset() дал бы призрачный габарит. Пустая форма → ZERO.
## считает он сам.
func foot_offset() -> Vector3:
	if shape == null:
		return Vector3.ZERO
	var half := E_Player.shape_half_height(shape)
	return Vector3(0.0, half, 0.0) if half >= 0.0 else Vector3.ZERO
