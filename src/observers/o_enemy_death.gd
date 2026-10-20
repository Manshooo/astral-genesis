# res://src/observers/o_enemy_death.gd
# Наблюдатель: смерть врага ставит на его место труп — экземпляр corpse_scene (E_Body), в который можно вселиться. Слушает
# "entity_died" только у сущностей с C_EnemyAI. Подмена откладывается call_deferred: событие идёт синхронно из process()
# S_Health, структурные правки в проходе нельзя (правило v9; как O_ExpelFromBody). Убитые враги в сейв не пишутся и
# возрождаются; исключение — C_BodyOrigin маркера ростера, который наследует труп (съеденный не разыгрывается).
class_name O_EnemyDeath
extends Observer


func query() -> QueryBuilder:
	return q.with_all([C_EnemyAI]).on_event(&"entity_died")


func each(_event: Variant, entity: Entity, _payload: Variant = null) -> void:
	replace_with_corpse.call_deferred(entity)


## Убирает enemy и ставит труп; публичная — проверка зовёт напрямую.
static func replace_with_corpse(enemy: Entity) -> void:
	if not is_instance_valid(enemy) or not is_instance_valid(ECS.world):
		return  # комнату успели снести вместе с врагом

	var node := enemy as Node as Node3D
	var parent := node.get_parent()
	var placement := node.global_transform
	var scene: PackedScene = (enemy as E_Enemy).corpse_scene if enemy is E_Enemy else null
	var origin := enemy.get_component(C_BodyOrigin) as C_BodyOrigin
	var origin_id: StringName = origin.body_id if origin else &""

	ECS.world.remove_entity(enemy)
	if scene == null or parent == null:
		return

	var corpse := scene.instantiate() as Entity
	# Место — ДО add_child и локальным трансформом: рэгдолл трупа стартует в _ready внутри add_child, сдвиг корня после оставил бы труп в начале координат.
	(corpse as Node as Node3D).transform = (parent as Node3D).global_transform.affine_inverse() * placement \
			if parent is Node3D else placement
	# Под ту же комнату: сносится и прячется (reveal_around) вместе с её содержимым.
	parent.add_child(corpse)
	ECS.world.add_entity(corpse)
	if origin_id != &"":
		# Тот же id, что у маркера; читаем ДО снятия врага.
		var inherited := C_BodyOrigin.new()
		inherited.body_id = origin_id
		corpse.add_component(inherited)
	_release_with_room(corpse)


## Труп под комнатой, а LayerStreamer.despawn снимает с мира только записанное при спавне — иначе в архетипах остался бы битый указатель; поглощённый труп уже снят.
static func _release_with_room(corpse: Entity) -> void:
	corpse.tree_exiting.connect(
		func() -> void:
			if is_instance_valid(ECS.world) and ECS.world.entities.has(corpse):
				ECS.world.remove_entity(corpse)
	)
