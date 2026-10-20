class_name RS_SkillDefinition
extends Resource
## Один навык дерева: что это для игрока, цена, что меняет. Место в графе не задаётся — выводит SkillGraphLayout из ветки и требований.

@export var id: StringName = &""            # "body_snatch", "lifespan"
@export var display_name: String = ""
@export var description: String = ""
@export var branch: StringName = &"default"  ## "possession", "survival" — сектор в графе
@export var max_rank: int = 3
@export var cost_per_rank: Array[int] = [1, 2, 3]   ## очков навыка за каждый ранг
@export var requires: Array[RS_SkillRequirement] = []

## Что навык делает с механикой: строчка в .tres, не код в O_ApplySkillEffects. Величины на ОДИН ранг — умножает свёртка.
@export var modifiers: Array[RS_StatModifier] = []

## На сколько выполненное условие усиливает значение ЭТОГО ранга (0.2 → 12 → 14.4); один на навык.
@export_range(0.0, 1.0, 0.01) var condition_bonus: float = 0.0
## Условие каждого ранга: [0] — для ранга 1. Короче max_rank или null — условия нет; прогресс только по условию ТЕКУЩЕГО ранга.
@export var rank_conditions: Array[RS_SkillCondition] = []

## Способность тела, без которой навык ничего не меняет (&"walk", &"jump", &"sprint"); пусто — не привязан. Нужна, чтобы карточка сказала об этом игроку.
@export var ability: StringName = &""

## Ручной слот по дуге кольца в секторе ветки (0 — крайний против часовой); -1 — раскладка сама. Закреплённая строка не подвинется.
@export var graph_row: int = -1


## Цена следующего ранга; -1 если максимум. Ранг без цены не продаётся, RS_SkillTree.validate() называет навык заранее.
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


## Условие ранга rank (1-based) или null.
func condition_for_rank(rank: int) -> RS_SkillCondition:
	if rank < 1 or rank > rank_conditions.size():
		return null
	return rank_conditions[rank - 1]


## Бонус выполненного условия — только если условие у ранга есть.
func bonus_for_rank(rank: int) -> float:
	return condition_bonus if condition_for_rank(rank) != null else 0.0


## Компонент способности навыка или null. Через match: ссылки на классы в const-словаре резолвятся на компиляции.
func ability_component() -> Script:
	match ability:
		&"walk":
			return C_Walk
		&"jump":
			return C_Jump
		&"sprint":
			return C_Sprint
	return null
