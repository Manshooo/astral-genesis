## Ростер врагов по слоям (data/enemy_roster.tres): кто встаёт на маркеры EnemySpawn* и как часто маркер пуст. Бросок — функция
## (сид, слой, узел, маркер), не общий ГСЧ: слой, собранный заново, даёт тех же врагов и ничего не сдвигает, поэтому
## GENERATOR_VERSION не поднимается. Вики: [[Цикл забега]].
class_name RS_EnemyRoster
extends Resource

const PATH := "res://data/enemy_roster.tres"

## Строки ростера; какие действуют на слое — по диапазонам глубин.
@export var entries: Array[RS_EnemyRosterEntry] = []

## Шанс пустого маркера по глубине; глубже последнего — последний.
@export var empty_chance: PackedFloat32Array = PackedFloat32Array([0.5])

static var _cached: RS_EnemyRoster


## Ростер игры: load() при первом обращении (godotengine/godot#100100).
static func current() -> RS_EnemyRoster:
	if _cached == null:
		_cached = load(PATH) as RS_EnemyRoster
	if _cached == null:
		push_warning("RS_EnemyRoster: нет %s — маркеры остаются пустыми" % PATH)
		_cached = RS_EnemyRoster.new()
	return _cached


## Строки, действующие на слое depth.
func entries_at(depth: int) -> Array[RS_EnemyRosterEntry]:
	var found: Array[RS_EnemyRosterEntry] = []
	for entry in entries:
		if entry != null and entry.covers(depth):
			found.append(entry)
	return found


func empty_chance_at(depth: int) -> float:
	if empty_chance.is_empty():
		return 0.0
	return empty_chance[clampi(depth, 0, empty_chance.size() - 1)]


## Враг для маркера узла слоя забега; null — пусто. Детерминированно по входу.
##
## Строки — String, не StringName: хэш Variant от StringName между сборками не обещан.
func roll(run_seed: int, depth: int, node_id: StringName, marker: StringName) -> PackedScene:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, depth, String(node_id), String(marker)])
	# Бросок «пусто или нет» всегда первым и одним числом: порядок не зависит от числа подходящих строк.
	var empty_roll := rng.randf()
	var pick_roll := rng.randf()

	var candidates := entries_at(depth)
	if candidates.is_empty() or empty_roll < empty_chance_at(depth):
		return null

	var total := 0.0
	for entry in candidates:
		total += entry.weight
	var threshold := pick_roll * total
	for entry in candidates:
		threshold -= entry.weight
		if threshold < 0.0:
			return entry.enemy_scene
	return candidates[candidates.size() - 1].enemy_scene


## Что не так с данными (пусто — порядок): слой без строк остался бы без врагов молча.
func validate(depths: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	for depth: int in depths:
		if entries_at(depth).is_empty():
			problems.append("на слое %d нет ни одной строки ростера" % depth)
	for entry in entries:
		if entry == null or entry.enemy_scene == null:
			problems.append("строка ростера без сцены врага")
		elif entry.depth_min > entry.depth_max:
			problems.append("%s: depth_min больше depth_max" % entry.enemy_scene.resource_path)
	for chance in empty_chance:
		if chance < 0.0 or chance > 1.0:
			problems.append("шанс пустого маркера %.2f вне 0..1" % chance)
	return problems
