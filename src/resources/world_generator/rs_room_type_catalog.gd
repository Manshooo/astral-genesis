## res://src/resources/world_generator/rs_room_type_catalog.gd
## Каталог типов помещений (data/room_type_catalog.tres): что встречается и на какой глубине. Лежит в библиотеке пресетов (type_catalog), не отдельным
## аргументом generate_run — у него пять вызывающих. Вики: [[Цикл забега]] (Две оси подбора комнаты).
@tool
class_name RS_RoomTypeCatalog
extends Resource

## Порядок важен для ДЕТЕРМИНИЗМА: розыгрыш идёт по массиву, перестановка строк меняет то, что выпадет на том же сиде.
@export var types: Array[RS_RoomType] = []

## Вес исхода «нет типа» — безликое помещение, их большинство; в том же броске, что и типы.
@export var untyped_weight: float = 4.0


## Разыгрывает тип для узла глубины depth; `&""` — «без типа» или глубину не покрывает ни один. Бросок ВСЕГДА, даже без подходящих: rng общий на генерацию.
func pick_for_depth(depth: int, rng: RandomNumberGenerator) -> StringName:
	var eligible: Array[RS_RoomType] = []
	# Нулевой элемент — «без типа»: соревнуется с типами наравне.
	var weights: Array[float] = [untyped_weight]
	for type: RS_RoomType in types:
		if type == null or type.weight <= 0.0 or not type.covers_depth(depth):
			continue
		eligible.append(type)
		weights.append(type.weight)

	var picked := WeightedPick.index(weights, rng.randf())
	return eligible[picked - 1].id if picked > 0 else &""


func by_id(id: StringName) -> RS_RoomType:
	for type: RS_RoomType in types:
		if type != null and type.id == id:
			return type
	return null


## Ключи всех типов в порядке объявления — для списков инструментов и проверок.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for type: RS_RoomType in types:
		if type != null and type.id != &"":
			out.append(type.id)
	return out


## Имя типа для инструментов; неизвестный ключ — как есть (тип убрали из каталога).
func label_of(id: StringName) -> String:
	if id == &"":
		return "—"
	var type := by_id(id)
	return type.label() if type else String(id)


## Описание типа или "" (как RS_RoomTagCatalog.description_of).
func description_of(id: StringName) -> String:
	var type := by_id(id)
	return type.description if type else ""


## Расхождения каталога — для проверок и инструментов.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen := {}
	for i in types.size():
		var type := types[i]
		if type == null:
			problems.append("null-тип в позиции %d" % i)
			continue
		if type.id == &"":
			problems.append("тип в позиции %d без id" % i)
			continue
		if seen.has(type.id):
			problems.append("id «%s» повторяется" % type.id)
		seen[type.id] = true
		if type.depth_min > type.depth_max:
			problems.append(
				"«%s»: depth_min=%d больше depth_max=%d — тип не выпадет никогда"
				% [type.id, type.depth_min, type.depth_max]
			)
		if type.map_name == "":
			problems.append("«%s»: нет map_name — карта покажет игроку непереведённое имя" % type.id)
	return problems
