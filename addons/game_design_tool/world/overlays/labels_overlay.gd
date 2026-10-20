## res://addons/game_design_tool/world/overlays/labels_overlay.gd
## Оверлей «Подписи»: id узла, пресет и теги над ВЫДЕЛЕННОЙ комнатой. Имя
## пресета приходит готовым в GDT_LayerView.preset_labels — библиотеку оверлей не знает.
## [[Редакторские инструменты]] §«Коридоры и сетка во вьюпорте».
@tool
extends Node3D

const Picker := preload("res://addons/game_design_tool/world/picker.gd")
const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")

const FONT_SIZE := 28
## Размер текста в мире = font_size * pixel_size.
const PIXEL_SIZE := 0.065
const COLOR := Color(0.95, 0.95, 0.9, 0.95)
## Отступ над верхней гранью Picker.room_aabb: у комнат разной высоты фиксированный не годится.
const ABOVE_AABB := 5.0

## Слой из rebuild(), по нему set_selected() считает подпись.
var _view: LayerView

var _label: Label3D


func _init() -> void:
	_label = Label3D.new()
	_label.font_size = FONT_SIZE
	_label.pixel_size = PIXEL_SIZE
	_label.modulate = COLOR
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.visible = false
	add_child(_label)


func rebuild(view: LayerView) -> void:
	_view = view
	_label.visible = false


func set_selected(node_id: StringName) -> void:
	var node_data := _view.node_by_id(node_id) if _view else null
	if node_data == null or _view.plan == null:
		_label.visible = false
		return

	var aabb := Picker.room_aabb(node_id, _view.nodes, _view.plan)
	var center := aabb.get_center()
	_label.position = Vector3(center.x, aabb.position.y + aabb.size.y + ABOVE_AABB, center.z)
	_label.text = _text_for(node_data, _view.preset_labels.get(node_id, ""))
	_label.visible = true


func _text_for(node_data: RS_LevelNode, preset_label: String) -> String:
	var lines: Array[String] = [String(node_data.id)]
	lines.append(preset_label if preset_label != "" else "—")
	if not node_data.tags.is_empty():
		lines.append(", ".join(node_data.tags))
	return "\n".join(lines)
