# res://src/ui/death_screen/death_screen.gd
## Экран ИТОГОВ ЗАБЕГА. Показывается RunManager.die() после того, как смерть
## зафиксирована в сейве (death_count уже увеличен) и мир снесён.
##
## Раньше это было надгробие: чёрный фон и две кнопки. Распад БФЖ — не «конец», а
## часть цикла, и экран теперь рассказывает то же самое: что игрок успел за забег
## и одна кнопка вперёд. Выход в меню отсюда убран намеренно — это обычная пауза
## по Esc уже после возрождения, а вторая кнопка на итогах спорила бы с
## единственным осмысленным действием.
##
## Ни один показатель здесь не назван по имени: строки берутся из
## data/run_stat_catalog.tres, так что «добавить в сводку артефакты» — это правка
## каталога и того, кто их считает, а не этого файла.
##
## Файл всё ещё называется death_screen: путь известен RunManager.DEATH_SCENE, и
## переименование ради вывески стоило бы дороже, чем даёт.
##
## Вид — язык «Отголосок» (§8–§9 «Меню — спека»): без панели, на глухом фоне
## сознание рассеивается точками вверх, заголовок исхода — с двумя эхами, у
## каждой строки сводки — пунктирная выноска к значению.
extends UI_MenuScreen

const WORLD_SCENE := "res://src/world/world.tscn"
const CATALOG_PATH := "res://data/run_stat_catalog.tres"

## Проявление из-под шторки, которую опустил RunManager.die(). Короче
## затемнения: гаснущий мир — это событие, а появление итогов — просто переход.
const FADE_IN := 0.35

const STAT_ROW_SCENE := preload("res://src/ui/death_screen/stat_row.tscn")

@onready var _rows: VBoxContainer = %StatRows
@onready var _revive: UI_EchoButton = %Revive


func _ready() -> void:
	super._ready()
	# Мы вне игровой сцены: погасить игровой UI-стек (дерево навыков могло остаться
	# открытым, если распад случился у инкубатора) и вернуть курсор.
	# ПОРЯДОК ВАЖЕН: enabled=false ДО close_all(), иначе close_all() при enabled=true
	# заново ЗАХВАТИТ курсор (см. UIManager.close_all). Видимый курсор — последним.
	UIManager.enabled = false
	UIManager.close_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_fill_summary()
	UIManager.fade_from_black(FADE_IN)


## Сводка последнего забега. Пустой сводки быть не должно, но если её нет
## (например, сцену открыли напрямую из редактора), экран остаётся заголовком и
## кнопкой — падать из-за отсутствия статистики ему незачем.
func _fill_summary() -> void:
	var stats := RunStats.last
	# load(), а не preload(): preload резолвится на компиляции и падает на
	# кастомном ресурсе в debug/export-сборке — та же грабля, что у
	# SkillManager.SKILL_TREE_PATH.
	var catalog := load(CATALOG_PATH) as RS_RunStatCatalog
	if stats == null or catalog == null:
		return

	# Строки — экземплярами stat_row.tscn, а не в сцене экрана: их состав
	# зависит от забега (пустые показатели не показываются) и будет пополняться
	# каталогом.
	for row: RS_RunStatRow in catalog.visible_rows(stats):
		var stat_row: UI_StatRow = STAT_ROW_SCENE.instantiate()
		_rows.add_child(stat_row)
		stat_row.setup(tr(row.label_key), catalog.value_text(row, stats))


func _on_revive_pressed() -> void:
	# Новый забег: world_seed/death_count НЕ трогаем — смерть уже записана, и
	# генерация возьмёт свежий run_seed() из (world_seed, death_count).
	#
	# Комплекс строится уже в мире, под его загрузочным экраном (UI_LoadingScreen,
	# RunManager.enter_complex_async), а world.tscn до него грузится в фоне
	# (SceneLoader) — кадры идут всё время. Кнопка гаснет, чтобы второе нажатие не
	# начало вход дважды, а подпись и бегущий штрих говорят, что игра работает.
	_revive.disabled = true
	_revive.busy = true
	_revive.text = "RUN_SUMMARY_REVIVING"
	await SceneLoader.change_to(get_tree(), WORLD_SCENE)
