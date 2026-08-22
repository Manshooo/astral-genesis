class_name RS_StatModifier
extends Resource
## Одна прибавка к одному стату — объявленная ДАННЫМИ, а не кодом.
##
## Ради этого ресурса всё и затевалось: добавить скилл, крутящий уже
## существующую механику, должно стоить строчки в .tres, а не новой ветки в
## наблюдателе. Поле stat рисуется выпадающим списком из C_StatModifiers.ALL —
## опечатка в имени стата не доживает до рантайма.
##
## Числа задаются НА ОДИН РАНГ и умножаются на ранг при свёртке: скилл на три
## ранга описывается одним модификатором, а не тремя.

enum Op {
	FLAT,  ## Плоская прибавка к базе: +0.5 м к дальности захвата
	MULT,  ## Множитель, заданный долей: 0.1 = +10%
}

@export var stat: StringName = &""
@export var op: Op = Op.FLAT
## Величина НА ОДИН РАНГ. Для MULT это доля: 0.1 на ранге 3 даёт ×1.3.
@export var per_rank: float = 0.0


## Вклад в свёртку на данном ранге. Линейно по рангу, а не степенно: ранг 3
## должен читаться как «втрое сильнее ранга 1», иначе описание скилла в UI
## придётся считать калькулятором.
func contribution(rank: int) -> float:
	if op == Op.MULT:
		return 1.0 + per_rank * rank
	return per_rank * rank


## Накопить набор модификаторов, взятых на ранге rank, в словари свёртки.
## Статическая, потому что накапливают её ВСЕ источники модификаторов (дерево
## перков, награды забега, временные эффекты) — правило свёртки должно быть
## одно, иначе источники разойдутся в трактовке flat/mult.
static func fold(modifiers: Array, rank: int, flat: Dictionary, mult: Dictionary) -> void:
	for entry in modifiers:
		var mod := entry as RS_StatModifier
		if mod == null or mod.stat.is_empty():
			continue
		if mod.op == Op.MULT:
			mult[mod.stat] = mult.get(mod.stat, 1.0) * mod.contribution(rank)
		else:
			flat[mod.stat] = flat.get(mod.stat, 0.0) + mod.contribution(rank)


func _validate_property(property: Dictionary) -> void:
	if property.name != "stat":
		return
	var names := PackedStringArray()
	for id in C_StatModifiers.ALL:
		names.append(String(id))
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = ",".join(names)
