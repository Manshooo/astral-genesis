# res://src/levels/props/exit_sign.gd
## Эвакуационная табличка: «ВЫХОД ↑ L0» и номер слоя. ЗАЧЕМ: цель игры — выбраться
## на поверхность, и мир сам должен её подсказывать — комплекс строили люди, и они
## знали, куда бежать (карточка «Игровой цикл — от и до», §6, п. 2).
##
## Какие цифры на табличке, сцена знать не может: одна и та же лестница или один и
## тот же портал стоят на любом слое. Поэтому номер ставит спавн — по слою УЗЛА,
## в котором комната, а не по RunManager.current_depth: на спавне нового слоя
## current_depth ещё указывает на старый (LayerStreamer ставит свою глубину в
## самом конце), а сама комната уже строится. Спавн зовёт [method stamp_depth] до
## add_entity, табличка принимает цифры через сеттеры и обновляет текст сама.
##
## Три вида:
## - ROUTE на стене лестницы: маршрут к выходу и номер слоя;
## - ROUTE на портале (billboard): то же плюс куда ведёт портал — направление
##   [member destination_depth]; у портала вниз маршрут «ВЫХОД ↑» не пишется, он
##   показывал бы в сторону, противоположную порталу;
## - DOOR над дверью наружу: одно слово «ВЫХОД».
##
## Знак — только картинка: ни коллизии, ни сокетов, ни сущности ECS. Он не меняет
## ни проходимость комнат, ни их габариты.
class_name ExitSign
extends Node3D

enum Kind { ROUTE, DOOR }

## Кегль единственного слова на табличке над дверью наружу (у двухстрочной — 56).
const DOOR_FONT_SIZE := 72

@export var kind: Kind = Kind.ROUTE:
	set(value):
		kind = value
		_refresh()
## Поворачивать ли знак к игроку вокруг вертикали и убрать подложку: так висит
## подпись у портала, который стоит посреди комнаты и виден со всех сторон.
@export var billboard: bool = false
## Номер слоя, на котором стоит знак. -1 — спавн его не проставил (сцена открыта
## сама по себе): строка слоя тогда не показывается, а не врёт «L?».
@export var layer_depth: int = -1:
	set(value):
		layer_depth = value
		_refresh()
## Слой, куда ведёт портал, у которого висит знак. -1 — знак не у портала.
@export var destination_depth: int = -1:
	set(value):
		destination_depth = value
		_refresh()

@onready var _plate: MeshInstance3D = %Plate
@onready var _exit_label: Label3D = %ExitLabel
@onready var _layer_label: Label3D = %LayerLabel


## Проставляет номер слоя всем табличкам внутри [param root] — комнате, ещё не
## вошедшей в дерево. Вызывается из LayerStreamer при спавне.
static func stamp_depth(root: Node, depth: int) -> void:
	for board in _signs_in(root):
		board.layer_depth = depth


## Проставляет, куда ведёт портал [param portal], табличкам внутри него.
static func stamp_destination(portal: Node, depth: int) -> void:
	for board in _signs_in(portal):
		board.destination_depth = depth


## Таблички в поддереве [param root], включая сам корень: find_children корень не
## считает, а знак может быть и корнем сцены.
static func _signs_in(root: Node) -> Array[ExitSign]:
	var found: Array[ExitSign] = []
	if root is ExitSign:
		found.append(root)
	for node in root.find_children("*", "ExitSign", true, false):
		found.append(node as ExitSign)
	return found


## Слой-поверхность. Не число в коде, а определение: L0 — самый верхний из слоёв
## графа, как его читает и карта комплекса.
static func surface_depth() -> int:
	return RS_LevelGraph.DEPTHS.min()


func _ready() -> void:
	_plate.visible = not billboard
	var mode := BaseMaterial3D.BILLBOARD_FIXED_Y if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	for label: Label3D in [_exit_label, _layer_label]:
		label.billboard = mode
		label.double_sided = billboard
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()


## Что написано в верхней строке — для проверок. Пусто — строка скрыта.
func exit_line() -> String:
	return _exit_label.text if _exit_label and _exit_label.visible else ""


## Что написано в нижней строке — для проверок. Пусто — строка скрыта.
func layer_line() -> String:
	return _layer_label.text if _layer_label and _layer_label.visible else ""


func _refresh() -> void:
	# Сеттеры звонят и до входа в дерево (спавн штампует цифры раньше _ready):
	# тогда узлы ещё не найдены, и текст соберёт сам _ready.
	if not is_node_ready():
		return
	if kind == Kind.DOOR:
		# Единственное слово — по центру подложки и крупнее: верхняя строка
		# двухстрочной таблички оставила бы под ним пустое поле.
		_exit_label.position.y = 0.0
		_exit_label.font_size = DOOR_FONT_SIZE
		_exit_label.visible = true
		_exit_label.text = tr("EXIT_SIGN_DOOR")
		_layer_label.visible = false
		return

	var surface := surface_depth()
	var goes_down := destination_depth > layer_depth and layer_depth >= 0
	_exit_label.visible = not goes_down
	if layer_depth == surface:
		# Уже наверху: стрелка вверх вела бы в никуда, остаётся слово.
		_exit_label.text = tr("EXIT_SIGN_DOOR")
	else:
		_exit_label.text = tr("EXIT_SIGN_ROUTE") % surface

	var line := ""
	if destination_depth >= 0 and layer_depth >= 0 and destination_depth != layer_depth:
		var key := "EXIT_SIGN_PORTAL_UP" if destination_depth < layer_depth else "EXIT_SIGN_PORTAL_DOWN"
		line = tr(key) % destination_depth
	elif layer_depth >= 0:
		line = tr("EXIT_SIGN_LAYER") % layer_depth
	_layer_label.text = line
	_layer_label.visible = line != ""
