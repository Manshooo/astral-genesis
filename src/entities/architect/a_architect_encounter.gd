class_name A_ArchitectEncounter
extends RS_InteractionAction
## Встреча с Архитектором: первое касание за забег даёт эссенцию, каждое —
## открывает его улучшения. Одно действие, а не два: разнеси награду и экран по
## разным объектам, и найти Архитектора значило бы ещё и искать, где его
## прокачать. Первая встреча открывает и вкладку Архитектора на экране навыков —
## с неё эссенцию можно тратить и у инкубатора.
##
## Награда привязана к узлу через WorldSave.claim_node_reward, а не к сущности:
## комната собирается из сида заново после каждой загрузки, и отметка на самой
## сущности пропала бы вместе с ней.


func execute(_entity: Entity, _interactor: Node = null) -> void:
	# Текущий узел меняет присутствие, так что у самого артефакта это всегда его
	# комната. Пустой он только вне забега — тогда награды нет, а экран есть.
	if WorldSave.claim_node_reward(RunManager.current_node_id):
		ArchitectManager.add_skill_points(GameConfig.config.architect_essence_reward)
	ArchitectManager.mark_met()
	UIManager.open_skill_tree(ArchitectManager, ArchitectManager.SKILL_TREE)
