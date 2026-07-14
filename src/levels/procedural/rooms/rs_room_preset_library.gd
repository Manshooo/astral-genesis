## res://src/levels/procedural/rooms/rs_room_preset_library.gd
## Библиотека пресетов комнат + селектор (см. ADR-0003). Генератор на финальном
## проходе зовёт select_preset() для каждого узла, когда его connections уже
## полностью проставлены, и подставляет узлу сцену комнаты.
##
## Критерии подбора:
##   1. Вместимость (жёстко): preset.slot_count >= node.connections.size().
##   2. Теги (жёстко): node.tags ⊆ preset.tags.
##   3. Специфичность (мягко): среди кандидатов — с минимумом лишних тегов,
##      затем взвешенный рандом. Не даёт «богатым» пресетам (напр. с порталом)
##      протекать в узлы, которым это не нужно.
class_name RS_RoomPresetLibrary
extends Resource

@export var presets: Array[RS_RoomPreset] = []

## Запасной пресет, когда ни один не подошёл (напр. у узла рёбер больше, чем
## слотов у любой комнаты). Может быть null — тогда select_preset вернёт null и
## генератор оставит узлу заранее проставленный placeholder.
@export var fallback: RS_RoomPreset


## Возвращает подходящий пресет для узла или fallback/null. rng должен быть тем
## же, что и во всей генерации, — иначе подстановка перестанет быть
## детерминированной по сиду.
func select_preset(node: RS_LevelNode, rng: RandomNumberGenerator) -> RS_RoomPreset:
	var needed := node.connections.size()
	var candidates := presets.filter(
		func(p: RS_RoomPreset) -> bool:
			return p != null and p.scene != null \
				and p.slot_count >= needed and _tags_cover(p.tags, node.tags)
	)
	if candidates.is_empty():
		push_warning(
			"RS_RoomPresetLibrary: нет пресета для узла '%s' (рёбер=%d, теги=%s) — fallback"
			% [node.id, needed, str(node.tags)]
		)
		return fallback

	# Специфичность: меньше всего лишних тегов сверх требуемых узлом.
	# node.tags ⊆ p.tags гарантировано фильтром, теги уникальны → лишних = разница размеров.
	# Инициализация от первого кандидата (список непустой), а не от 0/size — иначе
	# для узла без тегов min_extra залипнет на 0 и best может оказаться пустым.
	var min_extra: int = candidates[0].tags.size() - node.tags.size()
	for p in candidates:
		min_extra = min(min_extra, p.tags.size() - node.tags.size())
	var best := candidates.filter(
		func(p: RS_RoomPreset) -> bool: return p.tags.size() - node.tags.size() == min_extra
	)

	return _weighted_pick(best, rng)


## Каждый тег узла должен присутствовать в тегах пресета (node ⊆ preset).
func _tags_cover(preset_tags: Array, node_tags: Array) -> bool:
	for t in node_tags:
		if not preset_tags.has(t):
			return false
	return true


func _weighted_pick(pool: Array, rng: RandomNumberGenerator) -> RS_RoomPreset:
	var total := 0.0
	for p in pool:
		total += maxf(p.weight, 0.0)
	if total <= 0.0:  # все веса нулевые — равновероятно
		return pool[rng.randi_range(0, pool.size() - 1)]

	var roll := rng.randf() * total
	var acc := 0.0
	for p in pool:
		acc += maxf(p.weight, 0.0)
		if roll <= acc:
			return p
	return pool[pool.size() - 1]


## Отладочная проверка: сверяет заявленный slot_count каждого пресета с
## фактическим числом C_DoorSlot в сцене (инстанцирует и считает). Возвращает
## список расхождений — пусто, если всё сходится. Зовите из теста/дебага, не в
## горячем пути генерации.
func validate() -> Array[String]:
	var problems: Array[String] = []
	for p in presets:
		if p == null:
			problems.append("null-пресет в списке")
			continue
		if p.scene == null:
			problems.append("'%s': не назначена scene" % p.display_name)
			continue
		var inst := p.scene.instantiate()
		var actual := inst.find_children("*", "Entity", true, false).filter(
			func(n): return _has_door_slot(n)
		).size()
		inst.free()
		if actual != p.slot_count:
			problems.append(
				"'%s': slot_count=%d, но в сцене %d слотов C_DoorSlot"
				% [p.display_name, p.slot_count, actual]
			)
	return problems


## Есть ли на сущности слот двери. Проверяем И has_component (когда сущность в
## дереве и её _ready уже отработал), И component_resources (когда сцена
## инстанцирована detached — тогда _ready не звался и компоненты ещё «не разложены»).
func _has_door_slot(n: Node) -> bool:
	if not (n is Entity):
		return false
	var e := n as Entity
	if e.has_component(C_DoorSlot):
		return true
	for c in e.component_resources:
		if c is C_DoorSlot:
			return true
	return false
