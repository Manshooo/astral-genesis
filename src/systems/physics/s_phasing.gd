# res://src/systems/physics/s_phasing.gd
# Группа: "physics". Проход сквозь проницаемую геометрию — снимает бит слоя
# permeable из МАСКИ сущности, пока на ней висит C_Phasing, и возвращает его,
# когда возможность уснула (см. C_SoulTrait).
#
# ПОЧЕМУ СИСТЕМА КАЖДЫЙ КАДР, А НЕ НАБЛЮДАТЕЛЬ. Маска — состояние узла, а не
# компонента: её правит кто угодно (сцена, будущий эффект, отладка), и
# восстановить её можно только повторным утверждением. Наблюдатель поставил бы
# её один раз на событие и молча разошёлся бы с истиной при первом же стороннем
# изменении. Стоит это одного сравнения на сущность — маска пишется только когда
# отличается.
#
# Обе половины правила — в одном файле по той же причине, что у S_Jump: «кто
# ставит бит обратно» не должно быть вопросом порядка систем.
class_name S_Phasing
extends System


## Вторая выборка ограничена C_PlayerInput намеренно: сегодня фазируется только
## игрок, а утверждать маску всему подряд с C_Velocity значило бы молча
## переписывать авторские маски будущих врагов. Появится фазирующийся враг —
## запрос расширится вместе с ним.
func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_Phasing]), _pass_through],
		[q.with_all([C_PlayerInput]).with_none([C_Phasing]), _solid],
	]


func _pass_through(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		_set_mask_bit(entity, false)


func _solid(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		_set_mask_bit(entity, true)


func _set_mask_bit(entity: Entity, solid: bool) -> void:
	var body := entity as Node as CollisionObject3D
	if body == null:
		return
	var wanted := (
		body.collision_mask | C_Phasing.PERMEABLE_BIT
		if solid
		else body.collision_mask & ~C_Phasing.PERMEABLE_BIT
	)
	if body.collision_mask != wanted:
		body.collision_mask = wanted
