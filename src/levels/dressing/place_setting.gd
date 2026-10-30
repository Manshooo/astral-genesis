# res://src/levels/dressing/place_setting.gd
# Прибор на подносе за местом стола. В сцене — полный набор, как его видно в редакторе; при спавне RoomDressing
# бросает, что от него останется (RS_PlaceSetting). Правила: напиток один — кружка или стакан; чайная ложка только
# при кружке; плошка — вариант тарелки. Вики: [[Расстановка пропов в комнатах]].
class_name PlaceSetting
extends Node3D

enum State { EMPTY, FULL, TRAY_DRINK, LONE_DRINK, LONE_PLATE }

## Высота предметов над подносом: без подноса они опускаются на стол.
const ON_TRAY := 0.007

@export var table: RS_PlaceSetting


## false — место пустое. Все броски — до решений: их число не зависит от исхода, и правка одного шанса не
## перемешивает остальные.
func dress(rng: RandomNumberGenerator) -> bool:
	var state := roll_state(rng)
	var with_cup := rng.randf() < table.cup_chance
	var with_bowl := rng.randf() < table.deep_bowl_chance
	var with_fork := rng.randf() < table.fork_chance
	var with_spoon := rng.randf() < table.spoon_chance
	var with_tea_spoon := rng.randf() < table.tea_spoon_chance
	var with_knife := rng.randf() < table.knife_chance
	var with_salad := rng.randf() < table.salad_bowl_chance
	var shift := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * table.setting_offset
	var turn := rng.randf_range(-1.0, 1.0) * table.setting_turn
	if state == State.EMPTY:
		return false

	var on_tray := state == State.FULL or state == State.TRAY_DRINK
	var has_plate := state == State.FULL or state == State.LONE_PLATE
	var has_drink := state != State.LONE_PLATE
	var full := state == State.FULL
	var drink_is_cup := with_cup or table.glass == null

	_keep(^"Tray", on_tray)
	_keep(^"Dish", has_plate)
	if has_plate and with_bowl:
		_swap(^"Dish", table.deep_bowl)
	_keep(^"Cup", has_drink)
	if has_drink and not drink_is_cup:
		_swap(^"Cup", table.glass)
	_keep(^"Fork", full and with_fork)
	_keep(^"Spoon", full and with_spoon)
	_keep(^"TeaSpoon", full and drink_is_cup and with_tea_spoon)
	_fill(^"KnifeSlot", table.knife if full and with_knife else null, &"Knife")
	_fill(^"SaladBowlSlot", table.salad_bowl if full and with_salad else null, &"SaladBowl")

	position += shift
	rotate_y(deg_to_rad(turn))
	for item: Node3D in get_children():
		if item.name == &"Tray":
			continue
		if not on_tray:
			item.position.y -= ON_TRAY
		item.position += Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * table.item_offset
		item.rotate_y(deg_to_rad(rng.randf_range(-1.0, 1.0) * table.item_turn))
	return true


## Состояние места по весам RS_PlaceSetting.
func roll_state(rng: RandomNumberGenerator) -> State:
	var weights := PackedFloat32Array([
		table.weight_empty, table.weight_full, table.weight_tray_drink, table.weight_lone_drink, table.weight_lone_plate,
	])
	return rng.rand_weighted(weights) as State


func _keep(path: NodePath, keep: bool) -> void:
	if not keep and has_node(path):
		_drop(get_node(path))


## Вариант встаёт на место нарисованного предмета; нет сцены варианта — остаётся нарисованный.
func _swap(path: NodePath, scene: PackedScene, item_name := &"") -> void:
	if scene == null or not has_node(path):
		return
	var old := get_node(path) as Node3D
	var item := scene.instantiate() as Node3D
	item.transform = old.transform
	_drop(old)
	item.name = item_name if item_name else StringName(String(path))
	add_child(item)


## Слот-маркер заменяется предметом либо снимается: пустой маркер в комнате не нужен.
func _fill(path: NodePath, scene: PackedScene, item_name: StringName) -> void:
	if not has_node(path):
		return
	if scene:
		_swap(path, scene, item_name)
	else:
		_drop(get_node(path))


func _drop(node: Node) -> void:
	remove_child(node)
	node.free()
