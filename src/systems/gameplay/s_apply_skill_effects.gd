class_name O_ApplySkillEffects
extends Observer

func setup() -> void:
	SkillManager.skill_unlocked.connect(
		func(id, rank): ECS.world.emit_event(&"skill_unlocked", null, {"id": id, "rank": rank})
	)

func query() -> QueryBuilder:
	return q.with_all([C_Lifespan, C_BodySnatch]).on_event(&"skill_unlocked")

# payload — Dictionary {"id", "rank"} из setup(). Читаем по ключу: Dictionary в
# GDScript 4 не поддерживает dot-доступ (data.id упал бы в рантайме).
func each(_event, entity: Entity, data = null) -> void:
	var id: StringName = data.get("id", &"")
	var rank: int = data.get("rank", 0)
	match id:
		&"body_snatch":
			var c := entity.get_component(C_BodySnatch) as C_BodySnatch
			if c:
				c.capture_range = 2.0 + rank * 0.5
		&"lifespan":
			var c := entity.get_component(C_Lifespan) as C_Lifespan
			if c:
				c.max_duration = 60.0 + rank * 20.0
