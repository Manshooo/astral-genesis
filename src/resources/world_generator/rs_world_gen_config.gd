## res://src/resources/world_generator/rs_world_gen_config.gd
## Ручки генерации комплекса — данными, а не константами RS_LevelGraph.
##
## Данными ради Архитектора: его улучшения меняют не персонажа, а мир (меньше
## тупиков, больше веток, гарантированная комната), то есть это модификаторы
## ИМЕННО этих ручек. Константа в коде такого не переживает — каждый бонус
## пришлось бы вшивать в генератор руками.
##
## Забег генерируется по СНИМКУ этого ресурса, который лежит в сейве
## (RS_WorldSave.gen_config), а не по живому data/world_gen_config.tres. Иначе
## улучшение, купленное посреди забега (хаб — часть комплекса), на ближайшей
## загрузке дало бы на том же сиде другой комплекс, и сохранённый узел
## оказался бы в чужой комнате или не нашёлся вовсе.
@tool  # читается генератором и в редакторской вкладке «Генератор мира»
class_name RS_WorldGenConfig
extends Resource

@export_group("Этажи")
## Комнат на этаже — вместе с уникальными, которые занимают обычные места.
@export_range(1, 12) var rooms_per_floor: int = 4
## Сколько этажей в слое (включительно).
@export_range(1, 5) var floor_count_min: int = 1
@export_range(1, 5) var floor_count_max: int = 3

@export_group("Коридоры")
## Сколько веток коридора на этаже (включительно). Ветка — узел графа; комнаты
## висят на ветках, ветки стыкуются друг с другом. Больше веток — больше мест,
## где этаж можно разделить шлюзом, и тем реже комнаты делят один коридор.
@export_range(1, 6) var corridor_branches_min: int = 1
@export_range(1, 6) var corridor_branches_max: int = 3
## Шаг решётки, по которой расставляются комнаты этажа, — в клетках кита (18 м).
## 3 = центры комнат через 54 м (близко к прежним 60), между соседями обычно два
## тайла коридора. Меньше трёх нельзя: при шаге 2 клетки перед дверями соседних
## комнат совпадают, и двери разных веток встретились бы в одном тайле.
@export_range(3, 6) var room_lattice_step: int = 3

@export_group("Вертикаль")
## Сколько вертикальных переходов между соседними слоями.
@export_range(1, 6) var layer_connectors: int = 3
## Шанс, что вертикальный переход заперт. Один переход на каждую пару слоёв
## открыт всегда — иначе забег можно сгенерировать непроходимым (ключей в игре
## пока нет, заперто = закрыто наглухо).
@export_range(0.0, 1.0) var layer_lock_chance: float = 0.35

@export_group("Уникальные комнаты")
## Порядок записей важен: розыгрыш идёт по нему, и перестановка меняет комплекс
## на том же сиде.
@export var unique_rooms: Array[RS_UniqueRoom] = []


## Расхождения, из-за которых генерация не сможет выполнить обещанное.
## Пустой список — всё сходится.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if floor_count_min > floor_count_max:
		problems.append("этажей: минимум %d больше максимума %d" % [floor_count_min, floor_count_max])
	if corridor_branches_min > corridor_branches_max:
		problems.append(
			"веток: минимум %d больше максимума %d" % [corridor_branches_min, corridor_branches_max]
		)
	var entries := 0
	for i in unique_rooms.size():
		var unique := unique_rooms[i]
		if unique == null or unique.preset == null or unique.preset.scene == null:
			problems.append("уникальная комната #%d без пресета или сцены" % i)
			continue
		if unique.depth_min > unique.depth_max:
			problems.append("уникальная комната «%s»: глубины перепутаны" % unique.preset.display_name)
		elif unique.allowed_depths().is_empty():
			problems.append("уникальная комната «%s»: все глубины вычеркнуты" % unique.preset.display_name)
		if unique.entry:
			entries += 1
			if unique.count != 1 or unique.chance < 1.0:
				problems.append("вход обязан быть ровно один и гарантированный")
	if entries != 1:
		problems.append("входов среди уникальных комнат %d, нужен ровно один" % entries)
	return problems
