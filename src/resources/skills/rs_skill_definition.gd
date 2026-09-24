class_name RS_SkillDefinition
extends Resource
## Один навык дерева: чем он является для игрока, чего стоит и что меняет.
##
## Место навыка в графе здесь НЕ задаётся — колонку и дорожку выводит
## SkillGraphLayout из ветки и требований. Иначе добавление навыка стоило бы
## ещё и ручной расстановки координат, а первая же вставка в середину цепочки
## заставила бы двигать всё, что правее.

@export var id: StringName = &""            # "body_snatch", "lifespan"
@export var display_name: String = ""
@export var description: String = ""
@export var branch: StringName = &"default"  ## "possession", "survival" — дорожка в графе
@export var max_rank: int = 3
@export var cost_per_rank: Array[int] = [1, 2, 3]   ## очков навыка за каждый ранг
@export var requires: Array[RS_SkillRequirement] = []

## Что скилл делает с механикой. Здесь, а не кодом в O_ApplySkillEffects: скилл,
## который крутит уже существующее число, должен стоить строчки в .tres.
## Величины задаются на ОДИН ранг — умножение на ранг делает свёртка.
@export var modifiers: Array[RS_StatModifier] = []

## Ручная строка внутри своей дорожки и колонки; -1 — «расставь сам».
## Аварийный выход для случая, когда автораскладка развела соседей не так, как
## читается ветка. Оставлять -1 всюду, где не мешает: закреплённая строка не
## подвинется, когда рядом появится новый навык.
@export var graph_row: int = -1


## Сколько стоит следующий ранг. -1 если уже максимум.
##
## max_rank и cost_per_rank — два независимых поля инспектора, и поднять первое,
## не дописав второе, легко. Раньше это роняло покупку выходом за границы
## массива в момент клика; теперь ранг без цены просто не продаётся, а
## RS_SkillTree.validate() называет навык заранее.
func cost_for_next_rank(current_rank: int) -> int:
	if current_rank >= max_rank:
		return -1
	if current_rank >= cost_per_rank.size():
		push_error(
			"RS_SkillDefinition '%s': max_rank=%d, а цен в cost_per_rank %d — ранг %d не продаётся"
			% [id, max_rank, cost_per_rank.size(), current_rank + 1]
		)
		return -1
	return cost_per_rank[current_rank]
