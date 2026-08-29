extends Node
## Проверяет Room Wizard (addons/game_design_tool/dock/room_wizard.gd) — то,
## что молча ломается: рефлексивная форма показывает не те поля, путь
## ресурса посчитан неверно, тег не нормализуется. Кнопки «Сохранить»/
## «Добавить в библиотеку» здесь НЕ проверяются — они пишут в реальные файлы
## проекта, а не то, что можно безопасно гонять на каждом прогоне; их
## поведение проверяется живым прогоном в редакторе.
## Запуск: godot --headless dev/room_wizard_check.tscn

var _ok := 0
var _fail := 0

const RoomWizard := preload("res://addons/game_design_tool/dock/room_wizard.gd")
## Нормализация тега уехала из дока в общий GDT_Tags — там же её и проверяем,
## иначе тест сторожил бы делегирующую обёртку, а не правило.
const Tags := preload("res://addons/game_design_tool/shared/tags.gd")

## Не все 13 сцен — этого достаточно, чтобы поймать регресс в форме/пути.
const ROOM_SCENES := [
	"res://src/levels/procedural/rooms/default/default_room.tscn",
	"res://src/levels/procedural/rooms/exit/exit_room.tscn",
	"res://src/levels/procedural/rooms/lab/lab_room.tscn",
	"res://src/levels/procedural/rooms/vertical/vertical_hub_1.tscn",
	"res://src/levels/procedural/rooms/cross_A/cross_a_1.tscn",
]


func _ready() -> void:
	var wizard := RoomWizard.new()

	_check_tagify()
	_check_no_scene(wizard)
	for scene_path in ROOM_SCENES:
		_check_scene(wizard, scene_path)
	_check_hub_scene(wizard)

	wizard.free()
	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _check_tagify() -> void:
	_check(
		"tagify нормализует регистр и пробелы",
		Tags.tagify("  Vertical Hub  ") == &"vertical_hub",
		String(Tags.tagify("  Vertical Hub  "))
	)
	_check(
		"tagify схлопывает пунктуацию в один _",
		Tags.tagify("door--slot!!") == &"door_slot",
		String(Tags.tagify("door--slot!!"))
	)
	_check(
		"tagify пустой строки — пустой StringName",
		Tags.tagify("   ") == &"",
		String(Tags.tagify("   "))
	)
	# Теги — ASCII-ключи, в отличие от имён файлов (GDT_Fs.slug пропускает
	# кириллицу). Разъедься эти два правила — кириллический тег молча уехал бы
	# в RS_RoomPreset.tags и не совпал бы ни с одним ключом узла.
	_check(
		"tagify выбрасывает кириллицу (ключ, а не текст для игрока)",
		Tags.tagify("Лаборатория lab") == &"lab",
		String(Tags.tagify("Лаборатория lab"))
	)


func _check_no_scene(wizard: RoomWizard) -> void:
	wizard.refresh_for_scene(null)
	_check("без сцены форма пуста", wizard._field_controls.is_empty(), str(wizard._field_controls.size()))
	_check("без сцены кнопка сохранения выключена", wizard._save_btn.disabled, "")
	_check("без сцены кнопка библиотеки выключена", wizard._add_to_library_btn.disabled, "")


func _check_scene(wizard: RoomWizard, scene_path: String) -> void:
	var room := (load(scene_path) as PackedScene).instantiate()
	wizard.refresh_for_scene(room)

	var expected_preset_path := scene_path.get_basename() + ".tres"
	var label := scene_path.get_file()

	_check(
		"%s: путь пресета — рядом со сценой, тот же файл" % label,
		wizard._preset_path == expected_preset_path,
		wizard._preset_path
	)
	_check(
		"%s: пресет уже существует (мигрирован Room Wizard'ом)" % label,
		ResourceLoader.exists(expected_preset_path),
		expected_preset_path
	)

	# Рефлексивная форма: ровно скалярные @export-поля RS_RoomPreset — не
	# scene/tags (своя вёрстка) и не служебные поля базового Resource
	# (resource_local_to_scene и т.п.) — иначе фильтр PROPERTY_USAGE сломан.
	var fields: Array = wizard._field_controls.keys()
	fields.sort()
	_check(
		"%s: форма — ровно display_name/slot_count/weight" % label,
		fields == ["display_name", "slot_count", "weight"],
		str(fields)
	)
	# Тип помещения — отдельный контрол, а не поле рефлексивной формы (в форме
	# StringName нарисовался бы нередактируемой строкой). Проверяем ровно то,
	# чем он опасен: пустой или сбитый список делает сохранение РАЗРУШИТЕЛЬНЫМ —
	# _apply_form_to_preset возьмёт из него «нет типа» и сотрёт авторский.
	var selected: int = wizard._type_option.get_selected()
	_check(
		"%s: список типов заполнен и показывает тип пресета" % label,
		(
			wizard._type_option.item_count > 0
			and selected >= 0
			and selected < wizard._type_ids.size()
			and wizard._type_ids[selected] == wizard._preset.room_type
		),
		"пунктов %d, выбран %d, у пресета «%s»" % [
			wizard._type_option.item_count, selected, wizard._preset.room_type],
	)
	_check("%s: кнопка сохранения включена" % label, not wizard._save_btn.disabled, "")
	_check(
		"%s: кнопка библиотеки включена (пресет уже на диске)" % label,
		not wizard._add_to_library_btn.disabled,
		""
	)

	room.free()


## Хаб — единственная сцена, где «Сохранить» ведёт себя как обычно (форма
## читает hub.tres так же, как любой другой пресет), а «Добавить в библиотеку»
## обязана быть выключена структурно: попади hub.tres в library.presets —
## его пустые tags и slot_count=1 сделали бы его кандидатом-победителем для
## ЛЮБОГО непомеченного узла-тупика во всём графе (см.
## RS_RoomPresetLibrary.hub, room_wizard.gd._set_active).
func _check_hub_scene(wizard: RoomWizard) -> void:
	var room := (load(RS_LevelGraph.HUB_ROOM_SCENE) as PackedScene).instantiate()
	wizard.refresh_for_scene(room)

	_check(
		"хаб: путь пресета — рядом со сценой, тот же файл",
		wizard._preset_path == RS_LevelGraph.HUB_ROOM_SCENE.get_basename() + ".tres",
		wizard._preset_path
	)
	_check("хаб: пресет уже существует (hub.tres)", ResourceLoader.exists(wizard._preset_path), wizard._preset_path)
	_check("хаб: кнопка сохранения включена", not wizard._save_btn.disabled, "")
	_check(
		"хаб: кнопка библиотеки ВЫКЛЮЧЕНА (не для общего пула)",
		wizard._add_to_library_btn.disabled,
		""
	)

	room.free()


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
