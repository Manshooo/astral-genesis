# res://src/observers/o_body_thoughts.gd
# Мысли поглощённых: при ПЕРВОМ захвате тела нового вида за забег игрок слышит
# мысль этого тела (data/body_thoughts.tres). ЗАЧЕМ: у БФЖ по лору своей цели
# нет, её приносят чужие сознания, и это единственный способ показать цель игры
# («выбраться») изнутри, без диалога и без маркера на карте — карточка «Игровой
# цикл — от и до», §6.
#
# «Первый раз за забег» считает сам наблюдатель, а не RunStats.bodies: порядок
# между наблюдателями одного события не определён, и захват мог бы уже лежать в
# записи забега, а мог бы ещё не лежать. Свой набор виденных видов сеется записью
# забега на входе (complex_entered) — когда ничей захват ещё не идёт, — поэтому
# загрузка сохранённого забега не повторяет мысли тел, которые игрок уже носил.
#
# Мысль выходит не сразу и не поверх занятой строки: само событие приходит в
# момент захвата, когда HUD может показывать «Тело здесь не поместится» или
# подсказку двери, а сообщение без очереди перебило бы их. Отсюда задержка и
# повтор, пока на душе висит чужое сообщение.
class_name O_BodyThoughts
extends Observer

const THOUGHTS_PATH := "res://data/body_thoughts.tres"
## Через сколько после захвата показываем мысль: даём осесть самому захвату
## (смене облика, сообщениям) и самой фразе прозвучать отдельно от него.
const DELAY := 1.2
## Как часто и сколько раз проверять, освободился ли экран от чужого сообщения.
const RETRY := 0.6
const MAX_RETRIES := 10

var _thoughts: RS_BodyThoughts
## Виды тел (пути сцен), чьи мысли в этом забеге уже звучали.
var _seen: Dictionary[String, bool] = {}
## Забег, к которому относится _seen: смена накопителя — новый забег.
var _tracked: RS_RunStats


func setup() -> void:
	# load(), а не preload(): preload резолвится на компиляции и падает на
	# кастомном ресурсе в debug/export-сборке (см. SkillManager.SKILL_TREE_PATH).
	_thoughts = load(THOUGHTS_PATH) as RS_BodyThoughts
	if not RunManager.complex_entered.is_connected(_on_complex_entered):
		RunManager.complex_entered.connect(_on_complex_entered)


func sub_observers() -> Array[Array]:
	return [
		[q.with_all([C_BodySnatch, C_Embodied]).on_event(&"body_snatched"), _on_body_snatched],
	]


## Вход в забег (новый, возрождение или загрузка): список виденных видов
## пересобирается из записи забега. Запись к этому моменту уже есть — RunStats
## подписан на сигнал раньше любого наблюдателя мира.
func _on_complex_entered(_graph: RS_LevelGraph) -> void:
	_tracked = RunStats.current
	_seen.clear()
	if _tracked == null:
		return
	for body: RS_RunBody in _tracked.bodies:
		if body:
			_seen[body.scene_path] = true


func _on_body_snatched(_event: Variant, soul: Entity, _payload: Variant = null) -> void:
	var embodied := soul.get_component(C_Embodied) as C_Embodied
	if embodied == null or embodied.body_scene_path.is_empty() or _thoughts == null:
		return
	# Забег сменился без входа (проверки, перезапуск мира): виденное с прошлого —
	# чужое. Досевать из записи тут нельзя — см. шапку про порядок наблюдателей.
	if RunStats.current != _tracked:
		_tracked = RunStats.current
		_seen.clear()
	var path := embodied.body_scene_path
	if _seen.has(path):
		return
	_seen[path] = true
	_schedule(soul, _thoughts.pick(path), DELAY, 0)


## Таймером на сигнал, а не await: если мир уйдёт вместе с наблюдателем, соединение
## с его методом снимется само, а возобновлённый после await метод освобождённого
## узла — ошибка движка. process_always = false: на паузе мысль не должна
## проявиться поверх меню.
func _schedule(soul: Entity, key: StringName, delay: float, attempt: int) -> void:
	get_tree().create_timer(delay, false).timeout.connect(_show.bind(soul, key, attempt))


func _show(soul: Entity, key: StringName, attempt: int) -> void:
	# Игрок уже вышел из тела или мир сменился — мысль того тела не к месту.
	if not is_instance_valid(soul) or not soul.is_inside_tree() or not soul.has_component(C_Embodied):
		return
	if soul.has_component(C_ScreenMessage):
		if attempt < MAX_RETRIES:
			_schedule(soul, key, RETRY, attempt + 1)
		return  # экран занят дольше обычного — мысль уступает, а не перебивает
	C_ScreenMessage.show_on(soul, String(key))
