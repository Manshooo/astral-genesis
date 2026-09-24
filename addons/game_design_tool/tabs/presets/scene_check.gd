## res://addons/game_design_tool/tabs/presets/scene_check.gd
## «Проверка сцен» вкладки «Редактор пресетов» — свёрнутая панель внизу:
## расхождения slot_count ↔ сцена и разбор дверей — какая дверь на какой стене и
## что у неё в slot_id.
##
## Кнопка запуска внутри панели обязательна — открытие панели само ничего не
## считает: проверка инстанцирует сцены комнат, и вешать это на разворот значило
## бы платить паузой за взгляд на прошлый отчёт. Тем же соображением «Прогон
## сидов» в «Генераторе мира» не гоняется сам при открытии своей панели.
##
## Сторона двери определяется через RS_RoomLayout — тем же правилом, которым
## RS_LayerPlan раскладывает слой, иначе инструмент проверял бы не то, что делает
## игра.
@tool
extends VBoxContainer

const Ui := preload("res://addons/game_design_tool/shared/ui.gd")
const Library := preload("res://addons/game_design_tool/shared/library.gd")
const Context := preload("res://addons/game_design_tool/tabs/presets/context.gd")

var _ctx: Context
var _report: RichTextLabel


func _init(ctx: Context) -> void:
	_ctx = ctx
	visible = false
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var run := Ui.button("Проверить сцены", run_check)
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(run)
	_report = Ui.report_label(140)
	add_child(_report)


func report_text() -> String:
	return _report.text


## slot_id мы НЕ проставляем автоматически, хотя рекомендацию печатаем: у дверей,
## не перекрывших component_resources, C_DoorSlot приходит из complex_door.tscn и
## разделяется ВСЕМИ дверьми проекта — запись в него испортила бы все комнаты
## сразу. Плюс на раздачу рёбер slot_id не влияет (сторона берётся из геометрии),
## он остался ключом детерминированной сортировки.
func run_check() -> void:
	if _ctx.library == null and not _ctx.reload():
		return
	var lines: Array[String] = []
	var problems_total := 0
	var checked := Library.vocabulary_presets(_ctx.library)
	for preset: RS_RoomPreset in checked:
		lines.append("[b]%s[/b]" % Library.label_of(preset))
		var problems := _ctx.library.validate_preset(preset)
		problems_total += problems.size()
		for problem in problems:
			lines.append("  [color=#ff7066]! %s[/color]" % problem)
		lines.append_array(_door_lines(preset))

	var head := (
		"[color=#7ad17a]Расхождений нет.[/color]"
		if problems_total == 0
		else "[color=#ff7066]Проблем: %d[/color]" % problems_total
	)
	_report.text = head + "\n" + "\n".join(lines)
	_ctx.set_status("Проверено пресетов: %d" % checked.size())


## Имена дверей и их slot_id кэш RS_RoomLayout не хранит (там только число и
## стороны), поэтому здесь сцена инстанцируется — один раз на пресет, рядом с
## validate_preset. Счётчик «В сцене» в таблице, наоборот, идёт через кэш.
func _door_lines(preset: RS_RoomPreset) -> Array[String]:
	var lines: Array[String] = []
	if preset.scene == null:
		return lines
	var room := preset.scene.instantiate()
	for door in RS_RoomLayout.door_entities(room):
		var direction := RS_RoomLayout.door_direction(door as Node as Node3D, room)
		var slot_id := RS_RoomLayout.slot_id_of(door)
		var mark := "" if slot_id == direction else "   → по стене подошёл бы «%s»" % direction
		lines.append(
			"    %s: стена «%s», slot_id «%s»%s"
			% [door.name, direction, slot_id if slot_id != &"" else "—", mark]
		)
	room.free()
	return lines
