# res://src/observers/o_run_stats.gd
# Мост от событий мира к накопителю статистики забега (автолоад RunStats).
#
# Наблюдатель, а не подписка автолоада на сигналы: захват тела и урон живут
# событиями ECS (`body_snatched`, `damage_dealt`), а подписаться на них можно
# только отсюда. Логики здесь нет намеренно — что считать показателем, решает
# RunStats; этот файл только доносит событие живым.
#
# Один наблюдатель на оба события (sub_observers), а не два узла в мире: ось
# реакции разная, а адресат один, и регистрировать в world.tscn (и в каждой
# headless-проверке) две ноды вместо одной — лишний повод забыть половину.
class_name O_RunStats
extends Observer


func sub_observers() -> Array[Array]:
	return [
		[q.with_all([C_BodySnatch, C_Embodied]).on_event(&"body_snatched"), _on_body_snatched],
		[q.with_all([C_Health]).on_event(&"damage_dealt"), _on_damage],
	]


## Захват состоялся. Путь сцены читаем с души, а не с тела: тела к этому моменту
## в мире уже нет — захват его поглотил (см. S_BodySnatch про буфер команд).
func _on_body_snatched(_event: Variant, soul: Entity, _payload: Variant = null) -> void:
	var embodied := soul.get_component(C_Embodied) as C_Embodied
	if embodied:
		RunStats.record_body(embodied.body_scene_path)


func _on_damage(_event: Variant, _target: Entity, payload: Variant = null) -> void:
	if payload is S_Health.Damage:
		RunStats.record_damage(payload as S_Health.Damage)
