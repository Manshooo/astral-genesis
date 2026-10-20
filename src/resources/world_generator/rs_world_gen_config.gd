## res://src/resources/world_generator/rs_world_gen_config.gd
## Ручки генерации комплекса — данными, ради улучшений Архитектора (они меняют мир: меньше тупиков, больше петель). Забег генерируется по СНИМКУ
## этого ресурса в сейве (RS_WorldSave.gen_config), не по живому data/world_gen_config.tres: иначе улучшение, купленное посреди забега, на загрузке дало бы другой комплекс.
@tool  # читается генератором и в редакторской вкладке «Генератор мира»
class_name RS_WorldGenConfig
extends Resource

@export_group("Этажи")
## Комнат на этаже, вместе с уникальными. Порталы берут места из этого же числа: при 4 слою хаба оставалось 5 % обычных комнат (замер 29.09); в data/ — 8.
@export_range(1, 12) var rooms_per_floor: int = 4
## Сколько этажей в слое (включительно).
@export_range(1, 5) var floor_count_min: int = 1
@export_range(1, 5) var floor_count_max: int = 3

@export_group("Коридоры")
# Ручки «веток на этаж» нет: сколько коридоров, выводится из сети.
## Улица — минимум клеток между комнатами при разбросе (RS_CorridorPlanner._place_rooms). Меньше двух нельзя: на улице в клетку коридор обволакивал бы комнаты (от четверти до трети).
@export_range(2, 5) var room_gap: int = 2
## Доля области этажа под комнаты вместе с улицами: меньше — просторнее и длиннее коридоры. Область растёт сама, если не хватило места, — ручка разреженность, не потолок.
@export_range(0.2, 0.9) var room_density: float = 0.65
## Сколько петель по коридору раскладка пробует добавить на этаж; обволакивающая комнату не ставится, на тесном этаже выходит меньше.
@export_range(0, 4) var corridor_loops: int = 1
## Сколько тупиков на этаж: отросток в 1–2 клетки; клетка отмечается (RS_LayerPlan.dead_ends) под награду. База — 3; «Меньше тупиков» снимает до одного, не до нуля.
@export_range(0, 4) var dead_ends: int = 1

@export_group("Вертикаль")
## Лестница между этажами слоя: коробка в два уровня, нижняя дверь — в коридор своего этажа, верхняя — этажа выше; по одной на пару вместо порталов
## (RS_LevelGraph._place_floor_stairs). Пусто — этажи связывают порталы. Между слоями — всегда порталы.
@export var floor_stairs: RS_RoomPreset
## Сколько вертикальных переходов между соседними слоями.
@export_range(1, 6) var layer_connectors: int = 3
## Шанс, что вертикальный переход заперт; один на пару слоёв открыт всегда (ключей нет).
@export_range(0.0, 1.0) var layer_lock_chance: float = 0.35
## Насколько переходы жмутся к этажу прихода (0 — где выпало, 1 — все на одном); улучшение «Переходы ближе ко входу». Предпочтение: порядок кандидатов пересобирается
## после броска, rng тратится одинаково. Этаж прихода — этаж хаба на слое хаба, нижний на остальных.
@export_range(0.0, 1.0) var transit_near_entry: float = 0.0

@export_group("Уникальные комнаты")
## Порядок записей важен: розыгрыш идёт по нему.
@export var unique_rooms: Array[RS_UniqueRoom] = []


## Расхождения, из-за которых генерация не выполнит обещанное; пусто — всё сходится.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if floor_count_min > floor_count_max:
		problems.append("этажей: минимум %d больше максимума %d" % [floor_count_min, floor_count_max])
	var entries := 0
	for i in unique_rooms.size():
		var unique := unique_rooms[i]
		if unique == null or unique.preset == null or unique.preset.scene == null:
			problems.append("уникальная комната #%d без пресета или сцены" % i)
			continue
		if unique.depth_min > unique.depth_max:
			problems.append("уникальная комната «%s»: глубины перепутаны" % unique.preset.display_name)
		elif unique.allowed_depths().is_empty():
			problems.append("уникальная комната «%s»: все глубины вычеркнуты" % unique.preset.display_name)
		# Роль выхода — запись конфига, дверь наружу — коробка сцены; разойдясь, они оставили бы комнату выхода без выхода.
		var exit_shell := RS_RoomLayout.shell_of_scene(unique.preset.scene.resource_path)
		if unique.exit and exit_shell and exit_shell.exit_sockets.is_empty():
			problems.append("комната выхода «%s» без двери наружу (C_RoomShell.exit_sockets)" % unique.preset.display_name)
		if unique.entry:
			entries += 1
			if unique.count != 1 or unique.chance < 1.0:
				problems.append("вход обязан быть ровно один и гарантированный")
		elif unique.apart_from_entry and entries == 0:
			# Розыгрыш идёт по порядку списка: до входа его этаж не известен.
			problems.append(
				"уникальная комната «%s» не должна вставать на этаж входа, но стоит в списке раньше него"
				% unique.preset.display_name
			)
	if entries != 1:
		problems.append("входов среди уникальных комнат %d, нужен ровно один" % entries)
	problems.append_array(_validate_stairs())
	return problems


## Лестница обязана связать этаж с этажом выше: сокет на нижнем уровне и на следующем, оба открыты (иначе верхняя дверь могла бы не выпасть).
func _validate_stairs() -> Array[String]:
	var problems: Array[String] = []
	if floor_stairs == null:
		return problems
	var path := floor_stairs.scene.resource_path if floor_stairs.scene else ""
	var levels := {}
	var sockets := RS_RoomLayout.sockets_of_scene(path)
	for face in sockets:
		levels[face.y] = true
	if RS_RoomLayout.shell_of_scene(path) == null or not levels.has(0) or not levels.has(1):
		problems.append("лестнице нужна коробка с сокетами на нижнем уровне и на уровне выше (C_RoomShell.door_sockets)")
	elif floor_stairs.doors_min != sockets.size():
		problems.append("у лестницы дверей %d..%d, а сокетов %d — открыты должны быть все" % [floor_stairs.doors_min, floor_stairs.doors_max, sockets.size()])
	return problems
