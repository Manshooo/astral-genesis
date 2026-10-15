class_name RS_SkillDefinition
extends Resource
## Один навык дерева: чем он является для игрока, чего стоит и что меняет.
##
## Место навыка в графе здесь НЕ задаётся — сектор и кольцо нейросети выводит
## SkillGraphLayout из ветки и требований. Иначе добавление навыка стоило бы
## ещё и ручной расстановки координат, а первая же вставка в середину цепочки
## заставила бы двигать всё, что правее.

@export var id: StringName = &""            # "body_snatch", "lifespan"
@export var display_name: String = ""
@export var description: String = ""
@export var branch: StringName = &"default"  ## "possession", "survival" — сектор в графе
@export var max_rank: int = 3
@export var cost_per_rank: Array[int] = [1, 2, 3]   ## очков навыка за каждый ранг
@export var requires: Array[RS_SkillRequirement] = []

## Что скилл делает с механикой. Здесь, а не кодом в O_ApplySkillEffects: скилл,
## который крутит уже существующее число, должен стоить строчки в .tres.
## Величины задаются на ОДИН ранг — умножение на ранг делает свёртка.
@export var modifiers: Array[RS_StatModifier] = []

## На сколько выполненное условие ранга усиливает значение ЭТОГО ранга: 0.2 —
## +20 % (12 → 14.4). Один на навык, а не на ранг: так «Скорость» из карточки
## читается одной строкой, а условия по рангам различаются только действием.
@export_range(0.0, 1.0, 0.01) var condition_bonus: float = 0.0
## Условие каждого ранга: rank_conditions[0] — для ранга 1. Короче max_rank или
## null — у ранга условия нет, и бонуса он не получает. Прогресс считается
## только по условию ТЕКУЩЕГО ранга: бонус ранга 2 не зависит от того, что
## сделано под ранг 1.
@export var rank_conditions: Array[RS_SkillCondition] = []

## Способность тела, без которой навык ничего не меняет (&"walk", &"jump",
## &"sprint"); пусто — навык не привязан к способности. «Навык способности»
## (карточка «Игровой цикл» §4.1): в безногом теле скорость ходьбы гаснет сама,
## потому что компонента нет и система ходьбы тело не видит, — а поле нужно
## затем, чтобы карточка сказала об этом игроку.
@export var ability: StringName = &""

## Ручной слот по дуге своего кольца в секторе ветки (0 — крайний против
## часовой стрелки); -1 — «расставь сам».
## Аварийный выход для случая, когда автораскладка развела соседей не так, как
## читается ветка. Оставлять -1 всюду, где не мешает: закреплённая строка не
## подвинется, когда рядом появится новый навык.
@export var graph_row: int = -1


## Сколько стоит следующий ранг. -1 если уже максимум.
##
## max_rank и cost_per_rank — два независимых поля инспектора, и поднять первое,
## не дописав второе, легко. Раньше это роняло покупку выходом за границы
## массива в момент клика; теперь ранг без цены просто не продаётся, а
## RS_SkillTree.validate() называет навык заранее.
func cost_for_next_rank(current_rank: int) -> int:
	if current_rank >= max_rank:
		return -1
	if current_rank >= cost_per_rank.size():
		push_error(
			"RS_SkillDefinition '%s': max_rank=%d, а цен в cost_per_rank %d — ранг %d не продаётся"
			% [id, max_rank, cost_per_rank.size(), current_rank + 1]
		)
		return -1
	return cost_per_rank[current_rank]


## Условие ранга [param rank] (1-based) или null, если его нет.
func condition_for_rank(rank: int) -> RS_SkillCondition:
	if rank < 1 or rank > rank_conditions.size():
		return null
	return rank_conditions[rank - 1]


## Бонус, который даёт выполненное условие, — но только если условие у ранга есть:
## навык без условий на ранге не должен получать бонус из одного поля.
func bonus_for_rank(rank: int) -> float:
	return condition_bonus if condition_for_rank(rank) != null else 0.0


## Компонент способности, нужный навыку, или null (навык ни к чему не привязан).
## Через match, а не словарь констант: ссылки на классы в const-словаре
## резолвятся на компиляции, а нам нужен рантайм (см. SkillProgression.DEFAULT_SAVE).
func ability_component() -> Script:
	match ability:
		&"walk":
			return C_Walk
		&"jump":
			return C_Jump
		&"sprint":
			return C_Sprint
	return null
