class_name A_ArchitectEncounter
extends RS_InteractionAction
## Встреча с Архитектором: первое касание за забег даёт эссенцию, каждое открывает его улучшения (одно действие,
## чтобы не искать, где прокачать). Награда привязана к узлу (WorldSave.claim_node_reward), не к сущности — комната пересобирается из сида.


func execute(_entity: Entity, _interactor: Node = null) -> void:
	# Текущий узел — комната артефакта; пустой он только вне забега: награды нет, экран есть.
	if WorldSave.claim_node_reward(RunManager.current_node_id):
		var reward: int = GameConfig.config.architect_essence_reward
		ArchitectManager.add_skill_points(reward)
		# В разбивку сводки забега: эссенция приходит из нескольких источников.
		RunStats.credit(RS_RunStats.ESSENCE_ARCHITECT, reward)
	ArchitectManager.mark_met()
	UIManager.open_skill_tree(ArchitectManager, ArchitectManager.SKILL_TREE)
