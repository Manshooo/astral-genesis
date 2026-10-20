# res://src/systems/gameplay/s_void_fall.gd
# Группа "gameplay". Дно мира: провалившееся ниже GameConfig.void_fall_depth убирается. Ради ДЫРОК В ГЕОМЕТРИИ (генерация неизбежно оставит щель): иначе игрок падает вечно.
# Порог — координата, не death box (Area3D тянулась бы за слоями). Душа (C_Lifespan) — СМЕРТЬ: "run_ended" тем же путём, что у S_Lifespan; остальные (враги) просто
# убираются из мира, не через C_Health. Вики: [[Цикл забега]] (Провал сквозь мир).
class_name S_VoidFall
extends System


## Только то, что может ПАДАТЬ (с C_Velocity; тела в комнатах — StaticBody3D). C_Dead исключает: "run_ended" не дважды.
func query() -> QueryBuilder:
	return q.with_all([C_Velocity]).with_none([C_Dead])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	var floor_y := GameConfig.config.void_fall_depth
	for entity in entities:
		# Entity наследует Node — до Node3D двойной каст; вне дерева global_position ругается (один кадр после add_entity).
		var node := entity as Node as Node3D
		if node == null or not node.is_inside_tree():
			continue
		if node.global_position.y > floor_y:
			continue

		var life := entity.get_component(C_Lifespan) as C_Lifespan
		if life:
			_end_run(entity, life)
		else:
			cmd.remove_entity(entity)


## Смерть игрока тем же путём, что догоревший запас: обнулить остаток, пометить мёртвым, объявить конец забега (порядок как S_Lifespan).
## C_Dead — через буфер (правило v9), событие — синхронно, как в S_Health.
func _end_run(entity: Entity, life: C_Lifespan) -> void:
	life.current = 0.0
	cmd.add_component(entity, C_Dead.new())
	ECS.world.emit_event(&"run_ended", entity)
