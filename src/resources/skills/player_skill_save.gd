class_name PlayerSkillSave
extends Resource

## StringName (id навыка) -> int (текущий ранг)
@export var ranks: Dictionary = {}
@export var skill_points: int = 0
## Игрок уже встречал того, кто даёт это дерево. Читается только у Архитектора:
## до первой встречи его вкладки на экране навыков нет — игрок ещё не знает,
## что такое эссенция (решение 02.10, «UI — переверстка меню»).
@export var met: bool = false
