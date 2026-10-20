## res://src/resources/interaction/a_open_skill_tree.gd
## Открывает дерево навыков через UIManager; можно повесить на любой E_InteractableObject.
class_name A_OpenSkillTree
extends RS_InteractionAction

## Если не задано — SkillManager.SKILL_TREE.
@export var tree_data: RS_SkillTree


func execute(_entity: Entity, _interactor: Node = null) -> void:
	UIManager.open_skill_tree(SkillManager, tree_data if tree_data else SkillManager.SKILL_TREE)
