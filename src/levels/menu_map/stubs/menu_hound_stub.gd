# res://src/levels/menu_map/stubs/menu_hound_stub.gd
## Заглушка гончей, которая ест учёного, — до переделанной модели hound с
## действием «ест». Меш и скелет взяты из e_body_hound.tscn, но без сущности: в
## меню нет мира GECS, и телу-сущности там некому служить. Поза «на коленях над
## телом» запечена в кости сцены, чтобы читаться и в редакторе; здесь — только
## то, что делает её едой, а не статуей: голова рвёт рывками, челюсть ходит.
##
## Уходит вместе с заглушкой: пришедшая модель играет анимацию из метки
## menu_action своего узла сама (l_menu_map.gd).
extends Node3D

## Рывки головы — шумом, а не синусом: собака не жуёт ритмично, а дёргает.
const TUG_ANGLE := 0.16
const TUG_RATE := 2.2
const JAW_ANGLE := 0.25
const JAW_RATE := 5.0

var _noise := FastNoiseLite.new()
var _time := 0.0
## Кость → её запечённый поворот: рывок кладётся поверх позы, а не вместо неё.
var _posed := {}

@onready var _skeleton: Skeleton3D = $Skeleton3D
@onready var _neck := _skeleton.find_bone("neck.001")
@onready var _head := _skeleton.find_bone("head")
@onready var _jaw := _skeleton.find_bone("mouth")


func _ready() -> void:
	_noise.frequency = 1.0
	_noise.seed = randi()
	for bone in [_neck, _head, _jaw]:
		_posed[bone] = _skeleton.get_bone_pose_rotation(bone)


func _process(delta: float) -> void:
	_time += delta
	_turn(_neck, Vector3.RIGHT, _noise.get_noise_1d(_time * TUG_RATE) * TUG_ANGLE)
	_turn(_head, Vector3.UP, _noise.get_noise_1d(_time * TUG_RATE + 50.0) * TUG_ANGLE)
	_turn(_jaw, Vector3.RIGHT, (0.5 + 0.5 * sin(_time * JAW_RATE)) * JAW_ANGLE)


func _turn(bone: int, axis: Vector3, angle: float) -> void:
	_skeleton.set_bone_pose_rotation(bone, _posed[bone] * Quaternion(axis, angle))
