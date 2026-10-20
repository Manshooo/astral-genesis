# res://src/ui/death_screen/death_screen.gd
## Экран ИТОГОВ ЗАБЕГА: RunManager.die() показывает его после фиксации смерти в сейве и сноса мира. Заголовок исхода, сводка из data/run_stat_catalog.tres (ни один показатель
## не назван здесь) и одна кнопка вперёд; выхода в меню нарочно нет. Файл зовётся death_screen: путь известен RunManager.DEATH_SCENE. Язык «Отголосок» (§8–§9 «Меню — спека»). Вики: [[Цикл забега]].
extends UI_MenuScreen

const WORLD_SCENE := "res://src/world/world.tscn"
const CATALOG_PATH := "res://data/run_stat_catalog.tres"

## Проявление из-под шторки RunManager.die(); короче затемнения.
const FADE_IN := 0.35

const STAT_ROW_SCENE := preload("res://src/ui/death_screen/stat_row.tscn")

@onready var _rows: VBoxContainer = %StatRows
@onready var _revive: UI_EchoButton = %Revive


func _ready() -> void:
	super._ready()
	# Мы вне игровой сцены: гасим игровой UI-стек и возвращаем курсор. enabled=false ДО close_all(), иначе тот заново захватит курсор (UIManager.close_all).
	UIManager.enabled = false
	UIManager.close_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_fill_summary()
	UIManager.fade_from_black(FADE_IN)


## Сводка последнего забега; без неё (сцена открыта из редактора) остаётся заголовок и кнопка.
func _fill_summary() -> void:
	var stats := RunStats.last
	# load(), а не preload(): падает на кастомном ресурсе в debug/export (см. SkillManager.SKILL_TREE_PATH).
	var catalog := load(CATALOG_PATH) as RS_RunStatCatalog
	if stats == null or catalog == null:
		return

	# Строки — экземплярами stat_row.tscn: состав зависит от забега.
	for row: RS_RunStatRow in catalog.visible_rows(stats):
		var stat_row: UI_StatRow = STAT_ROW_SCENE.instantiate()
		_rows.add_child(stat_row)
		stat_row.setup(tr(row.label_key), catalog.value_text(row, stats))


func _on_revive_pressed() -> void:
	# Новый забег: world_seed/death_count не трогаем — смерть уже записана. Комплекс строится под загрузочным экраном (UI_LoadingScreen, enter_complex_async); кнопка гаснет от второго нажатия.
	_revive.disabled = true
	_revive.busy = true
	_revive.text = "RUN_SUMMARY_REVIVING"
	await SceneLoader.change_to(get_tree(), WORLD_SCENE)
