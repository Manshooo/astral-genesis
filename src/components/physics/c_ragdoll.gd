# res://src/components/physics/c_ragdoll.gd
# Мышцы рэгдолла трупа: профиль (RS_RagdollProfile) лежит в сцене тела, S_Ragdoll подхватывает рэгдолл, когда тот
# стартует, и несколько секунд ведёт его суставы. Не C_BodyTrait — при захвате остаётся с телом. Вики: [[Захват тела]].
class_name C_Ragdoll
extends Component

@export var profile: RS_RagdollProfile

## Откуда пришёл удар, уронивший тело: направление от ударившего к телу по горизонтали; ZERO — тело не сбивали.
## Ставит O_EnemyDeath из C_Struck врага.
var struck_from := Vector3.ZERO

## Скорость, с которой кости уходят из клипа гибели: имя кости → м/с. Пишет e_body_rigged на подхвате, отдаёт S_Ragdoll.
var launch: Dictionary = {}

# Состояние S_Ragdoll. Массив только присваивается целиком: GECS копирует компонент сцены поверхностно, и
# append в общий массив попал бы во все тела сразу.
var simulator: PhysicalBoneSimulator3D
var joints: Array = []
var elapsed := -1.0
var kicked := false
var done := false


## Профиль тела до того, как оно вошло в мир (из _ready тела компоненты ещё не разложены): сначала живой компонент,
## потом заготовка сцены.
static func profile_of(entity: Entity) -> RS_RagdollProfile:
	var ragdoll := entity.get_component(C_Ragdoll) as C_Ragdoll
	if ragdoll != null:
		return ragdoll.profile
	for template in entity.component_resources:
		if template is C_Ragdoll:
			return (template as C_Ragdoll).profile
	return null
