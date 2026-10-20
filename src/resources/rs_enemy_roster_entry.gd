## Строка ростера: враг, вес и диапазон глубин. Отдельный ресурс — параллельные массивы разъехались бы.
class_name RS_EnemyRosterEntry
extends Resource

## Сцена врага (E_Enemy); труп и класс угрозы — из неё самой.
@export var enemy_scene: PackedScene

## Вес среди строк слоя; 0 — выключена.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0

## Слои действия, включительно (0 — поверхность, 5 — дно).
@export_range(0, 5) var depth_min: int = 0
@export_range(0, 5) var depth_max: int = 5


func covers(depth: int) -> bool:
	return enemy_scene != null and weight > 0.0 and depth >= depth_min and depth <= depth_max
