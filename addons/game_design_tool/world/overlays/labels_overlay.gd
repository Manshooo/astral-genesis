## res://addons/game_design_tool/world/overlays/labels_overlay.gd
## Оверлей «Подписи»: id узла, подобранный пресет и теги — над ВЫДЕЛЕННОЙ
## комнатой, не над всеми разом. Один из четырёх вариантов, обсуждённых при
## выборе MVP-набора оверлеев (см. [[Единый редактор геймдизайна]]); тогда
## выбрали только «Геометрия»/«Граф», «Подписи» достроены отдельным заходом, а
## показ только по выделению — правкой сразу вслед за этим (изначально
## задумывались как подпись над каждым узлом всегда — оказалось, что это
## загромождает вид слоя целиком, а вопрос «что это за узел» и так возникает
## именно у ВЫДЕЛЕННОГО).
##
## Имя пресета — не то, что можно посчитать по узлам и раскладке: это выбор
## RS_RoomPresetLibrary по совпадению scene.resource_path, для которого нужна
## сама библиотека. Вместо того чтобы тащить сюда library (оверлей тогда бы
## знал о подборе пресетов — чужая забота), вкладка (world_gen.gd) считает
## словарь node_id → имя пресета сама и кладёт его в GDT_LayerView.
##
## billboard + no_depth_test: подпись должна читаться с любого ракурса камеры
## и не теряться за стеной комнаты — это debug-оверлей, не часть мира.
@tool
extends Node3D

const Picker := preload("res://addons/game_design_tool/world/picker.gd")
const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")

const FONT_SIZE := 28
## world-space размер текста = font_size * pixel_size. 0.065 = 0.05 * 1.3 —
## на 30% крупнее исходного (тот был мелковат при обычной дистанции камеры).
const PIXEL_SIZE := 0.065
const COLOR := Color(0.95, 0.95, 0.9, 0.95)
## Насколько подпись стоит НАД верхней гранью AABB комнаты (Picker.room_aabb),
## а не просто «над узлом фиксированной высотой» — иначе у комнат с разным
## габаритом подпись либо утыкалась бы в потолок высокой, либо неоправданно
## далеко висела над низкой.
const ABOVE_AABB := 5.0

## Слой, кэшированный rebuild() — по нему set_selected() считает позицию и
## текст ОДНОЙ подписи, не перестраивая ничего на каждый клик.
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
