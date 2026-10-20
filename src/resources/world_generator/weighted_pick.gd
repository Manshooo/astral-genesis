# res://src/resources/world_generator/weighted_pick.gd
# Взвешенный выбор по уже сделанному броску — общая арифметика подбора типа (RS_RoomTypeCatalog) и пресета (RS_RoomPresetLibrary).
# Бросок здесь НЕ делается: вызывающие тянут общий rng по-разному, и общий бросок поменял бы комплекс на прежних сидах. @tool — зовут редакторские инструменты.
@tool
class_name WeightedPick
extends RefCounted


## Сумма весов; отрицательные считаются нулём.
static func total(weights: Array[float]) -> float:
	var sum := 0.0
	for weight in weights:
		sum += maxf(weight, 0.0)
	return sum


## Индекс, на который попал roll из [0, 1], или -1, если все веса нулевые (решает вызывающий). Бросок ровно 0 попадает в первый.
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
