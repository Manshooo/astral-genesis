# res://src/autoloads/architect_manager.gd
# Улучшения Архитектора: меняют не БФЖ, а мир — что игрок знает о комплексе и
# каким будет следующий забег. Прокачка та же, что у навыков (SkillProgression),
# отдельны только дерево, сейв и валюта — эссенция, которую даёт встреча с
# Архитектором (A_ArchitectEncounter). Тратится она у него же: другого места
# нет, поэтому комната Архитектора гарантирована в каждом забеге.
extends SkillProgression

const SAVE_PATH := "user://architect.tres"
const DEFAULT_SAVE_PATH := "res://data/default_architect_save.tres"
const TREE_PATH := "res://data/architect_tree.tres"


func _init() -> void:
	super(SAVE_PATH, DEFAULT_SAVE_PATH, TREE_PATH)


## Уровень экрана карты, до которого дошли улучшения. Зажат сверху: лишний ранг в
## данных не должен открыть уровень, которого экран не умеет рисовать.
func map_level() -> int:
	return clampi(int(stat(ArchitectStats.MAP_LEVEL, 0.0)), 0, ArchitectStats.MAP_LEVEL_MAX)
