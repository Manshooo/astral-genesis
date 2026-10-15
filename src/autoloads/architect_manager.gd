# res://src/autoloads/architect_manager.gd
# Улучшения Архитектора: меняют не БФЖ, а мир — что игрок знает о комплексе и
# каким будет следующий забег. Прокачка та же, что у навыков (SkillProgression),
# отдельны только дерево, сейв и валюта — эссенция, которую даёт встреча с
# Архитектором (A_ArchitectEncounter). Тратить её можно и у него, и у инкубатора
# — экран навыков держит обе вкладки, — но добыть только у него, поэтому комната
# Архитектора гарантирована в каждом забеге.
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


## Кладёт улучшения раскладки в [param config] — снимок ручек НОВОГО забега
## (RunManager._run_gen_config). Правит переданный объект, поэтому зовущий обязан
## отдать копию базы: живой data/world_gen_config.tres от улучшений меняться не
## должен, иначе покупка поменяла бы и начатый забег (его снимок лежит в сейве),
## и всё, что читает базу.
##
## Границы держит сам: ручки в инспекторе ограничены export_range, а ресурс,
## собранный в коде, этих границ не знает. Тупиков остаётся хотя бы один, если
## база их давала — см. ArchitectStats.DEAD_ENDS_CUT.
func apply_to_gen_config(config: RS_WorldGenConfig) -> void:
	var cut := int(stat(ArchitectStats.DEAD_ENDS_CUT, 0.0))
	if config.dead_ends > 0:
		config.dead_ends = clampi(config.dead_ends - cut, 1, config.dead_ends)
	config.corridor_loops = clampi(config.corridor_loops + int(stat(ArchitectStats.LOOPS_ADD, 0.0)), 0, 4)
	config.transit_near_entry = clampf(stat(ArchitectStats.TRANSIT_NEAR_ENTRY, config.transit_near_entry), 0.0, 1.0)
