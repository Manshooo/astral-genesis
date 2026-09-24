# res://src/resources/world_generator/weighted_pick.gd
# Взвешенный выбор по уже сделанному броску — общая арифметика подбора типа
# помещения (RS_RoomTypeCatalog) и пресета (RS_RoomPresetLibrary).
#
# Бросок здесь НЕ делается намеренно: как и сколько раз тянуть общий rng
# генерации, решает вызывающий, и решает по-разному — каталог бросает всегда,
# даже без кандидатов (иначе сдвинулось бы всё, что разыгрывается после),
# библиотека при нулевых весах тянет randi_range вместо randf. Общая копия
# броска поменяла бы поток rng, а с ним и комплекс на прежних сидах. Общим
# сделано ровно то, что было продублировано: накопление весов и поиск по нему.
# @tool — функции зовут @tool-ресурсы прямо из редакторских инструментов.
@tool
class_name WeightedPick
extends RefCounted


## Сумма весов; отрицательные считаются нулём — вес «меньше нуля» не отнимает
## шансы у соседей.
static func total(weights: Array[float]) -> float:
	var sum := 0.0
	for weight in weights:
		sum += maxf(weight, 0.0)
	return sum


## Индекс, на который попал [param roll] из [0, 1], или -1, если все веса
## нулевые — что тогда делать, решает вызывающий. Нулевой вес не исключает
## элемент целиком: бросок ровно 0 попадает в первый, как и до выноса.
static func index(weights: Array[float], roll: float) -> int:
	var sum := total(weights)
	if sum <= 0.0:
		return -1
	var target := roll * sum
	var acc := 0.0
	for i in weights.size():
		acc += maxf(weights[i], 0.0)
		if target <= acc:
			return i
	return weights.size() - 1
