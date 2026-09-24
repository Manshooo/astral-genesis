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
extends Control

const WORLD_SCENE := "res://src/world/world.tscn"
const CATALOG_PATH := "res://data/run_stat_catalog.tres"

## Проявление из-под шторки, которую опустил RunManager.die(). Короче
## затемнения: гаснущий мир — это событие, а появление итогов — просто переход.
const FADE_IN := 0.35

@onready var _rows: GridContainer = %StatRows
@onready var _revive: Button = %Revive


func _ready() -> void:
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

	for row: RS_RunStatRow in catalog.visible_rows(stats):
		_rows.add_child(_make_cell(tr(row.label_key), false))
		_rows.add_child(_make_cell(catalog.value_text(row, stats), true))


## Строки сводки собираются кодом, а не лежат в сцене: их состав зависит от
## забега (пустые показатели не показываются) и будет пополняться каталогом.
func _make_cell(text: String, is_value: bool) -> Label:
	var label := Label.new()
	label.text = text
	# Текст уже переведён вызывающим (tr) или переводу не подлежит (число):
	# второй прогон через автоперевод искал бы ключ «12» и «Ходок».
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if is_value:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		label.modulate = Color(0.7, 0.7, 0.7)
	return label


func _on_revive_pressed() -> void:
	# Новый забег: world_seed/death_count НЕ трогаем — смерть уже записана, и
	# генерация возьмёт свежий run_seed() из (world_seed, death_count).
	#
	# ЗАГРУЗОЧНЫЙ ЭКРАН ПОКА ЗАГОТОВКА. Генерация комплекса синхронна
	# (RunManager.enter_complex спавнит весь слой за один кадр), поэтому честного
	# прогресса тут быть не может — только показать, что игра не зависла: гасим
	# кнопку, меняем подпись и ДОЖИДАЕМСЯ ОТРИСОВАННОГО КАДРА, иначе новая
	# подпись не успеет появиться на экране до фриза. Настоящий загрузочный экран
	# требует разбить генерацию по кадрам — это отдельная задача.
	_revive.disabled = true
	_revive.text = "RUN_SUMMARY_REVIVING"
	await RenderingServer.frame_post_draw
	get_tree().change_scene_to_file(WORLD_SCENE)
