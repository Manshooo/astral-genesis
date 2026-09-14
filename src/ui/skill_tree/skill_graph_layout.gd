# res://src/ui/skill_tree/skill_graph_layout.gd
## Раскладка дерева навыков по клеткам: где чья карточка стоит в графе.
##
## Считается ОДИН раз по всему дереву — не по видимой его части. В этом весь
## смысл: карточка навыка стоит на своём месте всегда, и открытие соседа не
## перетасовывает граф под курсором. Появление узла игрок читает как появление,
## а не как «всё поехало».
##
## Координаты выводятся из данных, а не задаются в них: колонка — глубина по
## требованиям, дорожка — ветка. Автору навыка остаётся объявить требования,
## то есть ровно то, что он и так обязан объявить, чтобы навык открывался.
##
## Единица — КЛЕТКА, не пиксель: сколько клетка занимает на экране, знает
## UI_SkillGraph, и раскладку можно проверить headless, не создавая ни одного
## Control.
class_name SkillGraphLayout
extends RefCounted

## Пустая строка между дорожками, чтобы ветки читались как ветки.
const LANE_GAP := 1

## StringName (id навыка) -> Vector2i(колонка, строка)
var cells: Dictionary = {}
## [{ "branch": StringName, "row": int, "height": int }] — дорожки сверху вниз.
var lanes: Array[Dictionary] = []
var columns: int = 0
var rows: int = 0


static func build(tree: RS_SkillTree) -> SkillGraphLayout:
	var layout := SkillGraphLayout.new()
	if tree == null:
		return layout

	var tiers := _compute_columns(tree)
	var row_cursor := 0

	for branch_id in tree.ordered_branch_ids():
		var branch_skills := tree.get_branch_skills(branch_id)
		if branch_skills.is_empty():
			continue

		var by_column: Dictionary = {}  # int -> Array[RS_SkillDefinition]
		for def in branch_skills:
			var column := int(tiers.get(def.id, 0))
			if not by_column.has(column):
				by_column[column] = []
			by_column[column].append(def)
			layout.columns = maxi(layout.columns, column + 1)

		var height := 0
		for column in by_column:
			var assigned := _assign_rows(by_column[column])
			for id in assigned:
				var row: int = assigned[id]
				layout.cells[id] = Vector2i(column, row_cursor + row)
				height = maxi(height, row + 1)

		layout.lanes.append({"branch": branch_id, "row": row_cursor, "height": height})
		row_cursor += height + LANE_GAP

	layout.rows = maxi(0, row_cursor - LANE_GAP)
	return layout


## Колонка = длина самой длинной цепочки требований до навыка.
##
## Считается итеративной релаксацией, а не обходом в глубину: требование
## BRANCH_TOTAL_RANKS ссылается на ветку целиком, в том числе на ту, в которой
## навык сам и лежит, — рекурсия на таком требовании ушла бы в цикл. Проходов не
## больше числа навыков: длиннее простой цепочки требований быть не может, а на
## циклической ссылке в данных счётчик просто упрётся в потолок вместо зависания.
static func _compute_columns(tree: RS_SkillTree) -> Dictionary:
	var tiers: Dictionary = {}
	for def in tree.skills:
		if def != null:
			tiers[def.id] = 0

	for _pass in maxi(1, tree.skills.size()):
		var changed := false
		for def in tree.skills:
			if def == null:
				continue
			var tier := 0
			for req in def.requires:
				if req == null:
					continue
				match req.type:
					RS_SkillRequirement.Type.SKILL_RANK:
						if tiers.has(req.target_skill):
							tier = maxi(tier, int(tiers[req.target_skill]) + 1)
					RS_SkillRequirement.Type.BRANCH_TOTAL_RANKS:
						for other in tree.get_branch_skills(req.target_branch):
							if other == null or other.id == def.id:
								continue
							tier = maxi(tier, int(tiers.get(other.id, 0)) + 1)
			if tier != int(tiers[def.id]):
				tiers[def.id] = tier
				changed = true
		if not changed:
			break

	return tiers


## Строки внутри одной клетки-колонки одной дорожки.
##
## Сначала расставляются закреплённые (graph_row), потом остальные занимают
## свободные строки сверху вниз. Закрепление на уже занятую строку не
## выигрывает спор, а откатывается к автоматическому: два навыка в одной строке
## нарисовались бы друг на друге, и это была бы худшая из реакций на опечатку.
static func _assign_rows(defs: Array) -> Dictionary:
	var taken: Dictionary = {}
	var assigned: Dictionary = {}

	for entry in defs:
		var def := entry as RS_SkillDefinition
		if def.graph_row >= 0 and not taken.has(def.graph_row):
			taken[def.graph_row] = true
			assigned[def.id] = def.graph_row

	var next_row := 0
	for entry in defs:
		var def := entry as RS_SkillDefinition
		if assigned.has(def.id):
			continue
		while taken.has(next_row):
			next_row += 1
		taken[next_row] = true
		assigned[def.id] = next_row

	return assigned
