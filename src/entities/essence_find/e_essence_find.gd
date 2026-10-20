## res://src/entities/essence_find/e_essence_find.gd
## Находка: деталь, которую подбирают ради эссенции (маркер EssenceSpot* или тупик коридора). Данные пишет
## LayerFinds, он же выдаёт награду и отметку (LayerFinds.claim); сущность только подбирается и исчезает.
@tool
class_name E_EssenceFind
extends E_InteractableObject

## Ключ отметки в WorldSave.claim_node_reward: узел плюс место; пустой — не расставлена.
var claim_key: StringName = &""
## Номинал, до множителя души (стат essence_gain).
var amount: int = 0
## Источник в разбивке забега: RS_RunStats.ESSENCE_PICKUP или ESSENCE_CACHE.
var source: StringName = &""


func interact() -> void:
	var granted := LayerFinds.claim(claim_key, source, amount)
	# 0 — отметка уже стоит (два interact() в кадре) или находка не расставлена: награды нет.
	if granted <= 0:
		return
	C_ScreenMessage.show_on(E_Player.find(), String(tr(&"HUD_MSG_ESSENCE_FOUND")) % granted)
	interacted.emit(self)
	# interact() идёт отложенно, вне прохода ECS — снимать структуру законно (правило v9).
	if ECS.world:
		ECS.world.remove_entity(self)
