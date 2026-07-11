## res://src/resources/interaction/rs_open_skill_tree_action.gd
## Открывает дерево навыков через UIManager. Не привязан жёстко к инкубатору -
## можно повесить на любой другой E_InteractableObject.
class_name RS_OpenSkillTreeAction
extends RS_InteractionAction

## Если не задано - берётся дефолтное SkillManager.SKILL_TREE.
@export var tree_data: RS_SkillTree


func execute(_entity: Entity, _interactor: Node = null) -> void:
	UIManager.open_skill_tree(SkillManager, tree_data if tree_data else SkillManager.SKILL_TREE)
