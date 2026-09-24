# res://src/ui/hud/hud_map.gd
## Мини-карта в HUD: этаж, на котором сейчас игрок.
##
## Показывает СКРОМНО и намеренно: комнаты и ветки коридора, где игрок был, плюс
## те, о существовании которых он знает — потому что видел ведущую туда дверь
## (MapKnowledge.known_nodes). Ветка коридора видна ЦЕЛИКОМ, как только
## известна: это тот же «сосед», что и комната, и дробить её на пройденные тайлы
## значило бы хранить их в сейве ради подробности, которую правильнее отдать
## улучшениям «Архитектора». Всё остальное не рисуется. Полная карта комплекса —
## отдельный экран на паузе (UI_ComplexMap).
##
## Рисует общий UI_MapFloor — тот же, что панели этажей на экране карты; здесь
## остаётся только выбор «что показать» и опрос игрока на ходу.
class_name UI_HudMap
extends UI_MapFloor

## Насколько игрок должен сдвинуться (метры) или повернуться, чтобы карта
## перерисовалась. Перерисовывать вектор каждый кадр незачем: клетка карты — это
## 18 м мира, и шаг в полметра на ней едва виден.
const REDRAW_MOVE := 0.3
const REDRAW_TURN := 0.02  # ~1° по косинусу между направлениями

var _last_position := Vector3.INF
var _last_forward := Vector2.ZERO


func _ready() -> void:
	RunManager.room_changed.connect(_on_run_changed)
	RunManager.layer_changed.connect(_on_run_changed)
	RunManager.complex_entered.connect(_on_run_changed)


func _on_run_changed(_arg: Variant = null) -> void:
	queue_redraw()


## Маркер игрока живёт непрерывно, а сигналов о том, что игрок прошёл два шага,
## нет — поэтому опрашиваем, как и остальной HUD (см. UI_HudVitals). Но карта
## рисуется вектором целиком, так что перерисовку просим только когда игрок
## реально сместился или повернулся.
func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var player := UI_MapFloor.player_node()
	if player == null:
		return

	var player_now := player.global_position
	var forward := UI_MapFloor.forward_of(player)
	var moved := player_now.distance_squared_to(_last_position) >= REDRAW_MOVE * REDRAW_MOVE
	var turned := forward.dot(_last_forward) <= 1.0 - REDRAW_TURN
	if not moved and not turned:
		return

	_last_position = player_now
	_last_forward = forward
	queue_redraw()


func _draw() -> void:
	if build_view().is_empty():
		return
	super()


## Что и где рисовать — отдельно от рисования, чтобы проверка могла спросить
## карту без пикселей: известные комнаты и ветки ТЕКУЩЕГО этажа, план и вписывание
## показанных клеток в контрол. Пусто — рисовать нечего.
##
## Только свой этаж: этажи слоя разнесены по высоте и в одной плоскости соседями
## не являются — рисовать их вперемешку значит врать про геометрию.
func build_view() -> Dictionary:
	var graph := RunManager.current_graph
	var current_id := RunManager.current_node_id
	if graph == null or current_id == &"":
		return {}
	var current := graph.get_node_data(current_id)
	if current == null:
		return {}

	plan = RunManager.plan_for_depth(current.depth)
	floor_index = current.floor_index
	here = current_id
	visited = WorldSave.save.visited_node_ids
	set_nodes(MapKnowledge.known_nodes(graph.get_nodes_by_depth(current.depth), visited))

	var player := UI_MapFloor.player_node()
	show_player = player != null
	if player:
		player_position = player.global_position
		player_forward = UI_MapFloor.forward_of(player)

	if not fit():
		return {}
	return {"plan": plan, "here": here, "floor": floor_index, "rooms": rooms, "branches": branches}
