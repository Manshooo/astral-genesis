class_name RS_StatModifier
extends Resource
## Одна прибавка к одному стату — объявленная ДАННЫМИ, а не кодом.
##
## Ради этого ресурса всё и затевалось: добавить скилл, крутящий уже
## существующую механику, должно стоить строчки в .tres, а не новой ветки в
## наблюдателе. Поле stat рисуется выпадающим списком из C_StatModifiers.ALL —
## опечатка в имени стата не доживает до рантайма.
##
## Числа задаются либо НА ОДИН РАНГ (линейно, умножаются на ранг при свёртке),
## либо списком значений по рангам (values) — скилл на три ранга описывается
## одним модификатором, а не тремя.

enum Op {
	FLAT,  ## Плоская прибавка к базе: +0.5 м к дальности захвата
	MULT,  ## Множитель, заданный долей: 0.1 = +10%
}

@export var stat: StringName = &""
@export var op: Op = Op.FLAT
## Величина НА ОДИН РАНГ. Для MULT это доля: 0.1 на ранге 3 даёт ×1.3.
## Не читается, если задан [member values].
@export var per_rank: float = 0.0
## Значение НА КАЖДЫЙ РАНГ (карточка «Игровой цикл — от и до» §4.1): values[0] —
## итог ранга 1, values[1] — ранга 2, и так далее; это итоговое значение ранга, а
## не добавка к предыдущему. Пример «Скорость»: 0.10 / 0.12 / 0.15 — на ранге 3
## даёт +15 %, а не +37 %. Пусто — навык старого вида, линейный [member per_rank].
## Рангов больше, чем значений, читают последнее значение: недописанная строка в
## данных не должна ронять свёртку, а валидатор дерева её называет.
@export var values: Array[float] = []
## Показывать значение процентами и у FLAT-стата (шанс захвата 0.1 → «+10%»).
## У MULT проценты всегда: доля без процентов игроку ничего не говорит.
@export var display_percent: bool = false


## Значение ранга БЕЗ бонуса условия: то, что навык обещает на этом ранге.
## Нулевой ранг ничего не даёт — ни доли, ни прибавки.
func value_at(rank: int) -> float:
	if rank <= 0:
		return 0.0
	if values.is_empty():
		return per_rank * rank
	return values[mini(rank, values.size()) - 1]


## Вклад в свёртку на данном ранге. [param bonus] — доля, на которую выполненное
## условие ранга усиливает ЗНАЧЕНИЕ ЭТОГО РАНГА (0.2 → ×1.2). Множителем на
## значение, а не на итог и не на каждый ранг подряд: бонус не копится от ранга
## к рангу, экспоненциального роста нет (решение 15.10).
## Линейно по рангу у старых навыков, а не степенно: ранг 3 должен читаться как
## «втрое сильнее ранга 1», иначе описание скилла в UI придётся считать
## калькулятором.
func contribution(rank: int, bonus: float = 0.0) -> float:
	var value := value_at(rank) * (1.0 + bonus)
	if op == Op.MULT:
		return 1.0 + value
	return value


## Значение ранга строкой для карточки: «+12%», «+0.3». Десятичный знак — точка,
## как в остальных числах игры; лишние нули убираются, чтобы «+10%» не писалось
## «+10.0%».
func format_value(value: float) -> String:
	var as_percent := op == Op.MULT or display_percent
	var text := _trimmed(value * 100.0 if as_percent else value)
	if not text.begins_with("-"):
		text = "+" + text
	return text + "%" if as_percent else text


static func _trimmed(number: float) -> String:
	var text := "%.2f" % number
	text = text.rstrip("0").rstrip(".")
	return "0" if text == "-0" or text.is_empty() else text


## Накопить набор модификаторов, взятых на ранге rank, в словари свёртки.
## Статическая, потому что накапливают её ВСЕ источники модификаторов (дерево
## перков, награды забега, временные эффекты) — правило свёртки должно быть
## одно, иначе источники разойдутся в трактовке flat/mult.
static func fold(
	modifiers: Array, rank: int, flat: Dictionary, mult: Dictionary, bonus: float = 0.0
) -> void:
	for entry in modifiers:
		var mod := entry as RS_StatModifier
		if mod == null or mod.stat.is_empty():
			continue
		if mod.op == Op.MULT:
			mult[mod.stat] = mult.get(mod.stat, 1.0) * mod.contribution(rank, bonus)
		else:
			flat[mod.stat] = flat.get(mod.stat, 0.0) + mod.contribution(rank, bonus)


## Значение стата по свёрнутым словарям: (база + Σflat) × Πmult. Рядом с fold по
## той же причине — трактовка flat/mult должна быть одна на всех читателей, и
## стат души (C_StatModifiers) не должен разойтись со статом мира
## (SkillProgression.stat).
static func resolve(stat_id: StringName, base: float, flat: Dictionary, mult: Dictionary) -> float:
	return (base + float(flat.get(stat_id, 0.0))) * float(mult.get(stat_id, 1.0))


## Статы мира (ArchitectStats) в том же списке, что и статы души: модификатор не
## знает, в каком дереве лежит, а опечатка в имени стата одинаково тиха в обоих.
func _validate_property(property: Dictionary) -> void:
	if property.name != "stat":
		return
	var names := PackedStringArray()
	for id in C_StatModifiers.ALL + ArchitectStats.ALL:
		names.append(String(id))
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = ",".join(names)
