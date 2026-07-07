class_name S_ApplySkillEffects
extends System

func setup() -> void:
	SkillManager.skill_unlocked.connect(_on_skill_unlocked)

func query() -> QueryBuilder:
	return q.with_all([C_Lifespan, C_BodySnatch])  # игрок

func process(entities, components, delta) -> void:
	pass  # эта система реагирует на сигнал, не на кадр — process_empty можно оставить пустым

func _on_skill_unlocked(id: StringName, rank: int) -> void:
	var player = _get_player_entity()
	match id:
		&"body_snatch":
			player.get_component(C_BodySnatch).capture_range = 2.0 + rank * 0.5
		&"lifespan":
			var c := player.get_component(C_Lifespan)
			c.max_duration = 60.0 + rank * 20.0
