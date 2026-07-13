class_name O_ApplySkillEffects
extends Observer

func setup() -> void:
	SkillManager.skill_unlocked.connect(
		func(id, rank): ECS.world.emit_event(&"skill_unlocked", null, {"id": id, "rank": rank})
	)

func query() -> QueryBuilder:
	return q.with_all([C_Lifespan, C_BodySnatch]).on_event(&"skill_unlocked")

func each(_event, entity: Entity, data: RS_SkillDefinition) -> void:
	match data.id:
		&"body_snatch":
			var c := entity.get_component(C_BodySnatch) as C_BodySnatch
			if c:
				c.capture_range = 2.0 + data.rank * 0.5
		&"lifespan":
			var c := entity.get_component(C_Lifespan) as C_Lifespan
			if c:
				c.max_duration = 60.0 + data.rank * 20.0
