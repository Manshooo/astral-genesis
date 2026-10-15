# res://src/systems/gameplay/s_skill_conditions.gd
# Группа: "gameplay". Считает действия игрока, из которых растут условия рангов
# навыков (RS_SkillCondition): пока это пройденная дистанция. Захваты тел
# приходят событием через RunStats.record_body — им система не нужна.
#
# Что здесь зачитывается, а что нет, и есть «условия в контексте» (карточка
# «Игровой цикл — от и до» §4.1):
#   - только пешком: душа воплощена в теле с C_Walk. Полёт призрака и тело без
#     ног условия ходьбы не двигают, как «Скорость» не действует без ног;
#   - только по НОВЫМ клеткам забега: каждая клетка даёт не больше своей стороны
#     (RS_RunStats.credit_cell_distance), так что круги в колбе километров не
#     набирают. Клетку и её размер спрашиваем у плана слоя — размер клетки живёт
#     только во вложении плана, константы метров здесь нет;
#   - скачок позиции (переход слоя, посадка в тело) шагом не считается.
#
# Группа gameplay, а не physics: рейкастов нет, читается одна координата.
# Порядок: после S_RoomPresence — тот переводит забег в нужный узел, и глубина
# слоя, по которой берём план, к этому моменту уже актуальна.
class_name S_SkillConditions
extends System

## Шаг дальше этого за один кадр — не ходьба, а перенос (портал, посадка в тело,
## телепорт отладочного оверлея). Бегущее тело проходит за кадр сантиметры.
const MAX_STEP := 2.5

var _last_position := Vector3.ZERO
var _has_last := false
var _last_depth := -1


func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_RoomPresence]}


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_Embodied, C_Walk])


## process_empty: когда игрок перестал быть «пешим» (призрак, безногое тело),
## запомненная позиция устаревает, и без сброса первый шаг после возвращения
## считался бы от старого места.
func setup() -> void:
	process_empty = true
	if not SkillManager.condition_completed.is_connected(_on_condition_completed):
		SkillManager.condition_completed.connect(_on_condition_completed)
	# Прогресс идёт кадрами, а на диск попадает вместе с контрольной точкой забега.
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


## Сколько из шага засчитывается: ноль вне забега, вне плана слоя и на клетке,
## которую в этом забеге уже обошли.
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


## «Душа усвоила» — мысль в HUD. Условие может выполниться и внутри прохода
## системы, и внутри обработчика события, поэтому показ отложен: компонент
## сообщения — структурное изменение (Правило v9).
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
