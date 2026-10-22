# res://src/observers/o_combat_mark.gd
# Урон по душе открывает окно «в бою» (C_AbilityLoadout.combat_left): пока оно не истекло, перенос из банка закрыт. Событие, а не опрос HP —
# падение HP врёт (смена тела, потолок после перка). Вики: [[Захват тела]] §«Способности и слоты».
class_name O_CombatMark
extends Observer


func query() -> QueryBuilder:
	return q.with_all([C_AbilityLoadout]).on_event(&"damage_dealt")


func each(_event: Variant, entity: Entity, _payload: Variant = null) -> void:
	var loadout := entity.get_component(C_AbilityLoadout) as C_AbilityLoadout
	loadout.combat_left = GameConfig.config.combat_window
