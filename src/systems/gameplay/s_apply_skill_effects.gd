class_name S_ApplySkillEffects
extends System

func setup() -> void:
	SkillManager.skill_unlocked.connect(_on_skill_unlocked)

func query() -> QueryBuilder:
	return q.with_all([C_Lifespan, C_BodySnatch])  # игрок

func process(_entities: Array[Entity], _components: Array, _delta: float) -> void:
	pass  # реагирует на сигнал, а не на кадр

func _on_skill_unlocked(id: StringName, rank: int) -> void:
	var player := _get_player_entity()
	if player == null:
		return
	match id:
		&"body_snatch":
			var c := player.get_component(C_BodySnatch) as C_BodySnatch
			if c:
				c.capture_range = 2.0 + rank * 0.5
		&"lifespan":
			var c := player.get_component(C_Lifespan) as C_Lifespan
			if c:
				c.max_duration = 60.0 + rank * 20.0

func _get_player_entity() -> Entity:
	return q.with_all([C_Lifespan, C_BodySnatch]).execute_one()
