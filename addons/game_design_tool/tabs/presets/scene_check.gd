## «Проверка сцен» вкладки «Редактор пресетов»: расхождения slot_count ↔ сцена и разбор дверей по стенам.
## Запуск только кнопкой — проверка инстанцирует сцены комнат.
## [[Редакторские инструменты]] → «Проверка генератора».
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


## slot_id не проставляем автоматически: C_DoorSlot общий у всех дверей проекта (см. вики).
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


## Имён дверей и slot_id в кэше RS_RoomLayout нет — сцена инстанцируется, по разу на пресет.
func _door_lines(preset: RS_RoomPreset) -> Array[String]:
	var lines: Array[String] = []
	if preset.scene == null:
		return lines
	var room := preset.scene.instantiate()
	for door in RS_RoomLayout.door_entities(room):
		var direction := RS_RoomLayout.side_name(RS_RoomLayout.door_side(door as Node as Node3D, room))
		var slot_id := RS_RoomLayout.slot_id_of(door)
		var mark := "" if slot_id == direction else "   → по стене подошёл бы «%s»" % direction
		lines.append(
			"    %s: стена «%s», slot_id «%s»%s"
			% [door.name, direction, slot_id if slot_id != &"" else "—", mark]
		)
	room.free()
	return lines
