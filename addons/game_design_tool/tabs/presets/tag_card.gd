## res://addons/game_design_tool/tabs/presets/tag_card.gd
## Карточка тега во вкладке «Редактор пресетов»: имя и описание из словаря,
## кто тег носит, переименование по всем пресетам и «убрать из словаря».
##
## ПОЧЕМУ описание здесь, а не тултипом у чипа: описание длиннее ключа, и в
## облаке его можно показать разве что тултипом — то есть тому, кто УЖЕ знает,
## какой тег ищет. Здесь оно читается до клика, ради чего словарь и заводили.
##
## Все правки — через контекст, то есть через историю редактора: переименование
## трогает десяток .tres разом, и откатить его руками значило бы помнить каждый.
@tool
extends VBoxContainer

const Ui := preload("res://addons/game_design_tool/shared/ui.gd")
const Library := preload("res://addons/game_design_tool/shared/library.gd")
const Tags := preload("res://addons/game_design_tool/shared/tags.gd")
const Context := preload("res://addons/game_design_tool/tabs/presets/context.gd")

## Показать в таблице пресетов только тех, кто носит тег.
signal filter_requested(tag: StringName)
## Тег переименован — вкладке переключить выделение на новое имя.
signal tag_renamed(new_tag: StringName)
## Тег убран из словаря — карточке больше нечего показывать.
signal forgotten

const COLOR_MUTED := Color(1, 1, 1, 0.7)
const COLOR_WARN := Color(1, 0.8, 0.45)

var tag := &""

var _ctx: Context
var _title: Label
var _uses: Label
var _name_edit: LineEdit
var _desc_edit: TextEdit
var _generator_note: Label
var _rename_btn: Button
var _used_by: Label
var _rename_dialog: ConfirmationDialog
var _rename_edit: LineEdit


func _init(ctx: Context) -> void:
	_ctx = ctx
	visible = false
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	_ctx.vocabulary_changed.connect(_on_vocabulary_changed)


func _build() -> void:
	_title = Ui.section_label()
	add_child(_title)
	_uses = Label.new()
	_uses.modulate = COLOR_MUTED
	add_child(_uses)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(Ui.label("Имя"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "как показывать дизайнеру"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.focus_exited.connect(flush_edits)
	_name_edit.text_submitted.connect(func(_t: String) -> void: flush_edits())
	grid.add_child(_name_edit)
	add_child(grid)

	add_child(Ui.label("Что тег значит"))
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 110)
	_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	# Сохраняем по уходу фокуса, а не на каждый символ: иначе каждая буква была
	# бы перезаписью словаря И шагом истории.
	_desc_edit.focus_exited.connect(flush_edits)
	add_child(_desc_edit)

	_generator_note = Ui.wrap_label(
		"Этот тег генератор ставит узлам сам, и его ключ захардкожен в"
		+ " RS_LevelGraph — переименование здесь сломало бы подбор молча."
	)
	_generator_note.modulate = COLOR_WARN
	add_child(_generator_note)

	var buttons := HBoxContainer.new()
	buttons.add_child(Ui.button("Показать пресеты с тегом", func() -> void: filter_requested.emit(tag)))
	_rename_btn = Ui.button("Переименовать…", _on_rename_pressed)
	buttons.add_child(_rename_btn)
	buttons.add_child(Ui.button("Убрать из словаря", _on_forget_pressed))
	add_child(buttons)

	_used_by = Ui.wrap_label("")
	_used_by.modulate = COLOR_MUTED
	add_child(_used_by)

	_rename_dialog = Ui.text_dialog("Переименовать тег во всех пресетах", _on_rename_confirmed)
	_rename_edit = Ui.dialog_edit(_rename_dialog)
	add_child(_rename_dialog)


## Показать [param shown]; &"" прячет карточку.
func show_tag(shown: StringName) -> void:
	tag = shown
	visible = tag != &""
	if visible:
		_fill()


func _on_vocabulary_changed() -> void:
	if not visible:
		return
	# Тег могли откатить Ctrl+Z до переименования или удалить — показывать
	# карточку исчезнувшего тега незачем.
	if not _ctx.known_tags.has(tag):
		show_tag(&"")
		forgotten.emit()
		return
	_fill()


func _fill() -> void:
	var catalog := _ctx.tag_catalog
	var entry: RS_RoomTag = catalog.by_id(tag) if catalog else null
	_title.text = String(tag)
	var uses := int(_ctx.tag_uses.get(tag, 0))
	_uses.text = "Носят пресетов: %d%s" % [uses, "" if entry else "   ⚠ нет в словаре"]
	_name_edit.text = entry.display_name if entry else ""
	_desc_edit.text = entry.description if entry else ""
	_name_edit.editable = entry != null
	_desc_edit.editable = entry != null
	_generator_note.visible = entry != null and entry.set_by_generator
	_rename_btn.disabled = entry != null and entry.set_by_generator
	_rename_btn.tooltip_text = (
		"Ключ захардкожен в RS_LevelGraph — переименовывать можно только вместе с кодом."
		if _rename_btn.disabled
		else ""
	)
	var names: Array[String] = []
	for preset: RS_RoomPreset in Library.vocabulary_presets(_ctx.library):
		if preset.tags.has(tag):
			names.append(Library.label_of(preset))
	_used_by.text = ", ".join(names) if not names.is_empty() else "— ни у одного пресета"


## Записывает правки имени/описания в словарь. Зовётся по уходу фокуса и перед
## любой сменой выделения: TextEdit не шлёт «готово», и без явного сброса
## описание терялось бы ровно в тот момент, когда пользователь кликает дальше.
func flush_edits() -> void:
	var catalog := _ctx.tag_catalog
	if catalog == null or tag == &"" or not visible:
		return
	var entry := catalog.by_id(tag)
	if entry == null:
		return
	var changes := {}
	if entry.display_name != _name_edit.text:
		changes["display_name"] = [entry.display_name, _name_edit.text]
	if entry.description != _desc_edit.text:
		changes["description"] = [entry.description, _desc_edit.text]
	if changes.is_empty():
		return
	_ctx.edit_many("Описание тега", [_ctx.catalog_edit(entry, changes)], "Словарь сохранён.")


func _on_rename_pressed() -> void:
	if tag != &"":
		Ui.popup_text_dialog(_rename_dialog, "Переименовать тег во всех пресетах", String(tag))


## Переименование идёт по ВСЕМ пресетам разом — вручную это правка десятка
## .tres, и пропущенный превращается в тихую опечатку, то есть в комнату, которая
## больше никуда не подходит.
func _on_rename_confirmed() -> void:
	var new_tag := Tags.tagify(_rename_edit.text)
	if tag == &"" or new_tag == &"" or new_tag == tag:
		return
	var old_tag := tag
	var edits := rename_edits(old_tag, new_tag)
	var merged := _ctx.tag_catalog != null and _ctx.tag_catalog.has_id(new_tag) and _ctx.tag_catalog.has_id(old_tag)
	var touched := 0
	for preset: RS_RoomPreset in Library.vocabulary_presets(_ctx.library):
		touched += 1 if preset.tags.has(old_tag) else 0
	var done := "«%s» → «%s», пресетов затронуто: %d.%s" % [
		old_tag, new_tag, touched,
		" Такой тег уже был — записи словаря слиты в одну." if merged else "",
	]
	if _ctx.edit_many("Переименовать тег", edits, done):
		tag_renamed.emit(new_tag)


## Правки переименования [param old_tag] → [param new_tag] одним шагом истории.
##
## Имя, которое уже занято в словаре, — это СЛИЯНИЕ, а не переименование. Раньше
## запись старого тега просто получала новый id, и в словаре оставались две
## записи с одним ключом: by_id находил первую, вторая становилась невидимой и
## неправимой, а сам дубль видел только validate(), которого эта кнопка не звала.
## Теперь остаётся запись того тега, в который переименовали; пустые поля она
## добирает из старой, чтобы описание не потерялось вместе с ключом.
func rename_edits(old_tag: StringName, new_tag: StringName) -> Array:
	var edits: Array = []
	for preset: RS_RoomPreset in Library.vocabulary_presets(_ctx.library):
		if not preset.tags.has(old_tag):
			continue
		var after: Array[StringName] = preset.tags.duplicate()
		after.erase(old_tag)
		if not after.has(new_tag):
			after.append(new_tag)
		edits.append(_ctx.preset_edit(preset, {"tags": [preset.tags.duplicate(), after]}))

	var catalog := _ctx.tag_catalog
	if catalog == null:
		return edits
	var old_entry := catalog.by_id(old_tag)
	var new_entry := catalog.by_id(new_tag)
	if old_entry and new_entry:
		var entries: Array[RS_RoomTag] = catalog.tags.duplicate()
		entries.erase(old_entry)
		edits.append(_ctx.catalog_edit(catalog, {"tags": [catalog.tags.duplicate(), entries]}))
		var fill := {}
		if new_entry.display_name == "" and old_entry.display_name != "":
			fill["display_name"] = [new_entry.display_name, old_entry.display_name]
		if new_entry.description == "" and old_entry.description != "":
			fill["description"] = [new_entry.description, old_entry.description]
		if not fill.is_empty():
			edits.append(_ctx.catalog_edit(new_entry, fill))
	elif old_entry:
		edits.append(_ctx.catalog_edit(old_entry, {"id": [old_tag, new_tag]}))
	elif new_entry == null:
		# Старого тега в словаре не было — новое имя заводится там сразу: каждый
		# тег пресетов обязан быть в словаре (см. GDT_Tags.register).
		var entries: Array[RS_RoomTag] = catalog.tags.duplicate()
		var entry := RS_RoomTag.new()
		entry.id = new_tag
		entries.append(entry)
		edits.append(_ctx.catalog_edit(catalog, {"tags": [catalog.tags.duplicate(), entries]}))
	return edits


## Убирает ОПИСАНИЕ, а не тег с пресетов: снять тег с комнаты — осознанное
## действие в её карточке, и делать это оптом из словаря опасно (пресет молча
## перестанет подходить своим узлам).
func _on_forget_pressed() -> void:
	var catalog := _ctx.tag_catalog
	if tag == &"" or catalog == null:
		return
	var entry := catalog.by_id(tag)
	if entry == null:
		return
	var uses := int(_ctx.tag_uses.get(tag, 0))
	var entries: Array[RS_RoomTag] = catalog.tags.duplicate()
	entries.erase(entry)
	var tail := (
		"" if uses == 0 else " Сам тег остался у %d пресетов — снимай его в их карточках." % uses
	)
	var removed := tag
	var done := _ctx.edit_many(
		"Убрать тег из словаря",
		[_ctx.catalog_edit(catalog, {"tags": [catalog.tags.duplicate(), entries]})],
		"«%s» убран из словаря.%s" % [removed, tail],
	)
	# Тег, которого никто не носит, исчезает из проекта целиком, и карточка уже
	# закрылась сама (_on_vocabulary_changed); носимый — остаётся, но описывать
	# его здесь больше нечем.
	if done and visible:
		show_tag(&"")
		forgotten.emit()
