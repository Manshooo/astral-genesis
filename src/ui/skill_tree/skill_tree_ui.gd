## res://src/ui/skill_tree/skill_tree_ui.gd
## Экран дерева навыков: рамка, счётчик очков и граф внутри.
##
## Сам экран навыков не рисует — этим занят UI_SkillGraph. Здесь остаётся то,
## что графу знать незачем: сколько у игрока очков, кто тратит их на
## разблокировку и как экран закрывается. Разделение не косметическое: граф
## умеет только показывать состояние, поэтому его можно собрать и проверить,
## не заводя ни SkillManager, ни стек экранов.
class_name SkillTreeUI
extends Control

@onready var points_label: Label = $Panel/MarginContainer/VBox/Header/PointsLabel
@onready var graph_host: Control = $Panel/MarginContainer/VBox/GraphHost

var _skill_manager
var _tree_data: RS_SkillTree
var _graph: UI_SkillGraph


func setup(skill_manager, tree_data: RS_SkillTree) -> void:
	_skill_manager = skill_manager
	_tree_data = tree_data

	_graph = UI_SkillGraph.new()
	_graph.name = "Graph"
	graph_host.add_child(_graph)
	_graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_graph.skill_activated.connect(_on_skill_activated)
	_graph.setup(skill_manager, tree_data)

	_skill_manager.skill_unlocked.connect(_on_skill_unlocked)
	_refresh_points()


func _on_skill_activated(id: StringName) -> void:
	_skill_manager.unlock(id)


## Разблокировка меняет и очки, и доступность соседей, и состав видимого:
## новый ранг мог открыть ветку целиком. Поэтому граф пересобирается полностью,
## а не подкрашивает одну карточку — дешевле, чем вычислять, кого задело.
func _on_skill_unlocked(id: StringName, _new_rank: int) -> void:
	_refresh_points()
	_graph.refresh()
	_graph.play_unlock_effect(id)


func _refresh_points() -> void:
	points_label.text = "Очки: %d" % _skill_manager.save.skill_points


func _on_close_pressed() -> void:
	UIManager.close_top()


func _exit_tree() -> void:
	if _skill_manager and _skill_manager.skill_unlocked.is_connected(_on_skill_unlocked):
		_skill_manager.skill_unlocked.disconnect(_on_skill_unlocked)
