# res://src/observers/o_expel_from_body.gd
# Наблюдатель: смерть ЗАХВАЧЕННОГО тела выбрасывает БФЖ в призрака, а не завершает забег ("entity_died" для C_Embodied).
# S_Health вешает C_Dead отложенно, а событие шлёт синхронно — развоплощение откладываем call_deferred, иначе душа залипла бы мёртвой.
class_name O_ExpelFromBody
extends Observer

## Порог выжатости тела, с которого добровольный выход даёт очко навыка (_settle_lifespan); фармить повторным входом нельзя — тело поглощено.
const _GRACEFUL_EXIT_DECAY_THRESHOLD := 0.5


func query() -> QueryBuilder:
	return q.with_all([C_Embodied]).on_event(&"entity_died")


func each(_event: Variant, entity: Entity, _payload: Variant = null) -> void:
	expel.call_deferred(entity, false)


## Развоплощение: снять «во плоти», характеристики тела и тег смерти; облик и форму вернут O_BodyVisual и O_BodyForm.
## voluntary различает три пути с разным правилом распада: гибель тела и конец времени (S_Lifespan) — false, выход игрока
## (S_BodySnatch) — true. Логика в одном месте, иначе три модели распада.
static func expel(soul: Entity, voluntary: bool) -> void:
	if not is_instance_valid(soul):
		return
	if not soul.has_component(C_Embodied):
		return  # уже вышли другим путём в этом же кадре

	_settle_lifespan(soul, voluntary)
	var exit := _exit_of(soul, voluntary)
	_shed_inertia(soul)

	# Снимаем ВСЕ характеристики, не перечисляя: тем же правилом E_Body.is_wearable, каким надевает S_BodySnatch.
	for component in E_Body.worn_by(soul):
		soul.remove_component(component)

	if soul.has_component(C_Dead):
		soul.remove_component(C_Dead)
	if soul.has_component(C_BodyVisual):
		soul.remove_component(C_BodyVisual)
	# Габарит и уровень глаз возвращает O_BodyForm по снятию — как и облик.
	if soul.has_component(C_BodyForm):
		soul.remove_component(C_BodyForm)
	soul.remove_component(C_Embodied)
	ECS.world.emit_event(&"expelled_from_body", soul, exit)

	# Контрольная точка на выходе (как при входе, S_BodySnatch._embody): expel зовётся отложенно, вне буфера.
	RunManager.save_progress()


## Что бросила душа — для эффекта выхода (O_SoulExit): сцена тела, его место подошвой на полу и скорость рига.
## Снимается ДО снятия формы и C_Embodied: после них путь сцены потерян, а foot_offset() ответил бы призрачной сферой.
static func _exit_of(soul: Entity, voluntary: bool) -> Dictionary:
	var embodied := soul.get_component(C_Embodied) as C_Embodied
	var velocity := soul.get_component(C_Velocity) as C_Velocity
	var placement := Transform3D.IDENTITY
	var rig := soul as Node as Node3D
	if rig != null:
		var sole := (soul as E_Player).foot_offset() if soul is E_Player else Vector3.ZERO
		placement = Transform3D(rig.global_basis, rig.global_position - sole)
	return {
		"body_scene_path": embodied.body_scene_path if embodied else "",
		"placement": placement,
		"velocity": velocity.velocity if velocity else Vector3.ZERO,
		"voluntary": voluntary,
		"pose": _worn_pose(soul),
	}


## Поза надетого тела в миг выхода — с его скелета, если меш облика к скелету привязан: брошенное тело продолжит
## из неё, а не из позы покоя. Пока риг носит один меш без скелета — пусто ([[Переработка тел — анимации, вид из тела, рэгдолл]]).
static func _worn_pose(soul: Entity) -> Dictionary:
	var slot := RS_EntityVisuals.primary(soul) as MeshInstance3D
	if slot == null or slot.skeleton.is_empty():
		return {}
	var skeleton := slot.get_node_or_null(slot.skeleton) as Skeleton3D
	if skeleton == null:
		return {}
	var pose := {}
	for bone in skeleton.get_bone_count():
		pose[skeleton.get_bone_name(bone)] = skeleton.get_bone_pose(bone)
	return pose


## Разгон принадлежал телу: оно и уходит по инерции (O_SoulExit), а у души нет массы — она уносит лишь долю
## скорости (C_SoulCloud.exit_inertia). Скорость тела для эффекта снята раньше, в _exit_of.
static func _shed_inertia(soul: Entity) -> void:
	var velocity := soul.get_component(C_Velocity) as C_Velocity
	var cloud := soul.get_component(C_SoulCloud) as C_SoulCloud
	if velocity != null and cloud != null:
		velocity.velocity *= cloud.exit_inertia


## Куда девается остаток запаса тела (модель «распад как ресурс»): вышел сам — прибавляется к запасу души, выше максимума,
## излишек утекает быстрее (S_Lifespan); тело погибло — малая доля (GameConfig.lifespan_death_fraction), больнее добровольного.
static func _settle_lifespan(soul: Entity, voluntary: bool) -> void:
	var life := soul.get_component(C_Lifespan) as C_Lifespan
	if life == null:
		return

	if voluntary:
		var decay := soul.get_component(C_BodyDecay) as C_BodyDecay
		if decay:
			# База 1.0 — весь остаток; стат — чтобы «+10% к времени после выхода» был модификатором.
			var gain := C_StatModifiers.of(soul, C_StatModifiers.LEAVE_BODY_GAIN, 1.0)
			life.current += decay.remaining * gain

			var used_fraction := 1.0 - decay.remaining / decay.effective_maximum(soul)
			if used_fraction >= _GRACEFUL_EXIT_DECAY_THRESHOLD:
				# Бонус за сознание, усвоенное целиком, — на шкале очков за захват (RS_SoulPointsTable), с источником в сводке.
				RunStats.award_soul_points(
					RS_RunStats.POINTS_CLEAN_EXIT, RS_SoulPointsTable.current().clean_exit_points
				)
				# Поглощение — тот же чистый выход (решение 22.10): способности тела остаются душе до конца забега.
				absorb_abilities(soul)
			elif _wears_abilities(soul):
				C_ScreenMessage.show_on(soul, "HUD_MSG_ABSORB_UNRIPE")
	else:
		var keep := C_StatModifiers.of(
			soul, C_StatModifiers.DEATH_KEEP, GameConfig.config.lifespan_death_fraction
		)
		life.current = minf(life.current, life.effective_max(soul) * keep)


## Способности надетого тела — душе: в открытый слот, в банк или в очередь выбора (полный банк спрашивает экран, UIManager). Зовётся до снятия трейтов.
static func absorb_abilities(soul: Entity) -> void:
	var loadout := soul.get_component(C_AbilityLoadout) as C_AbilityLoadout
	if loadout == null:
		return
	var embodied := soul.get_component(C_Embodied) as C_Embodied
	var source := E_Body.name_key_of_scene(embodied.body_scene_path) if embodied else &""
	var message := ""
	for component in E_Body.worn_by(soul):
		var ability := component as C_Ability
		if ability == null:
			continue
		match loadout.absorb(soul, ability, source):
			C_AbilityLoadout.Placement.SLOT:
				message = tr_line("HUD_MSG_ABILITY_ABSORBED", ability)
			C_AbilityLoadout.Placement.BANK:
				message = tr_line("HUD_MSG_ABILITY_BANKED", ability)
	if message != "":
		C_ScreenMessage.show_on(soul, message)


## Надето ли тело со способностями: ранний выход стоит объяснить, а бессильное тело — нет.
static func _wears_abilities(soul: Entity) -> bool:
	for component in E_Body.worn_by(soul):
		if component is C_Ability:
			return true
	return false


## Строка сообщения с именем способности: подстановка уже переведённым именем («HUD — спека» §12).
static func tr_line(key: String, ability: C_Ability) -> String:
	return TranslationServer.translate(key) % TranslationServer.translate(ability.name_key)
