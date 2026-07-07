class_name RS_SkillRequirement
extends Resource

enum Type { SKILL_RANK, BRANCH_TOTAL_RANKS }

@export var type: Type = Type.SKILL_RANK
@export var target_skill: StringName = &""     ## для SKILL_RANK
@export var target_branch: StringName = &""    ## для BRANCH_TOTAL_RANKS
@export var min_value: int = 1                 ## мин. ранг / мин. суммарных очков в ветке
