# res://src/world/layer_finds.gd
# Находки эссенции в мире: расстановка при спавне слоя и взятие (карточка «Источники эссенции»). Отдельно от LayerStreamer: ему находки нужны в двух местах, а здесь всё, что нужно проверке без мира.
# Бросок от hash([сид, слой, ключ]), не от общего rng: лишний бросок в нём сдвинул бы граф (и потребовал GENERATOR_VERSION); как погасшие лампы (LayerStreamer._is_lamp_dead). Вики: [[Цикл забега]].
class_name LayerFinds
extends RefCounted

const FIND_SCENE := preload("res://src/entities/essence_find/e_essence_find.tscn")

## Маркеры в сценах комнат: Marker3D с таким именем — место для находки (в тех же сценах ещё точки врагов).
const SPOT_PATTERN := "EssenceSpot*"


## Ключ отметки находки в комнате: узел плюс путь маркера (сцена одна на много комнат).
static func room_key(node_id: StringName, spot_path: NodePath) -> StringName:
	return StringName("%s#find:%s" % [node_id, spot_path])


## Ключ отметки тайника: узел-коридор и клетка тупика (порядок тупиков в плане не обещан).
static func cache_key(node_id: StringName, cell: Vector3i) -> StringName:
	return StringName("%s#cache:%d:%d:%d" % [node_id, cell.x, cell.y, cell.z])


## Номинал находки с ключом key: 0 — в этом месте её нет. Функция от (сид, слой, ключ), без состояния — детерминизм проверяется прямым вызовом.
static func roll(run_seed: int, depth: int, key: StringName, chance: float, lo: int, hi: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, depth, String(key)])
	# Сумма разыгрывается ДО шанса: правка шанса не перемешивает суммы остальных.
	var amount := rng.randi_range(mini(lo, hi), maxi(lo, hi))
	return amount if rng.randf() < chance else 0


## Расставляет находки по маркерам комнаты ДО add_entity: они становятся её дочерними (LayerStreamer._register_room_children) и уходят со сносом. Взятые в забеге не ставятся (отметка в сейве).
static func place_in_room(room: Entity, node_data: RS_LevelNode, run_seed: int) -> void:
	var config := GameConfig.config
	for marker in room.find_children(SPOT_PATTERN, "Marker3D", true, false):
		var key := room_key(node_data.id, room.get_path_to(marker))
		if WorldSave.is_node_reward_claimed(key):
			continue
		var amount := roll(
			run_seed, node_data.depth, key,
			config.essence_find_chance, config.essence_find_min, config.essence_find_max
		)
		if amount <= 0:
			continue
		var find := _make(key, RS_RunStats.ESSENCE_PICKUP, amount)
		find.name = "EssenceFind_%s" % marker.name
		room.add_child(find)
		(find as Node as Node3D).position = _local_origin(marker as Node3D, room)


## Ставит тайники в тупики коридора и возвращает их — стример снимает их при сносе слоя (у тайлов нет сущности-хозяина). Тупики — RS_LayerPlan.dead_ends.
static func place_caches(node_data: RS_LevelNode, plan: RS_LayerPlan, run_seed: int) -> Array[Entity]:
	var placed: Array[Entity] = []
	var config := GameConfig.config
	for cell: Vector3i in plan.dead_ends:
		if plan.node_by_cell.get(cell, &"") != node_data.id:
			continue
		var key := cache_key(node_data.id, cell)
		if WorldSave.is_node_reward_claimed(key):
			continue
		var amount := roll(
			run_seed, node_data.depth, key,
			config.essence_cache_chance, config.essence_cache_min, config.essence_cache_max
		)
		if amount <= 0:
			continue
		var find := _make(key, RS_RunStats.ESSENCE_CACHE, amount)
		find.name = "EssenceCache_%d_%d_%d" % [cell.x, cell.y, cell.z]
		# Позиция ДО входа в мир: иначе коллайдер зарегистрируется в начале координат.
		(find as Node as Node3D).position = plan.embedding.cell_origin(cell)
		ECS.world.add_entity(find)
		placed.append(find)
	return placed


## Снимает тайники слоя; невалидные пропускаются (взятая уже освобождена).
static func remove_all(finds: Array[Entity]) -> void:
	var alive: Array[Entity] = []
	for find in finds:
		if is_instance_valid(find):
			alive.append(find)
	if not alive.is_empty() and ECS.world:
		ECS.world.remove_entities(alive)
	finds.clear()


## Взять находку: отметка ДО выдачи (как WorldSave.claim_node_reward), иначе выход в меню между ними дал бы вторую награду. Возвращает выданное; 0 — уже брали или не расставлена.
static func claim(key: StringName, source: StringName, amount: int) -> int:
	if key == &"" or amount <= 0 or not WorldSave.claim_node_reward(key):
		return 0
	var granted := maxi(1, roundi(amount * gain()))
	RunStats.award_essence(source, granted)
	return granted


## Доля номинала, которую берёт душа: вычисленный стат (навык «Сбор эссенции» — модификатор), база в конфиге; без души читается база.
static func gain() -> float:
	return maxf(
		0.0,
		C_StatModifiers.of(
			E_Player.find(), C_StatModifiers.ESSENCE_GAIN, GameConfig.config.essence_gain_base
		)
	)


static func _make(key: StringName, source: StringName, amount: int) -> E_EssenceFind:
	var find := FIND_SCENE.instantiate() as E_EssenceFind
	find.claim_key = key
	find.source = source
	find.amount = amount
	return find


## Положение узла в системе координат root по цепочке родителей: до входа в дерево global_transform недоступен.
static func _local_origin(node: Node3D, root: Node) -> Vector3:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform.origin
