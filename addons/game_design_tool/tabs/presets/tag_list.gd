## res://addons/game_design_tool/tabs/presets/tag_list.gd
## «Облако тегов» вкладки «Редактор пресетов» — таблица всех тегов проекта со
## счётчиком носящих их пресетов и строка «новый тег».
##
## ПОЧЕМУ словарь — вторая таблица здесь же, а не отдельная вкладка: цикл работы
## («выделил пресет → навесил тег») ходит между ними постоянно, и уводить
## описания за переключатель вкладок значило бы вернуть ту же проблему другим
## способом. Что делать с выделенным тегом, решает вкладка (карточка справа);
## список только сообщает о выборе.
@tool
extends VBoxContainer

const Ui := preload("res://addons/game_design_tool/shared/ui.gd")
const Context := preload("res://addons/game_design_tool/tabs/presets/context.gd")

## Выделили тег (&"" — выделение снято).
signal tag_selected(tag: StringName)
## Ввели новый тег — завести и повесить решает вкладка: вешать его надо на
## пресет, выделенный в ДРУГОЙ таблице.
signal new_tag_requested(text: String)

const COL_NAME := 0
const COL_USES := 1
const COLOR_WARN := Color(1, 0.8, 0.45)

var _ctx: Context
var _tree: Tree
var _new_tag_edit: LineEdit
## Тег, выделение которого восстановить после пересборки.
var _selected := &""


func _init(ctx: Context) -> void:
	_ctx = ctx
	add_child(Ui.section_label("Облако тегов"))
	_tree = Tree.new()
	_tree.columns = 2
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(0, 72)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.set_column_title(COL_NAME, "Тег")
	_tree.set_column_title(COL_USES, "Пресетов")
	_tree.set_column_expand(COL_USES, false)
	_tree.set_column_custom_minimum_width(COL_USES, 72)
	_tree.item_selected.connect(_on_selected)
	add_child(_tree)

	var row := HBoxContainer.new()
	_new_tag_edit = LineEdit.new()
	_new_tag_edit.placeholder_text = "новый тег — Enter заводит и вешает на выделенный пресет"
	_new_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_tag_edit.text_submitted.connect(func(_t: String) -> void: _submit_new_tag())
	row.add_child(_new_tag_edit)
	row.add_child(Ui.button("+ тег", _submit_new_tag))
	add_child(row)

	_ctx.vocabulary_changed.connect(rebuild)
	_ctx.library_reloaded.connect(rebuild)


func selected_tag() -> StringName:
	return _selected


## Выделить [param tag] (или снять выделение) без сигнала — вкладке нужно
## синхронизировать список с карточкой, а не получить эхо своего же действия.
func select_quietly(tag: StringName) -> void:
	_selected = tag
	rebuild()


## Сигналы дерева на время пересборки блокируем: восстановление выделения шлёт
## item_selected так же, как клик, и правая панель прыгала бы на карточку тега
## каждый раз, когда тег просто повесили на пресет.
func rebuild() -> void:
	var catalog := _ctx.tag_catalog
	_tree.set_block_signals(true)
	_tree.clear()
	var root := _tree.create_item()
	for tag: StringName in _ctx.known_tags:
		var item := _tree.create_item(root)
		var known := catalog != null and catalog.has_id(tag)
		item.set_text(COL_NAME, String(tag) if known else "⚠ " + String(tag))
		item.set_metadata(COL_NAME, tag)
		if not known:
			item.set_custom_color(COL_NAME, COLOR_WARN)
			item.set_tooltip_text(
				COL_NAME,
				"Тега нет в словаре: описания у него нет, и никто не поручится, что это"
				+ " не опечатка в похожем теге.",
			)
		elif catalog.description_of(tag) != "":
			item.set_tooltip_text(COL_NAME, catalog.description_of(tag))
		var uses := int(_ctx.tag_uses.get(tag, 0))
		item.set_text(COL_USES, str(uses))
		if uses == 0:
			# Описан, но не носится ни одной комнатой — не ошибка (тег могли
			# завести заранее), но повод не искать его в облаке зря.
			item.set_custom_color(COL_USES, Color(1, 1, 1, 0.5))
		if tag == _selected:
			item.select(COL_NAME)
	_tree.set_block_signals(false)


func _on_selected() -> void:
	var item := _tree.get_selected()
	_selected = item.get_metadata(COL_NAME) if item else &""
	tag_selected.emit(_selected)


func _submit_new_tag() -> void:
	var text := _new_tag_edit.text
	_new_tag_edit.text = ""
	if text.strip_edges() != "":
		new_tag_requested.emit(text)
