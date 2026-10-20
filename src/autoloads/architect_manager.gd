# res://src/autoloads/architect_manager.gd
# Улучшения Архитектора: меняют мир, а не БФЖ. Прокачка та же, что у навыков
# (SkillProgression), своё только дерево, сейв и валюта.
# Вики: «Состояние проекта» (Архитектор), «Цикл забега» (Улучшения Архитектора в снимке).
extends SkillProgression

const SAVE_PATH := "user://architect.tres"
const DEFAULT_SAVE_PATH := "res://data/default_architect_save.tres"
const TREE_PATH := "res://data/architect_tree.tres"


func _init() -> void:
	super(SAVE_PATH, DEFAULT_SAVE_PATH, TREE_PATH)


## Уровень экрана карты; зажат сверху — экран не умеет рисовать лишнего.
func map_level() -> int:
	return clampi(int(stat(ArchitectStats.MAP_LEVEL, 0.0)), 0, ArchitectStats.MAP_LEVEL_MAX)


## Кладёт улучшения в [param config] — снимок ручек нового забега. Правит объект
## на месте: звать с копией базы, не с живым .tres. Границы держит сам —
## export_range для ресурса из кода не действует.
func apply_to_gen_config(config: RS_WorldGenConfig) -> void:
	var cut := int(stat(ArchitectStats.DEAD_ENDS_CUT, 0.0))
	if config.dead_ends > 0:
		config.dead_ends = clampi(config.dead_ends - cut, 1, config.dead_ends)
	config.corridor_loops = clampi(config.corridor_loops + int(stat(ArchitectStats.LOOPS_ADD, 0.0)), 0, 4)
	config.transit_near_entry = clampf(stat(ArchitectStats.TRANSIT_NEAR_ENTRY, config.transit_near_entry), 0.0, 1.0)
