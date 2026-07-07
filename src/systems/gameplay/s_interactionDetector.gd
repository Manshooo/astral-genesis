class_name S_InteractionDetector
extends System

var _current_target: Entity = null

func query() -> QueryBuilder:
	return q.with_all([C_Interactable])

func process(entities: Array[Entity], components: Array, delta: float) -> void:
	var player := _get_player()
	if player == null:
		return
	var best: Entity = null
	var best_dist := INF
	for e in entities:
		var c := e.get_component(C_Interactable)
		if not c.enabled:
			continue
		var d := player.global_position.distance_to(e.global_position)
		if d <= c.range and d < best_dist:
			best = e
			best_dist = d

	if best != _current_target:
		if _current_target and is_instance_valid(_current_target):
			cmd.remove_component(_current_target, C_Highlighted)
		if best:
			cmd.add_component(best, C_Highlighted.new())
		_current_target = best
		# Прокинуть в HUD текст подсказки ("E — Прокачать") через сигнал/автозагрузку
