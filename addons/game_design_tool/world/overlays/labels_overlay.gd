## res://addons/game_design_tool/world/overlays/labels_overlay.gd
## Оверлей «Подписи»: Label3D над каждым узлом слоя — id, подобранный пресет,
## теги узла. Один из четырёх вариантов, обсуждённых при выборе MVP-набора
## оверлеев (см. [[Единый редактор геймдизайна]]); тогда выбрали только
## «Геометрия»/«Граф», «Подписи» достроены отдельным заходом.
##
## Имя пресета — не то, что можно посчитать по layer_nodes/plan: это выбор
## RS_RoomPresetLibrary по совпадению scene.resource_path, для которого нужна
## сама библиотека. Вместо того чтобы тащить сюда library (оверлей тогда бы
## знал о подборе пресетов — чужая забота), вкладка (world_gen.gd) считает
## словарь node_id → имя пресета сама и просто отдаёт готовый текст.
##
## billboard + no_depth_test: подписи должны читаться с любого ракурса камеры
## и не теряться за стеной комнаты — это debug-оверлей, не часть мира.
@tool
extends Node3D

## Насколько подпись приподнята над маркером графа (у того своя высота
## NODE_HEIGHT в graph_overlay.gd) — иначе текст перекрывает сферу узла.
const LABEL_HEIGHT := 5.0
const FONT_SIZE := 28
## world-space размер текста = font_size * pixel_size; при шаге сетки
## ROOM_SPACING = 60 м подписи должны читаться от соседней комнаты, не только
## в упор.
const PIXEL_SIZE := 0.05
const COLOR := Color(0.95, 0.95, 0.9, 0.95)

var _labels: Dictionary[StringName, Label3D] = {}


## [param preset_labels] node_id -> имя пресета ("" — пресет не найден,
## например у узла-хаба: авторская сцена вне библиотеки).
func rebuild(
	layer_nodes: Array[RS_LevelNode], plan: RS_LayerPlan, preset_labels: Dictionary
) -> void:
	_clear()
	for node_data: RS_LevelNode in layer_nodes:
		var pos: Vector3 = plan.positions.get(node_data.id, Vector3.ZERO) + Vector3(0, LABEL_HEIGHT, 0)
		var label3d := Label3D.new()
		label3d.position = pos
		label3d.text = _text_for(node_data, preset_labels.get(node_data.id, ""))
		label3d.font_size = FONT_SIZE
		label3d.pixel_size = PIXEL_SIZE
		label3d.modulate = COLOR
		label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label3d.no_depth_test = true
		label3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(label3d)
		_labels[node_data.id] = label3d


func _text_for(node_data: RS_LevelNode, preset_label: String) -> String:
	var lines: Array[String] = [String(node_data.id)]
	lines.append(preset_label if preset_label != "" else "—")
	if not node_data.tags.is_empty():
		lines.append(", ".join(node_data.tags))
	return "\n".join(lines)


## free(), не queue_free() — та же причина, что у RoomsOverlay/GraphOverlay:
## пересборка слоя синхронная, отложенное удаление копило бы старые подписи
## поверх новых.
func _clear() -> void:
	for label3d: Label3D in _labels.values():
		label3d.free()
	_labels.clear()
