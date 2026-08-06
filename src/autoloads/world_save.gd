# res://src/autoloads/world_save.gd
extends Node
## Персистентное состояние прохождения: world_seed + death_count + прогресс
## текущего забега (RS_WorldSave). "Новая игра" катит новый world_seed, обнуляет
## death_count и сбрасывает прогресс; "Загрузить" продолжает с сохранённого узла.
##
## Сам комплекс не сериализуется: он генерируется детерминированно из
## save.run_seed() (см. RunManager.enter_complex), поэтому сейв — это несколько
## чисел, а не дамп мира.

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
## нужны только позиция в графе и остаток распада.
## [param lifespan_left] отрицательное = БФЖ без C_Lifespan (не сохраняем).
func record_progress(node_id: StringName, lifespan_left: float = -1.0) -> void:
	save.run_in_progress = true
	save.current_node_id = node_id
	if not save.visited_node_ids.has(node_id):
		save.visited_node_ids.append(node_id)
	save.lifespan_remaining = lifespan_left
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
