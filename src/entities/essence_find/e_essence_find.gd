## res://src/entities/essence_find/e_essence_find.gd
## Находка: деталь, которую подбирают интеракцией ради эссенции. Лежит в комнате
## (маркер «EssenceSpot*») или в тупике коридора (тайник).
##
## Данные находки (ключ отметки, номинал, источник) пишет тот, кто её ставит —
## LayerFinds, — а не сцена: сцена одна на все находки, а сумма и место зависят от
## сида. Деньги и отметку «взято» выдаёт LayerFinds.claim: сущность только
## подбирается и исчезает.
@tool
class_name E_EssenceFind
extends E_InteractableObject

## Ключ отметки в WorldSave.claim_node_reward: узел плюс место в нём, уникален на
## находку. Пустой — находка не расставлена (сцена открыта в редакторе).
var claim_key: StringName = &""
## Номинал, до множителя души (стат essence_gain).
var amount: int = 0
## Источник в разбивке забега: RS_RunStats.ESSENCE_PICKUP или ESSENCE_CACHE.
var source: StringName = &""


func interact() -> void:
	var granted := LayerFinds.claim(claim_key, source, amount)
	# 0 — отметка уже стоит (например, два отложенных interact() в одном кадре)
	# или находка не расставлена: награды нет, и объявлять о ней незачем.
	if granted <= 0:
		return
	C_ScreenMessage.show_on(E_Player.find(), String(tr(&"HUD_MSG_ESSENCE_FOUND")) % granted)
	interacted.emit(self)
	# remove_entity освобождает узел сам; interact() идёт отложенно, вне прохода
	# ECS, так что снимать структуру здесь законно (Правило v9).
	if ECS.world:
		ECS.world.remove_entity(self)
