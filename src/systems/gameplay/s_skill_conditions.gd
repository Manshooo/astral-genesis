# res://src/systems/gameplay/s_skill_conditions.gd
# Группа "gameplay". Считает действия игрока для условий рангов (RS_SkillCondition): дистанция; захваты приходят через RunStats.record_body. Зачитывается только пешком (душа
# в теле с C_Walk), только по НОВЫМ клеткам забега (RS_RunStats.credit_cell_distance; размер клетки — у плана слоя), скачок позиции шагом не считается.
# После S_RoomPresence — глубина слоя для плана к этому моменту актуальна. Вики: [[Захват тела]] (навыки).
class_name S_SkillConditions
extends System

## Шаг дальше этого за кадр — перенос (портал, посадка, телепорт оверлея), не ходьба.
const MAX_STEP := 2.5

var _last_position := Vector3.ZERO
var _has_last := false
var _last_depth := -1


func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_RoomPresence]}


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_Embodied, C_Walk])


## process_empty: когда игрок перестал быть «пешим», запомненная позиция устаревает — сброс нужен.
func setup() -> void:
	process_empty = true
	if not SkillManager.condition_completed.is_connected(_on_condition_completed):
		SkillManager.condition_completed.connect(_on_condition_completed)
	# Прогресс идёт кадрами, на диск — вместе с контрольной точкой забега.
	if not WorldSave.progress_saved.is_connected(SkillManager.flush):
		WorldSave.progress_saved.connect(SkillManager.flush)


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if entities.is_empty():
		_has_last = false
		return
	var node := entities[0] as Node as Node3D
	if node == null or not node.is_inside_tree():
		return

	var depth := RunManager.current_depth
	var position := node.global_position
	var step := 0.0
	if _has_last and depth == _last_depth:
		step = Vector2(position.x - _last_position.x, position.z - _last_position.z).length()
	_last_position = position
	_last_depth = depth
	_has_last = true
	if step <= 0.0 or step > MAX_STEP:
		return

	var meters := _new_cell_meters(position, depth, step)
	if meters > 0.0:
		SkillManager.add_distance(meters)


## Сколько из шага засчитывается: ноль вне забега, вне плана и на уже обойденной клетке.
func _new_cell_meters(position: Vector3, depth: int, step: float) -> float:
	var stats := RunStats.current
	if stats == null or RunManager.current_graph == null or depth < 0:
		return 0.0
	var plan := RunManager.plan_for_depth(depth)
	var embedding := plan.embedding as SquareGridEmbedding if plan else null
	if embedding == null:
		return 0.0
	var cell := embedding.cell_at(position)
	return stats.credit_cell_distance(RS_RunStats.cell_key(depth, cell), step, embedding.cell_size)


## «Душа усвоила» — мысль в HUD; показ отложен: компонент сообщения — структурное изменение (правило v9).
func _on_condition_completed(id: StringName, _rank: int) -> void:
	var definition := SkillManager.SKILL_TREE.get_definition(id)
	if definition == null:
		return
	var line := String(tr(&"HUD_MSG_SKILL_CONDITION")) % tr(definition.display_name)
	C_ScreenMessage.show_on.call_deferred(E_Player.find(), line)


func _exit_tree() -> void:
	if SkillManager.condition_completed.is_connected(_on_condition_completed):
		SkillManager.condition_completed.disconnect(_on_condition_completed)
	if WorldSave.progress_saved.is_connected(SkillManager.flush):
		WorldSave.progress_saved.disconnect(SkillManager.flush)
