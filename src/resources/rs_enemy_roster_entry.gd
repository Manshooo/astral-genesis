## Одна строка ростера врагов: кто может встать на маркер спавна, с каким весом
## и на каких глубинах. Отдельным ресурсом, а не параллельными массивами в
## ростере: «сцена, вес и диапазон слоёв» правятся в инспекторе одной карточкой,
## а три массива одинаковой длины разъезжаются при первой же вставке.
class_name RS_EnemyRosterEntry
extends Resource

## Сцена врага (E_Enemy). Труп и класс угрозы берутся из неё самой —
## E_Enemy.corpse_scene, — здесь их не дублируем.
@export var enemy_scene: PackedScene

## Вес в розыгрыше среди строк, подходящих слою. 0 — строка выключена.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0

## Слои, где строка действует, включительно (глубина графа: 0 — поверхность,
## 5 — дно). Диапазон, а не список: «L0–L1 учёные» — одна строка, а не две.
@export_range(0, 5) var depth_min: int = 0
@export_range(0, 5) var depth_max: int = 5


func covers(depth: int) -> bool:
	return enemy_scene != null and weight > 0.0 and depth >= depth_min and depth <= depth_max
