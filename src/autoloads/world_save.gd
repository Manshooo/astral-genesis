# res://src/autoloads/world_save.gd
extends Node
## Персистентное состояние прохождения: world_seed + death_count (RS_WorldSave).
## "Новая игра" катит новый world_seed и обнуляет death_count; "Загрузить" —
## восстанавливает. Комплекс генерируется детерминированно из save.run_seed()
## (см. RunManager.enter_complex).

const SAVE_PATH := "user://world_save.tres"

var save: RS_WorldSave


func _ready() -> void:
	save = _load()


## Новая игра: новый мир, счётчик смертей обнулён.
func new_game() -> void:
	save = RS_WorldSave.new()
	save.world_seed = randi()
	save.death_count = 0
	_save()


## Смерть: следующая генерация комплекса будет другой (death_count входит в сид).
## Пока не вызывается — включится с флоу смерти (нужны состояния).
func record_death() -> void:
	save.death_count += 1
	_save()


func _save() -> void:
	var err := ResourceSaver.save(save, SAVE_PATH)
	if err != OK:
		push_error("WorldSave: не удалось сохранить прогресс, код ошибки %d" % err)


func _load() -> RS_WorldSave:
	if ResourceLoader.exists(SAVE_PATH):
		var loaded := ResourceLoader.load(SAVE_PATH) as RS_WorldSave
		if loaded:
			return loaded
		push_warning("WorldSave: файл повреждён, начинаю новое прохождение")
	var fresh := RS_WorldSave.new()
	fresh.world_seed = randi()
	return fresh
