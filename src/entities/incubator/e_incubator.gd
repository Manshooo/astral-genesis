@tool
class_name E_Incubator
extends Entity

func define_components() -> Array:
	return [C_Interactable.new()]

func open_skill_menu() -> void:
	UIManager.open_skill_tree(SkillManager, preload("res://data/skill_tree.tres"))
