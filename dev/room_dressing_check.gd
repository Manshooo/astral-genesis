extends "res://dev/check_harness.gd"
## Обстановка комнаты по сиду (RoomDressing, PlaceSetting, PropJitter) на столовой. Ломается молча: два напитка на
## подносе или чайная ложка при стакане не роняют ничего, поднос, свесившийся со стола, висит в воздухе, а
## обстановка, зависящая от чего-то кроме сида, переставляет стулья при каждом входе в слой.
## Зоны перед сокетами и footprint после обстановки сверяет room_shell_check (хозяин этого правила).
##
## Запускать: godot --headless dev/room_dressing_check.tscn

const ROOM := "res://src/levels/procedural/rooms/canteen/canteen_room.tscn"
const SETTING := "res://src/levels/procedural/rooms/canteen/place_setting.tscn"
const SEEDS := 200
const DEPTH := 1
## Допуск на край стола: столешница — двенадцатигранник, её AABB чуть шире вписанного круга.
const TABLE_EDGE := 0.96

var _cup_path := ""
var _dish_path := ""
var _table_data: RS_PlaceSetting


func _ready() -> void:
	var sample := (load(SETTING) as PackedScene).instantiate() as PlaceSetting
	_cup_path = sample.get_node(^"Cup").scene_file_path
	_dish_path = sample.get_node(^"Dish").scene_file_path
	_table_data = sample.table
	sample.free()

	_check_determinism()
	_check_rules()
	_finish()


# --- 1. Обстановка — функция сида ---------------------------------------------


func _check_determinism() -> void:
	var first := _signature(7)
	_check("тот же сид — та же обстановка", first == _signature(7), "")
	_check("другой сид — другая обстановка", first != _signature(8), "")
	_check("другая комната графа — другая обстановка", first != _signature(7, &"other"), "")


## Что осталось в комнате и где: пути узлов обстановки и их трансформы.
func _signature(run_seed: int, node_id := &"room") -> String:
	var room := _dressed(run_seed, node_id)
	var parts: PackedStringArray = []
	for node in room.find_children("*", "Node3D", true, false):
		if node is PlaceSetting or node is PropJitter or node.get_parent() is PlaceSetting:
			parts.append("%s %s" % [room.get_path_to(node), (node as Node3D).transform])
	room.free()
	return "\n".join(parts)


# --- 2. Правила сервировки и места на столе -------------------------------------


func _check_rules() -> void:
	var drinks: Array[String] = []
	var plates: Array[String] = []
	var tea_spoons: Array[String] = []
	var off_table: Array[String] = []
	var seen := {"glass": 0, "cup": 0, "tea_spoon": 0, "empty": 0, "lone": 0, "full": 0, "chair_gone": 0, "chair_kept": 0}
	var settings_total := 0
	var chairs_total := 0
	var glass_path := _table_data.glass.resource_path if _table_data.glass else ""
	var bowl_path := _table_data.deep_bowl.resource_path if _table_data.deep_bowl else ""

	for run_seed in SEEDS:
		var authored := _authored_counts()
		settings_total += authored.x
		chairs_total += authored.y
		var room := _dressed(run_seed)
		var settings := room.find_children("*", "PlaceSetting", true, false)
		seen.empty += authored.x - settings.size()
		var chairs := room.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool: return n is PropJitter)
		seen.chair_kept += chairs.size()
		seen.chair_gone += authored.y - chairs.size()
		for setting: PlaceSetting in settings:
			var tag := "сид %d %s" % [run_seed, room.get_path_to(setting)]
			var paths := setting.get_children().map(func(n: Node) -> String: return n.scene_file_path)
			var cups := paths.count(_cup_path)
			var glasses := paths.count(glass_path) if glass_path else 0
			var has_tea_spoon := setting.has_node(^"TeaSpoon")
			if cups + glasses > 1:
				drinks.append(tag)
			if paths.count(_dish_path) + (paths.count(bowl_path) if bowl_path else 0) > 1:
				plates.append(tag)
			if has_tea_spoon and cups == 0:
				tea_spoons.append(tag)
			seen.cup += cups
			seen.glass += glasses
			seen.tea_spoon += 1 if has_tea_spoon else 0
			if setting.has_node(^"Tray"):
				seen.full += 1
			else:
				seen.lone += 1
			off_table.append_array(_off_table(setting, tag))
		room.free()

	_check("на подносе не больше одного напитка — кружка или стакан", drinks.is_empty(), ", ".join(drinks.slice(0, 5)))
	_check("тарелка одна — плоская или плошка", plates.is_empty(), ", ".join(plates.slice(0, 5)))
	_check("чайная ложка лежит только при кружке", tea_spoons.is_empty(), ", ".join(tea_spoons.slice(0, 5)))
	_check("прибор не свисает со стола и стоит на столешнице", off_table.is_empty(), ", ".join(off_table.slice(0, 5)))
	# Ассерты разнообразия держат остальные: обстановка, которая не срабатывает (сломан вес, не вызван dress),
	# оставила бы нарисованный полный набор, и правила выше прошли бы на нём впустую.
	_check("места бывают пустыми, с подносом и без", seen.empty > 0 and seen.full > 0 and seen.lone > 0, str(seen))
	_check("напиток бывает и кружкой, и стаканом", seen.cup > 0 and (seen.glass > 0 or glass_path == ""), str(seen))
	_check("чайная ложка встречается", seen.tea_spoon > 0, str(seen))
	_check("стулья бывают убраны, но остаются почти все", seen.chair_gone > 0 and seen.chair_kept > seen.chair_gone * 3,
		"%s из %d" % [seen, chairs_total])


## Геометрия прибора — в осях стола: по горизонтали внутри столешницы, по высоте не ниже её верха.
func _off_table(setting: PlaceSetting, tag: String) -> Array[String]:
	var found: Array[String] = []
	var group := setting.get_parent() as Node3D
	var table := group.get_node(^"Table") as Node3D
	var top := _local_aabb(group, table)
	var radius := top.size.x * 0.5 * TABLE_EDGE
	# Углы бокса в осях самого предмета: AABB повёрнутого подноса шире подноса и «свешивается» там, где поднос цел.
	for geometry: GeometryInstance3D in setting.find_children("*", "GeometryInstance3D", true, false):
		var to_group := group.global_transform.affine_inverse() * geometry.global_transform
		for i in 8:
			var corner := to_group * geometry.get_aabb().get_endpoint(i)
			if Vector2(corner.x, corner.z).length() > radius or corner.y < top.end.y - 0.01:
				found.append("%s/%s" % [tag, geometry.name])
				break
	return found


## AABB геометрии (или всего поддерева) в осях узла space.
func _local_aabb(space: Node3D, node: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var items: Array = [node] if node is GeometryInstance3D else node.find_children("*", "GeometryInstance3D", true, false)
	for item: GeometryInstance3D in items:
		var box := space.global_transform.affine_inverse() * item.global_transform * item.get_aabb()
		merged = box if first else merged.merge(box)
		first = false
	return merged


## Сколько в нарисованной комнате мест и стульев, которым позволено исчезнуть.
func _authored_counts() -> Vector2i:
	var room := (load(ROOM) as PackedScene).instantiate()
	var nodes := room.find_children("*", "Node3D", true, false)
	var counts := Vector2i(nodes.filter(func(n: Node) -> bool: return n is PlaceSetting).size(),
		nodes.filter(func(n: Node) -> bool: return n is PropJitter).size())
	room.free()
	return counts


func _dressed(run_seed: int, node_id := &"room") -> Node3D:
	var room := (load(ROOM) as PackedScene).instantiate() as Node3D
	add_child(room)
	RoomDressing.dress_room(room, node_id, DEPTH, run_seed)
	return room
