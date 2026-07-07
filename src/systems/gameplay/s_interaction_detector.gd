class_name S_InteractionDetector
extends System

var _current_target: Entity = null

func query() -> QueryBuilder:
	return q.with_all([C_Interactable])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	var player := _get_player()
	if player == null:
		return
	var player_node: Node = player
	var player_3d := player_node as Node3D
	if player_3d == null:
		return
	var player_pos: Vector3 = player_3d.global_position

	var best: Entity = null
	var best_dist := INF
	for e in entities:
		var c := e.get_component(C_Interactable) as C_Interactable
		if not c.enabled:
			continue
		var e_node: Node = e
		var e_3d := e_node as Node3D
		if e_3d == null:
			continue
		var d: float = player_pos.distance_to(e_3d.global_position)
		if d <= c.range_cast and d < best_dist:
			best = e
			best_dist = d

	if best != _current_target:
		if _current_target and is_instance_valid(_current_target):
			cmd.remove_component(_current_target, C_Highlighted)
		if best:
			cmd.add_component(best, C_Highlighted.new())
		_current_target = best

func _get_player() -> Entity:
	return q.with_all([C_PlayerInput]).execute_one()
