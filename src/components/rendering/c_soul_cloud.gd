# res://src/components/rendering/c_soul_cloud.gd
# Облик души вне тела — сгусток тёмного дыма с ядром: голова из карточек, след, стекающий вниз, клочья у камеры.
# Узлы и числа — данные сцены игрока, ведёт S_SoulCloud; во плоти облик гаснет весь. Вики: [[Захват тела]].
class_name C_SoulCloud
extends Component

## Слой отрисовки головы: камера игрока его не рисует — изнутри сгустка была бы стена дыма. Вики: [[Конвенции проекта]] §2.
const OUTSIDE_LAYER := 2

## Корень облика (голова и след); гаснет во плоти.
@export var root_path: NodePath = ^"SoulCloud"
## Голова — MultiMesh карточек-билбордов; узел top_level, карточки отстают по следу в мире.
@export var head_path: NodePath = ^"SoulCloud/Head"
## След — частицы под глазами, стекают к полу.
@export var trail_path: NodePath = ^"SoulCloud/Trail"
## Клочья по краям кадра; висят под камерой, а не под корнем облика: едут с её наклоном.
@export var wisps_path: NodePath = ^"Camera3D/SoulWisps"

@export var count := 30
@export var radius := 0.55
## Сплюснутость по осям: широкий сгусток стелется, а не висит шаром.
@export var shape := Vector3(1.3, 0.55, 1.1)
@export var card_size := Vector2(0.5, 0.9)
## Сколько комков бродит друг относительно друга — форма не держится шаром; 1 — один ком.
@export var lobes := 4
@export var lobe_spread := 0.55
## На ходу карточки отстают до этой доли следа — голова тянется, а не едет целиком.
@export var drag := 0.12
@export var spin := 0.35
@export var rng_seed := 7
## След, по которому отстают карточки: сколько секунд и сколько точек.
@export var trail_seconds := 1.1
@export_range(4, 128) var samples := 32
## Доля частиц следа и клочьев на исходе запаса (1 — сколько на спокойном); насколько клочки бледнеют и
## рвутся — ручки decay_fade и decay_ragged в материалах облика.
@export_range(0.0, 1.0, 0.01) var decay_amount := 0.45

## Рантайм S_SoulCloud. applied: -1 — облик ещё не показывали и не прятали, 0/1 — спрятан/показан.
var applied := -1
## Распад, отданный облику в последнем такте (0 — спокойно, 1 — на исходе; кривая UI_HudMood.decay).
var decay := 0.0
var time := 0.0
var history := PackedVector3Array()
var history_acc := 0.0
var offsets: Array[Vector3] = []
var seeds := PackedFloat32Array()
var sizes := PackedFloat32Array()
