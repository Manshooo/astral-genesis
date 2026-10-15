# res://src/resources/skills/architect_stats.gd
# Каталог статов МИРА — того, что меняют улучшения Архитектора. Отдельно от
# C_StatModifiers.ALL, потому что те статы лежат на душе и читаются через её
# компонент, а эти — нет: уровень карты нужен и тогда, когда души ещё нет
# (экран карты на паузе, генерация следующего забега). Читаются они через
# SkillProgression.stat у ArchitectManager.
class_name ArchitectStats
extends RefCounted

## Уровень экрана карты: 0 — экрана нет, дальше по таблице из карточки «Экран
## карты комплекса» (1 — посещённое на слое, … 4 — содержимое комнат).
const MAP_LEVEL := &"map_level"
const MAP_LEVEL_MAX := 4

## Улучшения раскладки — ручки генерации (RS_WorldGenConfig), которые Архитектор
## сдвигает в снимке нового забега (ArchitectManager.apply_to_gen_config). Величина
## стата — сдвиг базы, а не готовое значение ручки: база живёт в
## data/world_gen_config.tres, и правка её не должна ломать данные дерева.
##
## Сколько тупиков на этаже снимается с базы. До нуля не доходит: в тупике
## лежит тайник с эссенцией (карточка «Источники эссенции»), и этаж без него
## отнял бы у игрока второй источник.
const DEAD_ENDS_CUT := &"dead_ends_cut"
## Сколько петель по коридору добавляется к базе: обходов больше, путь короче.
const LOOPS_ADD := &"corridor_loops_add"
## Сила предпочтения «переходы ближе ко входу»: прибавка к
## RS_WorldGenConfig.transit_near_entry, 1 — все переходы на этаже прихода.
const TRANSIT_NEAR_ENTRY := &"transit_near_entry"

const ALL: Array[StringName] = [
	MAP_LEVEL,
	DEAD_ENDS_CUT,
	LOOPS_ADD,
	TRANSIT_NEAR_ENTRY,
]
