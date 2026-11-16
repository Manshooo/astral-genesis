class_name C_Look
extends C_BodyTrait
## Варианты облика тела (шесть обликов и двое очков учёного): материал на всю геометрию облика и один видимый меш из
## группы. Какой — разыгрывается по сиду места (RS_EntityVisuals.roll_look), и номера едут на душу при захвате и в сейв.
## Вики: [[Захват тела]].

## Материалы облика; каждый ставится на всю геометрию узла Visual. Пусто — материал сцены.
@export var materials: Array[Material] = []

## Имена мешей облика, из которых виден ровно один (варианты очков). Пусто — меши как в сцене.
@export var alternatives: PackedStringArray = PackedStringArray()

## Разыгранные номера в materials и alternatives; −1 — ещё не разыгрывали, облик как в сцене. Хранятся (а не
## вычисляются по месту), потому что место тела теряется при захвате, а облик — нет.
@export_storage var material_index: int = -1
@export_storage var alternative_index: int = -1


## Разыгран ли облик.
func is_rolled() -> bool:
	return material_index >= 0 or alternative_index >= 0
