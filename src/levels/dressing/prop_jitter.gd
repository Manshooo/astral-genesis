# res://src/levels/dressing/prop_jitter.gd
# Проп, которому позволено отойти от нарисованного места (стул у стола): RoomDressing при спавне сдвигает его в
# пределах RS_PropJitter, отодвигает назад или убирает. Вешается на корень пропа в сцене комнаты. Вики: [[Расстановка пропов в комнатах]].
class_name PropJitter
extends Node3D

@export var jitter: RS_PropJitter


## false — пропа на этом месте нет. Все броски — до решений: их число не зависит от исхода, и правка шанса не
## перемешивает сдвиги.
func dress(rng: RandomNumberGenerator) -> bool:
	var missing := rng.randf() < jitter.missing_chance
	var pushed := rng.randf() < jitter.pushed_chance
	var shift := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * jitter.offset
	var turn := rng.randf_range(-1.0, 1.0) * jitter.turn
	var push_turn := rng.randf_range(-1.0, 1.0) * jitter.push_turn
	if missing:
		return false
	if pushed:
		shift -= basis.z.normalized() * jitter.push_distance
		turn += push_turn
	position += shift
	rotate_y(deg_to_rad(turn))
	return true
