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

const ALL: Array[StringName] = [
	MAP_LEVEL,
]
