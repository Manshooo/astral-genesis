class_name C_AbilityLoadout
extends Component
## Поглощённые душой способности на забег: слоты души и банк. Тело главнее: во плоти способность тела
## перекрывает слот души с тем же номером, поглощённая под ней спит (решение 20.10, «А + Б и банк»).
## Будит и усыпляет S_AbilityLoadout, в сейв пишет RunManager. Вики: [[Захват тела]] §«Способности и слоты».

const MAX_SLOTS := 4
## База 2 и ветка души +1…+3 — больше пяти ячеек HUD не рисует.
const MAX_BANK := 5
## Клавиши слотов по номеру (индекс 0 — слот 1); цифры 1–4 в project.godot.
const ACTIONS: Array[StringName] = [&"ability_1", &"ability_2", &"ability_3", &"ability_4"]

## Чем кончилось поглощение одной способности.
enum Placement { SLOT, BANK, BANK_FULL, KNOWN }

## Слоты души 1–4 по индексу 0–3; null — пусто. Массивы ПЕРЕСОБИРАЮТСЯ, не правятся на месте (C_StatModifiers._refold).
var slots: Array[C_Ability] = [null, null, null, null]
var bank: Array[C_Ability] = []
## Не поместились в полный банк и ждут ответа игрока (экран выбора).
var pending: Array[C_Ability] = []


## Что видно и что работает в слоте [member number]: снимок на кадр для S_Abilities и HUD.
class SlotView:
	extends RefCounted
	var number := 1
	var locked := false
	## Способность надетого тела в этом слоте.
	var body: C_Ability
	## Поглощённая в слоте души.
	var soul: C_Ability

	## Что показывает ячейка: тело главнее.
	func shown() -> C_Ability:
		return body if body else soul

	## Поглощённая спит под способностью тела.
	func sleeping() -> bool:
		return body != null and soul != null


## Сколько слотов открыто душе: база из конфига плюс ветка слотов (стат ability_slots).
static func open_slots(soul: Entity) -> int:
	var base := float(GameConfig.config.ability_slots_base)
	return clampi(roundi(C_StatModifiers.of(soul, C_StatModifiers.ABILITY_SLOTS, base)), 0, MAX_SLOTS)


static func bank_size(soul: Entity) -> int:
	var base := float(GameConfig.config.bank_slots_base)
	return clampi(roundi(C_StatModifiers.of(soul, C_StatModifiers.BANK_SLOTS, base)), 0, MAX_BANK)


## Способность надетого тела в слоте [param number] или null.
static func body_ability(soul: Entity, number: int) -> C_Ability:
	for component in soul.components.values():
		var ability := component as C_Ability
		if ability and not ability.absorbed and ability.slot == number:
			return ability
	return null


func view(soul: Entity, number: int) -> SlotView:
	var v := SlotView.new()
	v.number = number
	v.locked = number > open_slots(soul)
	v.body = body_ability(soul, number)
	v.soul = slots[number - 1]
	return v


## Поглотить способность тела: в первый открытый пустой слот души, иначе в банк, иначе в очередь выбора.
## Уже известная душе не дублируется.
func absorb(soul: Entity, ability: C_Ability) -> Placement:
	if knows(ability):
		return Placement.KNOWN
	var copy := ability.absorbed_copy()
	for i in open_slots(soul):
		if slots[i] == null:
			var next := slots.duplicate()
			next[i] = copy
			slots = next
			return Placement.SLOT
	if bank.size() < bank_size(soul):
		var grown := bank.duplicate()
		grown.append(copy)
		bank = grown
		return Placement.BANK
	var queued := pending.duplicate()
	queued.append(copy)
	pending = queued
	return Placement.BANK_FULL


## Ответ игрока на полный банк: заменить ячейку [param index] первой ждущей или (index < 0) не брать её.
func resolve_pending(index: int) -> C_Ability:
	if pending.is_empty():
		return null
	var next_pending := pending.duplicate()
	var taken: C_Ability = next_pending.pop_front()
	pending = next_pending
	if index < 0 or index >= bank.size():
		return null
	var next_bank := bank.duplicate()
	var dropped: C_Ability = next_bank[index]
	next_bank[index] = taken
	bank = next_bank
	return dropped


## Та же способность (по классу) уже есть у души — в слоте, банке или очереди.
func knows(ability: C_Ability) -> bool:
	var script: Script = ability.get_script()
	for held in slots + bank + pending:
		if held != null and held.get_script() == script:
			return true
	return false
