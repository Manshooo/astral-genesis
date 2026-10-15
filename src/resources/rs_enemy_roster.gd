## Ростер врагов по слоям — data/enemy_roster.tres: кто встаёт на маркеры
## `EnemySpawn*` в сценах комнат и как часто маркер остаётся пустым
## (карточка «Игровой цикл — от и до», §2 и §10). Состав и вероятности — данные:
## game-balance пересчитывает их, не трогая код спавна.
##
## БРОСОК — функция сида забега, слоя, узла и маркера (roll), а не общий ГСЧ.
## Два следствия, ради которых так: слой, снятый и собранный заново (переход
## порталом туда и обратно), даёт ровно тех же врагов на тех же местах; и бросок
## не сдвигает ничего другого — граф уже построен, а раскладка ламп и прочее
## живёт на своих хэшах (LayerStreamer._is_lamp_dead). Тем же приёмом ростер не
## требует поднять RS_LevelGraph.GENERATOR_VERSION: граф и план не зависят от
## врагов, у того же сида меняется только то, что стоит В комнатах.
class_name RS_EnemyRoster
extends Resource

const PATH := "res://data/enemy_roster.tres"

## Строки ростера. Какие из них действуют на слое, решают их диапазоны глубин.
@export var entries: Array[RS_EnemyRosterEntry] = []

## Шанс, что маркер остаётся пустым; индекс — глубина. Глубже последнего элемента
## действует последний. Шанс по слою, а не один на всех: на поверхности врагов
## должно быть меньше, чем у дна, и это одна строка данных.
@export var empty_chance: PackedFloat32Array = PackedFloat32Array([0.5])

static var _cached: RS_EnemyRoster


## Ростер игры. Грузится load() при первом обращении, а не preload — по той же
## причине, что RS_SoulPointsTable.current (godotengine/godot#100100).
static func current() -> RS_EnemyRoster:
	if _cached == null:
		_cached = load(PATH) as RS_EnemyRoster
	if _cached == null:
		push_warning("RS_EnemyRoster: нет %s — маркеры остаются пустыми" % PATH)
		_cached = RS_EnemyRoster.new()
	return _cached


## Строки, действующие на слое [param depth].
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


## Враг для маркера [param marker] узла [param node_id] слоя [param depth] забега
## [param run_seed]; null — маркер остаётся пустым. Один и тот же вход всегда даёт
## один и тот же ответ.
##
## Строки — String, не StringName: хэш Variant от StringName не обещан совпадать
## между сборками, а от String — обещан (сид забега переживает версию игры).
func roll(run_seed: int, depth: int, node_id: StringName, marker: StringName) -> PackedScene:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, depth, String(node_id), String(marker)])
	# Бросок «пусто или нет» делается ВСЕГДА первым и одним числом: порядок
	# розыгрыша не зависит от того, сколько строк подходит слою.
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


## Что не так с данными (пусто — всё в порядке). Ловит тихие поломки: слой без
## единой строки просто остался бы без врагов, и никто бы не понял почему.
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
