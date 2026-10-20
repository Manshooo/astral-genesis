# res://src/observers/o_body_thoughts.gd
# Мысли поглощённых: при ПЕРВОМ захвате нового вида за забег игрок слышит мысль тела (data/body_thoughts.tres) — так
# показывается цель («выбраться») без диалога и маркера. «Первый раз» считает сам наблюдатель (порядок наблюдателей
# события не определён): набор сеется записью забега на complex_entered. Мысль не сразу и не поверх чужой строки.
class_name O_BodyThoughts
extends Observer

const THOUGHTS_PATH := "res://data/body_thoughts.tres"
## Через сколько после захвата показываем мысль, с.
const DELAY := 1.2
## Как часто и сколько раз проверять, освободился ли экран.
const RETRY := 0.6
const MAX_RETRIES := 10

var _thoughts: RS_BodyThoughts
## Виды тел (пути сцен), чьи мысли в этом забеге уже звучали.
var _seen: Dictionary[String, bool] = {}
## Забег, к которому относится _seen: смена накопителя — новый забег.
var _tracked: RS_RunStats


func setup() -> void:
	# load(), а не preload(): падает на кастомном ресурсе в debug/export (см. SkillManager).
	_thoughts = load(THOUGHTS_PATH) as RS_BodyThoughts
	if not RunManager.complex_entered.is_connected(_on_complex_entered):
		RunManager.complex_entered.connect(_on_complex_entered)


func sub_observers() -> Array[Array]:
	return [
		[q.with_all([C_BodySnatch, C_Embodied]).on_event(&"body_snatched"), _on_body_snatched],
	]


## Вход в забег: виденные виды пересобираются из записи (RunStats подписан раньше любого наблюдателя мира).
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
	# Забег сменился без входа: виденное с прошлого — чужое; досевать из записи нельзя (порядок наблюдателей).
	if RunStats.current != _tracked:
		_tracked = RunStats.current
		_seen.clear()
	var path := embodied.body_scene_path
	if _seen.has(path):
		return
	_seen[path] = true
	_schedule(soul, _thoughts.pick(path), DELAY, 0)


## Таймером на сигнал, а не await: возобновлённый метод освобождённого узла — ошибка движка; на паузе мысль не проявится.
func _schedule(soul: Entity, key: StringName, delay: float, attempt: int) -> void:
	get_tree().create_timer(delay, false).timeout.connect(_show.bind(soul, key, attempt))


func _show(soul: Entity, key: StringName, attempt: int) -> void:
	# Игрок вышел из тела или мир сменился — мысль не к месту.
	if not is_instance_valid(soul) or not soul.is_inside_tree() or not soul.has_component(C_Embodied):
		return
	if soul.has_component(C_ScreenMessage):
		if attempt < MAX_RETRIES:
			_schedule(soul, key, RETRY, attempt + 1)
		return  # экран занят дольше обычного — мысль уступает, а не перебивает
	C_ScreenMessage.show_on(soul, String(key))
