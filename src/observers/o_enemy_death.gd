# res://src/observers/o_enemy_death.gd
# Наблюдатель: смерть врага превращает его в тело, в которое можно вселиться.
# Слушает "entity_died" (шлёт S_Health при HP<=0) только для сущностей с
# C_EnemyAI — гибель игрока и захваченного тела идёт своим путём
# (O_ExpelFromBody, O_RunEnded), а у них C_EnemyAI нет.
#
# ВРАГ ПОДМЕНЯЕТСЯ ТРУПОМ, а не «превращается»: у живого врага корень —
# CharacterBody3D со своим ИИ, у трупа — StaticBody3D-E_Body с набором
# характеристик для захвата, и снимать с одного узла одно, ставя другое,
# значило бы спорить с сущностью, у которой скрипт и тип корня уже другие.
# Поэтому на место врага встаёт экземпляр его corpse_scene — настоящий E_Body, а
# сам враг убирается. Тело получает свежее полное здоровье «даром»: оно
# читается из component_resources сцены трупа, а не копируется с умершего.
#
# Порядок кадра (важно): событие приходит СИНХРОННО из process() S_Health, а
# C_Dead он вешает через свой буфер команд. Убирать сущность и добавлять новую
# прямо здесь нельзя — Правило v9 (структурные правки в проходе системы
# пропускают соседей по архетипу). Поэтому подмена откладывается call_deferred —
# тем же приёмом, что у O_ExpelFromBody.
#
# Состояние убитых врагов в сейв НЕ пишется: комплекс восстанавливается из сида
# покомнатно-заново, и враг, убитый до сохранения, после загрузки возродится на
# месте. Исключение одно и частичное: враг с маркера ростера несёт C_BodyOrigin
# (id маркера), и труп наследует его — съеденный захватом труп попадает в
# consumed_body_ids, и маркер перестаёт разыгрываться. Убитый, но не съеденный
# враг по-прежнему возродится. Хвост задачи «Бой — начало».
class_name O_EnemyDeath
extends Observer


func query() -> QueryBuilder:
	return q.with_all([C_EnemyAI]).on_event(&"entity_died")


func each(_event: Variant, entity: Entity, _payload: Variant = null) -> void:
	replace_with_corpse.call_deferred(entity)


## Убирает [param enemy] из мира и ставит на его место труп. Статическая и
## публичная — проверка зовёт её напрямую, не дожидаясь отложенного вызова.
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
	# Место — ДО add_child, и локальным трансформом: глобальный у узла вне дерева
	# не задать. Рэгдолл трупа стартует в его _ready, то есть внутри add_child, и
	# кости симуляции — тела в мировом пространстве: сдвинь корень после, и
	# коллайдер захвата уедет на место смерти, а сам труп останется лежать там,
	# где корень был в момент старта, — в начале координат комнаты.
	(corpse as Node as Node3D).transform = (parent as Node3D).global_transform.affine_inverse() * placement \
			if parent is Node3D else placement
	# Под ту же комнату, что и враг: сносится она вместе с комнатой, и
	# reveal_around прячет труп вместе с остальным содержимым комнаты (прячутся
	# все Node3D, кроме CharacterBody3D, а труп — StaticBody3D).
	parent.add_child(corpse)
	ECS.world.add_entity(corpse)
	if origin_id != &"":
		# Тот же id, что у маркера, — см. шапку. Читаем его ДО снятия врага с мира.
		var inherited := C_BodyOrigin.new()
		inherited.body_id = origin_id
		corpse.add_component(inherited)
	_release_with_room(corpse)


## Труп живёт под комнатой, а LayerStreamer.despawn снимает с мира только то, что
## записал при её спавне, — трупа в списке нет. Освободись комната вместе с ним,
## и в архетипах мира остался бы битый указатель. Поэтому при выходе узла из
## дерева сами снимаем сущность с мира, если она ещё там (поглощённый захватом
## труп уже снят, и повторное снятие ругалось бы).
static func _release_with_room(corpse: Entity) -> void:
	corpse.tree_exiting.connect(
		func() -> void:
			if is_instance_valid(ECS.world) and ECS.world.entities.has(corpse):
				ECS.world.remove_entity(corpse)
	)
