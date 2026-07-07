class_name RS_SkillDefinition
extends Resource

@export var id: StringName = &""            # "body_snatch", "lifespan"
@export var display_name: String = ""
@export var description: String = ""
@export var branch: StringName = &"default"  ## "possession", "survival" — для отрисовки веток дерева
@export var max_rank: int = 3
@export var cost_per_rank: Array[int] = [1, 2, 3]   ## очков навыка за каждый ранг
@export var requires: Array[RS_SkillRequirement] = []

## Сколько стоит следующий ранг. -1 если уже максимум.
func cost_for_next_rank(current_rank: int) -> int:
	if current_rank >= max_rank:
		return -1
	return cost_per_rank[current_rank]
