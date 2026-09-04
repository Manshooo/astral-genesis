# res://src/autoloads/world_save.gd
extends Node
## Персистентное состояние прохождения: world_seed + death_count + прогресс
## текущего забега (RS_WorldSave). "Новая игра" катит новый world_seed, обнуляет
## death_count и сбрасывает прогресс; "Загрузить" продолжает с сохранённого узла.
##
## Сам комплекс не сериализуется: он генерируется детерминированно из
## save.run_seed() (см. RunManager.enter_complex), поэтому сейв — это несколько
## чисел, а не дамп мира.

## Прогресс забега ушёл на диск. Слушает HUD, чтобы показать «Сохранено»:
## запись проходит между кадрами и без отклика игрок не знает, что точка
## поставлена. Сигнал именно у сейва, а не у RunManager: точку ставят из
## нескольких мест (смена комнаты, автосохранение по времени, смена воплощения,
## кнопка в паузе), а факт записи один.
signal progress_saved

const SAVE_PATH := "user://world_save.tres"

var save: RS_WorldSave
## Лежит ли на диске валидный сейв. Пока false, "Загрузить" в главном меню
## неактивна: продолжать нечего, save содержит свежесгенерированную заготовку.
var has_save_file: bool = false


func _ready() -> void:
	save = _load()


## Новая игра: новый мир, счётчик смертей обнулён, прогресс прошлого забега снят.
func new_game() -> void:
	save = RS_WorldSave.new()
	save.world_seed = randi()
	save.death_count = 0
	_save()


## Смерть: следующая генерация комплекса будет другой (death_count входит в сид),
## а незавершённый забег больше не продолжить — загрузка начнёт с входного узла.
func record_death() -> void:
	save.death_count += 1
	save.clear_run()
	_save()


## Контрольная точка забега. Зовётся RunManager при каждой смене комнаты — это
## и есть гранула сохранения: комплекс восстановится из сида, а из состояния
## нужны только позиция в графе, остаток распада и текущее воплощение.
##
## Компоненты сюда не передаём — автолоад сейва про ECS ничего не знает; всё
## разбирает на числа RunManager._checkpoint.
## [param lifespan_left] отрицательное = БФЖ без C_Lifespan (не сохраняем).
## [param body_scene_path] пустая строка = БФЖ развоплощён, HP тогда не значимы.
## [param persist] false — обновить состояние В ПАМЯТИ, не трогая диск. Так
## входят в забег (RunManager._enter_node без came_from): писать там нечего —
## состояние входа выводится из сида и death_count, и на диске уже лежит ровно
## оно, — но текущий узел обязан попасть в visited_node_ids, иначе комната, в
## которой игрок стоит, не считается посещённой ни картой, ни статистикой.
func record_progress(
	node_id: StringName,
	lifespan_left: float = -1.0,
	body_scene_path: String = "",
	body_health: float = 0.0,
	body_health_max: float = 0.0,
	body_lifespan_left: float = 0.0,
	body_lifespan_max: float = 0.0,
	persist: bool = true,
) -> void:
	save.run_in_progress = true
	save.current_node_id = node_id
	if not save.visited_node_ids.has(node_id):
		save.visited_node_ids.append(node_id)
	save.lifespan_remaining = lifespan_left
	save.body_scene_path = body_scene_path
	save.body_health = body_health
	save.body_health_max = body_health_max
	save.body_lifespan_remaining = body_lifespan_left
	save.body_lifespan_max = body_lifespan_max
	if not persist:
		return
	_save()
	progress_saved.emit()


## Итоги ЗАВЕРШЁННОГО забега. Лежат отдельно от прогресса и переживают
## `clear_run()`: забега больше нет, а его сводка — уже часть прохождения. Без
## записи на диск итоги жили бы только в памяти, и закрытая на экране итогов игра
## теряла бы их вместе с процессом — а на них встанет доска истории забегов в
## хабе.
func record_run_summary(stats: RS_RunStats) -> void:
	save.last_run = stats
	_save()


## Тело поглощено захватом — в этом забеге оно больше не появится.
## Пишем на диск сразу, а не на ближайшей контрольной точке: между захватом и
## сменой комнаты игрок может выйти в меню, и тогда съеденное тело воскресло бы
## дубликатом того, в ком он сидит.
func mark_body_consumed(body_id: StringName) -> void:
	if body_id == &"" or save.consumed_body_ids.has(body_id):
		return
	save.consumed_body_ids.append(body_id)
	_save()


## Забег закончился штатно (побег на поверхность) — прохождение остаётся, но
## продолжать нечего. Для смерти есть record_death: там ещё и death_count++.
func clear_run() -> void:
	save.clear_run()
	_save()


func _save() -> void:
	var err := ResourceSaver.save(save, SAVE_PATH)
	if err != OK:
		push_error("WorldSave: не удалось сохранить прогресс, код ошибки %d" % err)
		return
	has_save_file = true


func _load() -> RS_WorldSave:
	if ResourceLoader.exists(SAVE_PATH):
		# CACHE_MODE_IGNORE: без него повторная загрузка вернёт закэшированный
		# ресурс с прошлого запуска редактора вместо содержимого файла.
		var loaded := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as RS_WorldSave
		if loaded:
			has_save_file = true
			return loaded
		push_warning("WorldSave: файл повреждён, начинаю новое прохождение")
	var fresh := RS_WorldSave.new()
	fresh.world_seed = randi()
	return fresh
