class_name PlayerSkillSave
extends Resource

## id навыка -> текущий ранг
@export var ranks: Dictionary = {}
@export var skill_points: int = 0
## Игрок уже встречал того, кто даёт это дерево (читается у Архитектора: до встречи вкладки нет).
@export var met: bool = false

## Прогресс условий: "<id навыка>:<ранг>" -> метры или штуки. Копится МЕЖДУ забегами; новые поля обратно совместимы.
@export var condition_progress: Dictionary = {}
## Для CAPTURE_KINDS: виды тел, уже зачтённые условию; прогресс — размер списка (отдельный счётчик разошёлся бы).
@export var condition_seen: Dictionary = {}
