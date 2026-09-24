## res://addons/game_design_tool/tabs/presets/preset_card.gd
## Карточка пресета во вкладке «Редактор пресетов»: слоты (со сверкой с дверьми
## сцены), вес, тип помещения и навешанные теги.
##
## ПОЧЕМУ теги — табличка навешанных + выпадающий список для добавления, а не
## чекбокс на каждый тег проекта: чекбоксов было бы по одному на КАЖДЫЙ тег
## библиотеки, а не только пресета, — при полусотне тегов карточка превращалась
## бы в длинный список, где смысл несёт меньшинство отмеченных строк. Описание —
## тултипом на строке и на пункте списка: тултип не отъедает высоту у списка,
## который растёт вместе со словарём.
##
## Пресет карточка на месте НЕ меняет: каждое поле уходит в контекст правкой
## «было → стало» (история редактора), а обратно карточка перерисовывается по
## сигналу контекста — тем же путём после правки и после Ctrl+Z.
@tool
extends VBoxContainer

const Ui := preload("res://addons/game_design_tool/shared/ui.gd")
const Tags := preload("res://addons/game_design_tool/shared/tags.gd")
const Library := preload("res://addons/game_design_tool/shared/library.gd")
const Context := preload("res://addons/game_design_tool/tabs/presets/context.gd")

## Куда идти писать описание тега — текст тултипа для тега без записи в словаре.
const TAG_HINT_WHERE := "облаке тегов слева"

const COLOR_MISMATCH := Color(1, 0.45, 0.4)
const COLOR_MATCH := Color(0.6, 0.85, 0.6)
const COLOR_MUTED := Color(1, 1, 1, 0.7)
const COLOR_WARN := Color(1, 0.8, 0.45)

var preset: RS_RoomPreset

var _ctx: Context
var _title: Label
var _scene: Label
var _slots: SpinBox
var _actual: Label
var _weight: SpinBox
var _type: OptionButton
var _type_desc: Label
## Табличка навешанных тегов — строка на тег, кнопка ✕ снимает.
var _tag_list: VBoxContainer
## Все известные теги МИНУС навешанные; пересобирается вместе с табличкой.
var _add_option: OptionButton
## Кандидаты выпадающего списка в порядке его пунктов (у OptionButton своих
## ключей нет — StringName берём отсюда по индексу выделения).
var _add_candidates: Array[StringName] = []

## Заполнение карточки двигает SpinBox/OptionButton, и те шлют свои сигналы так же,
## как от руки. Без флага открытие пресета тут же «сохраняло» его собственные
## значения, а при переключении строки — значения предыдущего пресета в новый.
var _syncing := false
## Перерисовка по сигналу контекста откладывается: сигнал приходит изнутри
## обработчика кнопки ✕ в самой табличке, и немедленная пересборка освобождала бы
## эту кнопку, пока её сигнал ещё обрабатывается. Флаг — чтобы пачка сигналов
## (переименование тега трогает много пресетов) дала одну перерисовку.
var _refill_queued := false


func _init(ctx: Context) -> void:
	_ctx = ctx
	visible = false
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	_ctx.preset_changed.connect(_on_preset_changed)
	_ctx.vocabulary_changed.connect(_queue_refill)


func _build() -> void:
	_title = Ui.section_label()
	add_child(_title)
	_scene = Ui.status_label()
	add_child(_scene)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	grid.add_child(Ui.label("Слоты"))
	var slots_row := HBoxContainer.new()
	_slots = SpinBox.new()
	Library.configure_spin(_slots, Library.SLOT_RANGE)
	_slots.value_changed.connect(_on_slots_changed)
	slots_row.add_child(_slots)
	_actual = Label.new()
	slots_row.add_child(_actual)
	grid.add_child(slots_row)

	grid.add_child(Ui.label("Вес"))
	_weight = SpinBox.new()
	Library.configure_spin(_weight, Library.WEIGHT_RANGE)
	_weight.value_changed.connect(_on_weight_changed)
	grid.add_child(_weight)

	grid.add_child(Ui.label("Тип"))
	_type = OptionButton.new()
	_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_type.item_selected.connect(_on_type_selected)
	grid.add_child(_type)
	add_child(grid)

	_type_desc = Ui.wrap_label("")
	_type_desc.modulate = COLOR_MUTED
	add_child(_type_desc)

	add_child(HSeparator.new())
	add_child(
		Ui.wrap_label(
			"Узел получит эту комнату, только если все теги узла есть здесь. Лишние теги не мешают."
		)
	)
	_tag_list = VBoxContainer.new()
	_tag_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_tag_list)

	var add_row := HBoxContainer.new()
	_add_option = OptionButton.new()
	_add_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_option.item_selected.connect(_on_add_option_selected)
	add_row.add_child(_add_option)
	add_row.add_child(Ui.button("+", _on_add_known_tag_pressed))
	add_child(add_row)


## Показать [param shown]; null прячет карточку.
func show_preset(shown: RS_RoomPreset) -> void:
	preset = shown
	visible = preset != null
	if preset != null:
		_refill()


func _on_preset_changed(changed: RS_RoomPreset) -> void:
	if changed == preset:
		_queue_refill()


func _queue_refill() -> void:
	if preset == null or _refill_queued:
		return
	_refill_queued = true
	_refill.call_deferred()


func _refill() -> void:
	_refill_queued = false
	if preset == null:
		return
	_syncing = true
	_title.text = Library.label_of(preset)
	_title.tooltip_text = preset.resource_path
	var scene_path := preset.scene.resource_path if preset.scene else ""
	_scene.text = scene_path.get_file() if scene_path != "" else "сцена не назначена"
	_scene.tooltip_text = scene_path
	_slots.value = preset.slot_count
	_update_actual_label()
	_weight.value = preset.weight

	_type.clear()
	for text: String in Library.type_labels(_ctx.library, _ctx.type_ids):
		_type.add_item(text)
	_type.select(_ctx.type_index(preset.room_type))
	_syncing = false

	_update_type_desc()
	_rebuild_tag_table()


## «В сцене N» рядом со слотами: тот же рассинхрон, что подсвечен красным в
## таблице, но здесь его видно в момент правки — а правят слоты именно здесь.
func _update_actual_label() -> void:
	var actual: int = _ctx.actual_doors.get(preset.resource_path, -1)
	if actual < 0:
		_actual.text = "в сцене: —"
		_actual.modulate = COLOR_MUTED
	elif actual == preset.slot_count:
		_actual.text = "в сцене: %d ✓" % actual
		_actual.modulate = COLOR_MATCH
	else:
		_actual.text = "в сцене: %d ⚠" % actual
		_actual.modulate = COLOR_MISMATCH


func _update_type_desc() -> void:
	var catalog := _ctx.library.type_catalog if _ctx.library else null
	if preset.room_type == &"":
		_type_desc.text = (
			"Без типа — безликое помещение. Тип ПРЕДПОЧИТАЕТСЯ, а не требуется:"
			+ " узел с типом возьмёт комнату без него, если типизированной нет."
		)
		return
	var description := catalog.description_of(preset.room_type) if catalog else ""
	_type_desc.text = description if description != "" else "Описание типа не заполнено."


func _on_slots_changed(value: float) -> void:
	if _syncing or preset == null or int(value) == preset.slot_count:
		return
	_ctx.edit_preset(
		"Слоты пресета", preset, {"slot_count": [preset.slot_count, int(value)]}, true
	)


func _on_weight_changed(value: float) -> void:
	if _syncing or preset == null or is_equal_approx(value, preset.weight):
		return
	_ctx.edit_preset("Вес пресета", preset, {"weight": [preset.weight, value]}, true)


func _on_type_selected(index: int) -> void:
	if _syncing or preset == null:
		return
	_ctx.edit_preset(
		"Тип пресета", preset, {"room_type": [preset.room_type, _ctx.type_at(index)]}
	)


## Табличка навешанных тегов. Порядок — алфавитный, чтобы снятие/добавление не
## переставляло уже показанные теги местами.
func _rebuild_tag_table() -> void:
	# free(), не queue_free(): отложенное удаление копило бы старые строки поверх
	# новых — пересборка идёт на каждую смену выделения.
	for child: Node in _tag_list.get_children():
		child.free()

	var assigned: Array[StringName] = preset.tags.duplicate()
	assigned.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	if assigned.is_empty():
		_tag_list.add_child(Ui.wrap_label("Тегов нет — добавь ниже."))
	for tag: StringName in assigned:
		_tag_list.add_child(_build_tag_row(tag))
	_rebuild_add_option(assigned)


func _build_tag_row(tag: StringName) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var catalog := _ctx.tag_catalog
	var known := catalog != null and catalog.has_id(tag)
	var name_label := Ui.ellipsis_label(catalog.label_of(tag) if known else String(tag))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = Tags.description_or_hint(catalog, tag, TAG_HINT_WHERE)
	if not known:
		name_label.modulate = COLOR_WARN
	row.add_child(name_label)
	row.add_child(Ui.button("✕", _set_tag.bind(tag, false)))
	return row


## Кандидаты — известные теги минус навешанные: список предлагает только то,
## чего у пресета ещё нет.
func _rebuild_add_option(assigned: Array[StringName]) -> void:
	_add_option.clear()
	_add_candidates.clear()
	var catalog := _ctx.tag_catalog
	for tag: StringName in _ctx.known_tags:
		if assigned.has(tag):
			continue
		_add_candidates.append(tag)
		var known := catalog != null and catalog.has_id(tag)
		_add_option.add_item(catalog.label_of(tag) if known else String(tag))
		_add_option.set_item_tooltip(
			_add_option.item_count - 1, Tags.description_or_hint(catalog, tag, TAG_HINT_WHERE)
		)
	var has_candidates := not _add_candidates.is_empty()
	_add_option.disabled = not has_candidates
	_add_option.tooltip_text = _add_option.get_item_tooltip(0) if has_candidates else ""
	if not has_candidates:
		_add_option.add_item("— все известные теги уже здесь —")


## Наведение на СВЁРНУТУЮ кнопку списка тоже показывает описание — иначе тултип
## был бы виден только в развёрнутом попапе.
func _on_add_option_selected(index: int) -> void:
	if index >= 0 and index < _add_option.item_count:
		_add_option.tooltip_text = _add_option.get_item_tooltip(index)


func _on_add_known_tag_pressed() -> void:
	var index := _add_option.selected
	if preset == null or index < 0 or index >= _add_candidates.size():
		return
	_set_tag(_add_candidates[index], true)


## Повесить или снять тег. Снимок массива «до» — копия: сам массив пресета
## до коммита не трогаем.
func _set_tag(tag: StringName, on: bool) -> void:
	if preset == null or preset.tags.has(tag) == on:
		return
	var after: Array[StringName] = preset.tags.duplicate()
	if on:
		after.append(tag)
	else:
		after.erase(tag)
	_ctx.edit_preset(
		"Повесить тег" if on else "Снять тег", preset, {"tags": [preset.tags.duplicate(), after]}
	)
