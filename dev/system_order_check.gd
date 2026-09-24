extends "res://dev/check_harness.gd"
## Проверка порядка систем в том виде, в каком его получает ИГРА: настоящий
## world.tscn, та же топосортировка GECS (ArrayExtensions.topological_sort), что
## зовёт World.initialize(), — и ассерты на порядок, от которого зависит механика.
##
## Порядок в сцене здесь ничего не гарантирует. Сортировка по Кану ставит систему
## с входящей зависимостью в КОНЕЦ очереди: S_Walk (после S_Sprint и S_EnemyAI) и
## S_Jump (после S_Gravity) уезжали за S_Movement, и ход с прыжком доезжали до
## тела на тик позже. Остальные проверки собирали системы списком без сортировки
## и видели другой порядок, чем игра, — поэтому порядок сверяется отдельно и по
## самой сцене.
##
## Заодно сверяется раскладка: папка системы — это её группа. Система в
## systems/gameplay/, живущая в "physics" (так лежали S_BodySnatch и
## S_InteractionDetector), — ловушка: кто возьмёт её за образец, положит свой
## рейкаст в "gameplay", а там запрос к space-state небезопасен (Jolt на своём
## потоке).
## Запускать: godot --headless dev/system_order_check.tscn

const WORLD_SCENE := "res://src/world/world.tscn"
const SYSTEMS_DIR := "res://src/systems/"
const OBSERVERS_DIR := "res://src/observers/"

## Кто готовит перемещение: пишет скорость (ход, прыжок, полёт, гравитация, ИИ) или
## маску коллизий (S_Phasing) — всё это move_and_slide() обязан увидеть в этом же тике.
const BEFORE_MOVEMENT := [
	"S_Phasing", "S_Gravity", "S_EnemyAI", "S_Sprint", "S_Walk", "S_Jump", "S_Flight",
]
## Кто кастует луч от камеры — и потому обязан идти после перемещения.
const CAMERA_RAYS := ["S_InteractionDetector", "S_SnatchTargetDetector"]


func _ready() -> void:
	var main := (load(WORLD_SCENE) as PackedScene).instantiate()
	var systems_root := main.get_node("World/Systems")

	var by_group := _collect_systems(systems_root)
	_check_layout(systems_root, by_group)

	ArrayExtensions.topological_sort(by_group)
	var physics := _names(by_group.get("physics", []))
	print("  порядок physics: %s" % " → ".join(physics))
	_check_physics_order(physics)

	main.free()
	_finish()


## Системы по группам в порядке сцены — ровно то, что собирает
## World.initialize(). Группа — имя SystemGroup-родителя: в дерево сцена не
## добавлена, и SystemGroup ещё не проставил System.group сам.
func _collect_systems(systems_root: Node) -> Dictionary:
	var by_group := {}
	for group_node in systems_root.get_children():
		if group_node is System or group_node is Observer:
			continue
		for child in group_node.get_children():
			if child is System:
				var system := child as System
				system.group = group_node.name
				if not by_group.has(system.group):
					by_group[system.group] = []
				by_group[system.group].append(system)
	return by_group


func _check_layout(systems_root: Node, by_group: Dictionary) -> void:
	var misplaced: Array[String] = []
	for group: String in by_group:
		for system: System in by_group[group]:
			var path := (system.get_script() as Script).resource_path
			if not path.begins_with("%s%s/" % [SYSTEMS_DIR, group]):
				misplaced.append("%s в группе %s лежит в %s" % [system.name, group, path])
	_check("папка системы совпадает с её группой", misplaced.is_empty(), ", ".join(misplaced))

	var stray: Array[String] = []
	for child in systems_root.get_children():
		if child is Observer:
			var path := (child.get_script() as Script).resource_path
			if not path.begins_with(OBSERVERS_DIR):
				stray.append("%s лежит в %s" % [child.name, path])
	_check("наблюдатели лежат в src/observers/", stray.is_empty(), ", ".join(stray))


func _check_physics_order(order: Array[String]) -> void:
	var movement := order.find("S_Movement")
	_check("S_Movement есть в группе physics", movement >= 0, str(order))
	if movement < 0:
		return

	var late: Array[String] = []
	for writer: String in BEFORE_MOVEMENT:
		var at := order.find(writer)
		if at < 0 or at > movement:
			late.append(writer)
	_check(
		"всё, что готовит перемещение, идёт до S_Movement",
		late.is_empty(),
		"после S_Movement или нет в группе: %s" % ", ".join(late)
	)

	var early: Array[String] = []
	for ray: String in CAMERA_RAYS:
		var at := order.find(ray)
		if at < 0 or at < movement:
			early.append(ray)
	_check(
		"лучи от камеры кастуются после перемещения",
		early.is_empty(),
		"до S_Movement или нет в группе: %s" % ", ".join(early)
	)

	_check_before(order, "S_Gravity", "S_Jump")
	_check_before(order, "S_Sprint", "S_Walk")
	_check_before(order, "S_EnemyAI", "S_Walk")
	_check_before(order, "S_SnatchTargetDetector", "S_BodySnatch")


func _check_before(order: Array[String], first: String, second: String) -> void:
	var a := order.find(first)
	var b := order.find(second)
	_check("%s до %s" % [first, second], a >= 0 and b >= 0 and a < b, "%d / %d" % [a, b])


func _names(systems: Array) -> Array[String]:
	var result: Array[String] = []
	for system: System in systems:
		result.append(String(system.name))
	return result
