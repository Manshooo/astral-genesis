class_name C_Ability
extends C_BodyTrait
## База способностей слотов 1–4: тело приносит их как любую характеристику, поглощённые хранит душа
## (C_AbilityLoadout). Что делает способность — наследник и его система (C_Regeneration → S_Regeneration),
## нажатие и откат — S_Abilities. Вики: [[Захват тела]] §«Способности и слоты».

## Слот тела, 1–4; открыт ли он душе, решает стат ability_slots.
@export_range(1, 4) var slot: int = 1

## Пауза после применения, с.
@export var cooldown: float = 10.0

## Ключ перевода имени.
@export var name_key: StringName = &""

@export var icon: Texture2D

## Сколько ждать до следующего применения, с. Рабочее состояние: копия в банке хранит своё.
var cooldown_left := 0.0

## Копия, которую душа забрала себе (C_AbilityLoadout): не уезжает с телом (E_Body.is_wearable).
var absorbed := false

## Защёлка применения: ставит S_Abilities, гасит система способности.
var requested := false


## Почему применить нельзя сейчас — ключ сообщения; пусто — можно. Откат и закрытый слот проверяет S_Abilities.
func refusal(_owner: Entity) -> String:
	return ""


## Копия для души: число и иконка те же, состояние с нуля.
func absorbed_copy() -> C_Ability:
	var copy := duplicate() as C_Ability
	copy.absorbed = true
	copy.cooldown_left = 0.0
	copy.requested = false
	return copy
