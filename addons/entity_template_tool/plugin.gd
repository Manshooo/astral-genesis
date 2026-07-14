## res://addons/entity_template_tool/plugin.gd
## Регистрирует док «Шаблоны сущностей» в правой панели редактора.
@tool
extends EditorPlugin

const Dock := preload("res://addons/entity_template_tool/dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = Dock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
