extends Node
## Проверка СЛОВАРЯ структурных тегов (`RS_RoomTagCatalog`,
## `data/room_tag_catalog.tres`).
## Запуск: godot --headless dev/room_tags_check.tscn
##
## Словарь — единственное место, где записано, что тег значит, и единственное,
## по чему настоящий тег отличается от опечатки: `verticalhub` в облаке
## выглядит ровно так же полноценно, как `vertical_hub`, и без словаря их не
## различить ни глазом, ни кодом. Поэтому расхождения словаря и реальности
## ловятся здесь, а не «когда-нибудь заметим»:
##   1. тег стоит у пресетов, но описания нет — либо забыли описать, либо это
##      и есть опечатка;
##   2. тег в словаре помечен set_by_generator, а генератор его никому не
##      ставит (или наоборот) — флаг запрещает переименование в инструменте, и
##      соврав в любую сторону, он либо блокирует безопасную правку, либо
##      разрешает ту, что молча сломает подбор.
##
## Проверка НЕ требует, чтобы каждый тег словаря кто-то носил: тег заводят
## заранее, под ещё не нарисованную комнату, и это нормальное состояние.

const SEED_COUNT := 12

var _ok := 0
var _fail := 0


func _ready() -> void:
	_run()

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	var library := GameConfig.config.room_preset_library as RS_RoomPresetLibrary
	if library == null:
		_check("библиотека пресетов назначена в game_config", false, "room_preset_library == null")
		return

	var catalog := library.tag_catalog
	_check("облако тегов назначен библиотеке", catalog != null, "tag_catalog == null")
	if catalog == null:
		return

	var problems := catalog.validate()
	_check("словарь без расхождений", problems.is_empty(), "; ".join(problems))
	_check("в словаре есть теги", not catalog.tags.is_empty(), "tags пуст")

	_check_presets(library, catalog)
	_check_generator_tags(library, catalog)


# ---------------------------------------------------------------------------
# 1. Теги пресетов
# ---------------------------------------------------------------------------


func _check_presets(library: RS_RoomPresetLibrary, catalog: RS_RoomTagCatalog) -> void:
	var presets := library.presets + ([library.fallback] if library.fallback else [])
	var used := {}
	for preset: RS_RoomPreset in presets:
		if preset == null:
			continue
		for tag: StringName in preset.tags:
			used[tag] = true

	for tag: StringName in used:
		_check(
			"тег «%s» есть в словаре" % tag,
			catalog.has_id(tag),
			"тег стоит у пресетов, но не описан — описка или забытое описание",
		)
		# Пустое описание требуем только у тегов, которые уже кто-то носит:
		# заведённый впрок тег без описания — нормальная незавершённая работа,
		# а вот носимый молча теряет весь смысл словаря.
		var entry := catalog.by_id(tag)
		if entry:
			_check(
				"у тега «%s» заполнено описание" % tag,
				entry.description.strip_edges() != "",
				"тег стоит у пресетов, но что он значит — не записано",
			)


# ---------------------------------------------------------------------------
# 2. Теги, которые расставляет сам генератор
# ---------------------------------------------------------------------------


## Узлам теги проставляет RS_LevelGraph по захардкоженным ключам. Флаг
## set_by_generator в словаре — единственное, что об этом знает инструмент, и
## он обязан совпадать с реальностью в ОБЕ стороны.
func _check_generator_tags(library: RS_RoomPresetLibrary, catalog: RS_RoomTagCatalog) -> void:
	var seen := {}
	for s in SEED_COUNT:
		var graph := RS_LevelGraph.new().generate_run(s, library)
		for node: RS_LevelNode in graph.nodes.values():
			for tag: StringName in node.tags:
				seen[tag] = true

	_check("генератор вообще проставляет теги узлам", not seen.is_empty(), "ни одного тега за %d сидов" % SEED_COUNT)

	for tag: StringName in seen:
		var entry := catalog.by_id(tag)
		_check("тег генератора «%s» есть в словаре" % tag, entry != null, "узлы его получают, а словарь о нём не знает")
		if entry:
			_check(
				"тег «%s» помечен set_by_generator" % tag,
				entry.set_by_generator,
				"инструмент разрешит переименовать его, а ключ захардкожен в RS_LevelGraph",
			)

	for entry: RS_RoomTag in catalog.tags:
		if entry == null or not entry.set_by_generator:
			continue
		_check(
			"помеченный set_by_generator тег «%s» генератор действительно ставит" % entry.id,
			seen.has(entry.id),
			"флаг устарел: за %d сидов такой тег не выпал ни одному узлу" % SEED_COUNT,
		)


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
