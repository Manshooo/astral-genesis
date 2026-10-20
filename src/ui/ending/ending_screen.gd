# res://src/ui/ending/ending_screen.gd
## Экран КОНЦОВКИ после побега (RunManager.finish_run): заглушка на месте синематика — текст, титры, затем сводка из RunStats.last и кнопка в меню. Фазы STORY → CREDITS → FINAL; Esc или клик
## пропускают текущую. Сводка после титров — иначе сбила бы тон. Раскладка — в ending_screen.tscn, скрипт ведёт время.
extends UI_MenuScreen

enum Phase { STORY, CREDITS, FINAL }

const CATALOG_PATH := "res://data/run_stat_catalog.tres"
const STAT_ROW_SCENE := preload("res://src/ui/death_screen/stat_row.tscn")

## Проявление из-под шторки finish_run(); медленнее итогов смерти — это выход.
const FADE_IN := 1.2
## Сколько строка проявляется и держится.
const LINE_IN := 1.4
const LINE_HOLD := 1.6
## Пауза после последней строки перед титрами.
const STORY_TAIL := 2.2
## Скорость титров, px/с, не время: длина зависит от числа ролей и перевода.
const CREDITS_SPEED := 70.0
## Сколько строк сводки показывать — штрих, не отчёт.
const SUMMARY_ROWS := 3

## Текущая фаза — для проверок и пропуска.
var phase: Phase = Phase.STORY

var _timeline: Tween

@onready var _story: VBoxContainer = %Story
@onready var _credits: Control = %Credits
@onready var _credits_roll: VBoxContainer = %CreditsRoll
@onready var _final: Control = %Final
@onready var _rows: VBoxContainer = %StatRows
@onready var _to_menu: UI_EchoButton = %ToMenu
@onready var _skip_hint: Label = %SkipHint


func _ready() -> void:
	super._ready()
	# Мы вне игровой сцены: гасим UI-стек, возвращаем курсор; enabled=false ДО close_all() (как у экрана итогов).
	UIManager.enabled = false
	UIManager.close_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_fill_summary()
	UIManager.fade_from_black(FADE_IN)
	_enter_phase(Phase.STORY)


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if phase == Phase.FINAL:
		return
	var mouse := event as InputEventMouseButton
	if (mouse != null and mouse.pressed) or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		skip()


## Пропустить текущую фазу (ввод и проверки); из FINAL ничего не делает.
func skip() -> void:
	match phase:
		Phase.STORY:
			_enter_phase(Phase.CREDITS)
		Phase.CREDITS:
			_enter_phase(Phase.FINAL)


func _enter_phase(next: Phase) -> void:
	phase = next
	if _timeline:
		_timeline.kill()
	match next:
		Phase.STORY:
			_play_story()
		Phase.CREDITS:
			_story.visible = false
			_credits.visible = true
			_play_credits()
		Phase.FINAL:
			_story.visible = false
			_credits.visible = false
			_skip_hint.visible = false
			_final.visible = true
			_final.modulate.a = 0.0
			_timeline = create_tween()
			_timeline.tween_property(_final, "modulate:a", 1.0, ENTER_TIME)
			_to_menu.grab_focus()


## Строки проявляются по одной и остаются; твин последовательный — пропуск убивает одну сущность.
func _play_story() -> void:
	_timeline = create_tween()
	for line in _story.get_children():
		(line as Control).modulate.a = 0.0
	for line in _story.get_children():
		_timeline.tween_property(line, "modulate:a", 1.0, LINE_IN)
		_timeline.tween_interval(LINE_HOLD)
	_timeline.tween_interval(STORY_TAIL)
	_timeline.tween_callback(_enter_phase.bind(Phase.CREDITS))


## Титры едут снизу вверх: старт, когда первая строка за нижним краем, конец — последняя за верхним.
func _play_credits() -> void:
	# Высота окна — из вьюпорта (size корня ещё не раскладан); высота рулона — по минимальному размеру.
	var view_h := get_viewport_rect().size.y
	var roll_h := _credits_roll.get_combined_minimum_size().y
	_credits_roll.position.y = view_h
	_timeline = create_tween()
	_timeline.tween_property(_credits_roll, "position:y", -roll_h, (view_h + roll_h) / CREDITS_SPEED)
	_timeline.tween_callback(_enter_phase.bind(Phase.FINAL))


## Короткая сводка из того же снимка; без снимка блок остаётся без строк.
func _fill_summary() -> void:
	var stats := RunStats.last
	# load(), а не preload() (см. экран итогов).
	var catalog := load(CATALOG_PATH) as RS_RunStatCatalog
	if stats == null or catalog == null:
		return
	var shown := 0
	for row: RS_RunStatRow in catalog.visible_rows(stats):
		if shown >= SUMMARY_ROWS:
			break
		var stat_row: UI_StatRow = STAT_ROW_SCENE.instantiate()
		_rows.add_child(stat_row)
		stat_row.setup(tr(row.label_key), catalog.value_text(row, stats))
		shown += 1


func _on_to_menu_pressed() -> void:
	# Кнопка гаснет от второго нажатия; меню грузится в фоне (SceneLoader, RunManager.scene_changer).
	_to_menu.disabled = true
	_to_menu.busy = true
	await RunManager.scene_changer.call(get_tree(), RunManager.MENU_SCENE)
