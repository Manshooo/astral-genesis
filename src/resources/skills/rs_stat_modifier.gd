class_name RS_StatModifier
extends Resource
## Одна прибавка к одному стату, объявленная ДАННЫМИ: скилл на существующую механику стоит строчки в .tres. stat — выпадающий
## список из C_StatModifiers.ALL. Число — на ОДИН ранг (per_rank) либо списком по рангам (values).

enum Op {
	FLAT,  ## Плоская прибавка к базе: +0.5 м к дальности захвата
	MULT,  ## Множитель, заданный долей: 0.1 = +10%
}

@export var stat: StringName = &""
@export var op: Op = Op.FLAT
## Величина НА ОДИН РАНГ (для MULT — доля: 0.1 на ранге 3 даёт ×1.3); не читается, если задан values.
@export var per_rank: float = 0.0
## Итоговое значение КАЖДОГО ранга (не добавка): 0.10 / 0.12 / 0.15 — на ранге 3 +15 %. Пусто — линейный per_rank. Рангов больше
## значений — читают последнее (валидатор дерева называет).
@export var values: Array[float] = []
## Показывать процентами и у FLAT-стата; у MULT всегда.
@export var display_percent: bool = false


## Значение ранга БЕЗ бонуса условия; нулевой ранг ничего не даёт.
func value_at(rank: int) -> float:
	if rank <= 0:
		return 0.0
	if values.is_empty():
		return per_rank * rank
	return values[mini(rank, values.size()) - 1]


## Вклад в свёртку на ранге. [param bonus] усиливает ЗНАЧЕНИЕ этого ранга (0.2 → ×1.2), не итог: бонус не копится от ранга к рангу
## (решение 15.10). Линейно по рангу у старых навыков — описание в UI читается без калькулятора.
func contribution(rank: int, bonus: float = 0.0) -> float:
	var value := value_at(rank) * (1.0 + bonus)
	if op == Op.MULT:
		return 1.0 + value
	return value


## Значение ранга строкой для карточки: «+12%», «+0.3»; точка, лишние нули убираются.
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


## Накопить набор модификаторов ранга в словари свёртки. Статическая: правило одно для всех источников (перки, награды, эффекты).
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


## Значение стата: (база + Σflat) × Πmult — одна трактовка для стата души и мира (SkillProgression.stat).
static func resolve(stat_id: StringName, base: float, flat: Dictionary, mult: Dictionary) -> float:
	return (base + float(flat.get(stat_id, 0.0))) * float(mult.get(stat_id, 1.0))


## Статы мира (ArchitectStats) в том же списке, что и души.
func _validate_property(property: Dictionary) -> void:
	if property.name != "stat":
		return
	var names := PackedStringArray()
	for id in C_StatModifiers.ALL + ArchitectStats.ALL:
		names.append(String(id))
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = ",".join(names)
