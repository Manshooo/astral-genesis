# res://src/autoloads/skill_manager.gd
# Дерево навыков самого БФЖ: захват, распад, тело. Вся машинерия прокачки — в
# SkillProgression; здесь только то, какое это дерево и где лежит его сейв.
extends SkillProgression

const SAVE_PATH := "user://skills.tres"
const DEFAULT_SAVE_PATH := "res://data/default_skill_save.tres"
const SKILL_TREE_PATH := "res://data/skill_tree.tres"


func _init() -> void:
	super(SAVE_PATH, DEFAULT_SAVE_PATH, SKILL_TREE_PATH)
