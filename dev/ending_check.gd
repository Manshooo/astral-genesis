extends "res://dev/check_harness.gd"
## Проверка концовки: побег на поверхность (RunManager.finish_run) ведёт на экран
## концовки и помечает игру пройденной, экран проходит свои фазы и кнопкой уводит
## в меню, а главное меню помнит пройденную игру.
##
## Что здесь важно поймать, потому что руками это ловится только дойдя до двери
## наружу: повторный выход или распад в секунды затемнения не должны засчитаться
## поверх побега (_ending), сейв после финала не стирается, а помечается, и смена
## сцены не должна ронять сам экран (кнопка «В меню»).
##
## Смену сцены подменяет RunManager.scene_changer: настоящая унесла бы саму
## проверку. Запускать: godot --headless dev/ending_check.tscn

const ENDING_SCENE := "res://src/ui/ending/ending_screen.tscn"
const MAIN_MENU_SCENE := "res://src/ui/main_menu/main_menu.tscn"

## Куда finish_run / кнопка повели; пусто — смены сцены не было.
var _changed_to: Array[String] = []
var _finished := 0

## Настоящий сейв разработчика на момент старта: прогон пишет на диск
## (finish_run сохраняет итоги и отметку), и чужое прохождение он ронять не должен.
var _save_backup := PackedByteArray()
var _had_save := false
var _saved_save: RS_WorldSave
var _saved_stats: RS_RunStats
var _saved_current: RS_RunStats
var _saved_enabled := true


func _ready() -> void:
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()
	_saved_save = WorldSave.save
	_saved_stats = RunStats.last
	_saved_current = RunStats.current
	_saved_enabled = UIManager.enabled

	RunManager.scene_changer = _fake_change_scene
	# Шторку затемнения UIManager вешает на корень дерева, а пока тот собирает
	# детей (_ready проверки), add_child на нём отказывает.
	await get_tree().process_frame

	await _check_finish_run()
	await _check_screen()
	await _check_main_menu()

	RunManager.scene_changer = SceneLoader.change_to
	RunManager.current_graph = null
	RunStats.last = _saved_stats
	RunStats.current = _saved_current
	WorldSave.save = _saved_save
	UIManager.enabled = _saved_enabled
	_restore_save()
	_finish()


func _fake_change_scene(_tree: SceneTree, path: String) -> void:
	_changed_to.append(path)


func _count_finish() -> void:
	_finished += 1


## Забег «идёт»: граф есть, накопитель статистики и сейв чистые.
func _begin_run() -> void:
	WorldSave.save = RS_WorldSave.new()
	WorldSave.save.run_in_progress = true
	RunStats.current = RS_RunStats.new()
	RunStats.current.add(RS_RunStats.TIME, 125.0)
	RunStats.last = null
	RunManager.current_graph = RS_LevelGraph.new()
	RunManager._ending = false
	_changed_to.clear()
	_finished = 0


func _check_finish_run() -> void:
	# Не в забеге выходить неоткуда: ни сцены, ни отметки.
	RunManager.current_graph = null
	WorldSave.save = RS_WorldSave.new()
	_changed_to.clear()
	await RunManager.finish_run()
	_check("вне забега побег ничего не делает",
		_changed_to.is_empty() and not WorldSave.save.game_completed, "сцены: %s" % [_changed_to])

	_begin_run()
	RunManager.run_finished.connect(_count_finish)
	# Первый вызов не ждём — он идёт всё затемнение: второй и третий делаются в
	# это окно, и оба обязаны упереться в _ending.
	RunManager.finish_run()
	_check("побег закрывает забег сразу, до конца затемнения", RunManager._ending, "")
	RunManager.finish_run()
	RunManager.die()
	await get_tree().create_timer(RunManager.ENDING_FADE_DURATION + 0.6).timeout
	RunManager.run_finished.disconnect(_count_finish)

	_check("побег ведёт на экран концовки, а не в меню",
		_changed_to == [RunManager.ENDING_SCENE], "сцены: %s" % [_changed_to])
	_check("повторный выход и распад во время затемнения ничего не добавили",
		_finished == 1 and WorldSave.save.death_count == 0, "run_finished: %d, смертей: %d" % [_finished, WorldSave.save.death_count])
	_check("игра помечена пройденной", WorldSave.save.game_completed, "")
	_check("прогресс забега снят, сейв остался",
		not WorldSave.save.run_in_progress and WorldSave.has_save_file, "")
	_check("снимок побега лежит для экрана концовки",
		RunStats.last != null and RunStats.last.outcome == RS_RunStats.OUTCOME_ESCAPE, "")
	_check("забег снесён, флаг окончания снят",
		RunManager.current_graph == null and not RunManager._ending, "")
	# На диске отметка тоже: закрытая на экране концовки игра её не теряет.
	var on_disk := UserResourceFile.read(WorldSave.SAVE_PATH, RS_WorldSave, "WorldSave") as RS_WorldSave
	_check("отметка записана на диск", on_disk != null and on_disk.game_completed, "")

	# Новая игра — чистый лист: отметка уходит со старым прохождением.
	WorldSave.new_game()
	_check("«Новая игра» снимает отметку", not WorldSave.save.game_completed, "")

	# Шторка затемнения осталась чёрной — вернуть.
	await UIManager.fade_from_black(0.0)


func _check_screen() -> void:
	RunStats.last = RS_RunStats.new()
	RunStats.last.add(RS_RunStats.TIME, 125.0)
	RunStats.last.add(RS_RunStats.ROOMS, 7.0)
	RunStats.last.add(RS_RunStats.BODIES, 2.0)
	RunStats.last.add(RS_RunStats.DAMAGE_TAKEN, 40.0)
	_changed_to.clear()

	var screen := (load(ENDING_SCENE) as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	_check("экран концовки начинается с текста",
		screen.phase == screen.Phase.STORY and screen._story.visible and not screen._final.visible, "")
	_check("курсор отпущен, игровой UI погашен",
		Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not UIManager.enabled, "")
	_check("сводка короткая: не больше строк, чем положено",
		screen._rows.get_child_count() > 0 and screen._rows.get_child_count() <= screen.SUMMARY_ROWS,
		"строк: %d" % screen._rows.get_child_count())

	# Esc пропускает текст, клик — титры; в конце пропускать нечего.
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	screen._unhandled_input(esc)
	_check("Esc пропускает текст — идут титры",
		screen.phase == screen.Phase.CREDITS and screen._credits.visible and not screen._story.visible, "")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	screen._unhandled_input(click)
	_check("клик пропускает титры — итог и кнопка",
		screen.phase == screen.Phase.FINAL and screen._final.visible and not screen._skip_hint.visible, "")
	screen.skip()
	_check("из итога пропускать некуда", screen.phase == screen.Phase.FINAL, "")

	_check("кнопка «В меню» на месте и в фокусе",
		screen._to_menu.is_visible_in_tree() and screen._to_menu.has_focus(), "")
	screen._to_menu.pressed.emit()
	await get_tree().process_frame
	_check("кнопка ведёт в меню", _changed_to == [RunManager.MENU_SCENE], "сцены: %s" % [_changed_to])

	screen.queue_free()
	await get_tree().process_frame


func _check_main_menu() -> void:
	var settings := SettingsManager.settings
	var was_calibrated := settings.brightness_calibrated
	settings.brightness_calibrated = true  # без предложения калибровки поверх меню

	WorldSave.save = RS_WorldSave.new()
	var menu := (load(MAIN_MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check("в непройденной игре отметки нет", not menu.completed_note.visible, "")
	menu.queue_free()
	await get_tree().process_frame

	WorldSave.save.game_completed = true
	menu = (load(MAIN_MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check("в пройденной игре меню тихо отмечает это", menu.completed_note.visible, "")
	_check("«Новая игра» остаётся обычным пунктом",
		not (menu.find_child("NewGame", true, false) as Button).disabled, "")
	menu.queue_free()
	await get_tree().process_frame

	settings.brightness_calibrated = was_calibrated


func _restore_save() -> void:
	if _had_save:
		var file := FileAccess.open(WorldSave.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_save_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WorldSave.SAVE_PATH))
	WorldSave.has_save_file = _had_save
	_check("сейв разработчика возвращён на место",
		FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH) == _save_backup, "")
