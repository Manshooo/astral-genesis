## res://addons/level_gen_tool/plugin.gd
## Регистрирует док «Генератор» в правой панели редактора — в том же слоте, что и
## «Шаблоны» из entity_template_tool, так что оба живут вкладками одного дока.
@tool
extends EditorPlugin

const Dock := preload("res://addons/level_gen_tool/dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = Dock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
