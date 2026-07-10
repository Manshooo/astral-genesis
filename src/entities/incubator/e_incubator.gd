# src/entities/incubator/e_incubator.gd
@tool
class_name E_Incubator
extends Entity

func interact() -> void:
	UIManager.open_skill_tree(SkillManager, preload("res://data/skill_tree.tres"))
