# res://src/observers/o_run_stats.gd
# Мост от событий мира (`body_snatched`, `damage_dealt`) к накопителю RunStats; логики нет — что считать, решает RunStats.
# Один наблюдатель на оба события (sub_observers): меньше узлов в world.tscn и в каждой headless-проверке.
class_name O_RunStats
extends Observer


func sub_observers() -> Array[Array]:
	return [
		[q.with_all([C_BodySnatch, C_Embodied]).on_event(&"body_snatched"), _on_body_snatched],
		[q.with_all([C_Health]).on_event(&"damage_dealt"), _on_damage],
	]


## Захват состоялся. Путь сцены — с души: тела в мире уже нет (см. S_BodySnatch).
func _on_body_snatched(_event: Variant, soul: Entity, _payload: Variant = null) -> void:
	var embodied := soul.get_component(C_Embodied) as C_Embodied
	if embodied:
		RunStats.record_body(embodied.body_scene_path)


func _on_damage(_event: Variant, _target: Entity, payload: Variant = null) -> void:
	if payload is S_Health.Damage:
		RunStats.record_damage(payload as S_Health.Damage)
