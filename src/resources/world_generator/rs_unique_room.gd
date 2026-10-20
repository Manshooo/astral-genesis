## res://src/resources/world_generator/rs_unique_room.gd
## Комната, которую генератор РАЗМЕЩАЕТ, а не подбирает (хаб, выход, Архитектор): узел резервируется под известную сцену, рёбер — сколько в ней дверей.
## «Тупик» хаба получается сам, новая уникальная комната — строка данных, а не якорь в коде.
@tool  # читается генератором и в редакторской вкладке «Генератор мира»
class_name RS_UniqueRoom
extends Resource

## Что ставится: сцена, тип и число дверей — отсюда же.
@export var preset: RS_RoomPreset

@export_group("Где")
## Диапазон глубин, из которого разыгрывается слой (включительно); для хаба и выхода одна глубина.
@export var depth_min: int = 0
@export var depth_max: int = 0
## Глубины внутри отрезка, на которые комната не встаёт (дырка бывает посередине).
@export var excluded_depths: Array[int] = []
## Не ставить на этаж входа: Архитектор на слое хаба, но не рядом со стартом. Слою добавляется второй этаж; запись обязана идти в списке после входа.
@export var apart_from_entry: bool = false
## Сколько таких комнат в забеге.
@export_range(1, 8) var count: int = 1
## Шанс, что комната окажется в забеге; бросок тратит rng ВСЕГДА, иначе не выпавшая сдвигала бы всё после.
@export_range(0.0, 1.0) var chance: float = 1.0

@export_group("Роль в забеге")
## Отсюда игрок начинает забег (entry_node_id); ровно одна запись.
@export var entry: bool = false
## Отсюда игрок сбегает (exit_node_ids, тег level_exit).
@export var exit: bool = false
## Двери не открываются, а ПЕРЕСТАВЛЯЮТ игрока перед ними — когда за дверью в арте нет проёма (был нужен хабу 18 м).
@export var door_teleports: bool = false

@export_group("Карта")
## Название на карте (ключ перевода): роль в забеге («Выход»), не имя сцены; первые буквы разных комнат не должны совпадать (заглушка значка). Пусто — display_name.
@export var map_name: String = ""
## Значок на карте; пусто — заглушка из первой буквы map_name.
@export var map_icon: Texture2D


## Имя для карты: map_name, иначе имя пресета; ключ и готовая строка проходят через tr().
func map_label() -> String:
	if map_name != "":
		return map_name
	return preset.display_name if preset else ""


func covers_depth(depth: int) -> bool:
	return depth >= depth_min and depth <= depth_max and not excluded_depths.has(depth)


## Глубины, из которых разыгрывается слой, по возрастанию; пусто — отрезок вычеркнут (ловит RS_WorldGenConfig.validate).
func allowed_depths() -> Array[int]:
	var result: Array[int] = []
	for depth in range(depth_min, depth_max + 1):
		if not excluded_depths.has(depth):
			result.append(depth)
	return result
