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
func cost_for_next_rank(current_rank: int) -> int:
	if current_rank >= max_rank:
		return -1
	return cost_per_rank[current_rank]
