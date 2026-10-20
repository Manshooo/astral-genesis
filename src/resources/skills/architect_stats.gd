# res://src/resources/skills/architect_stats.gd
# Каталог статов МИРА (улучшения Архитектора): не на душе, а читаются через SkillProgression.stat у ArchitectManager — уровень карты нужен и без души.
class_name ArchitectStats
extends RefCounted

## Уровень экрана карты: 0 — экрана нет, 1 — посещённое на слое … 4 — содержимое комнат.
const MAP_LEVEL := &"map_level"
const MAP_LEVEL_MAX := 4

## Улучшения раскладки — сдвиги базы ручек генерации в снимке нового забега (ArchitectManager.apply_to_gen_config); база живёт в
## data/world_gen_config.tres. Тупиков снимается с базы; до нуля не доходит — в тупике тайник с эссенцией.
const DEAD_ENDS_CUT := &"dead_ends_cut"
## Сколько петель по коридору добавляется к базе.
const LOOPS_ADD := &"corridor_loops_add"
## Прибавка к RS_WorldGenConfig.transit_near_entry; 1 — все переходы на этаже прихода.
const TRANSIT_NEAR_ENTRY := &"transit_near_entry"

const ALL: Array[StringName] = [
	MAP_LEVEL,
	DEAD_ENDS_CUT,
	LOOPS_ADD,
	TRANSIT_NEAR_ENTRY,
]
