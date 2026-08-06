# res://src/systems/gameplay/s_body_snatch.gd
# Группа: "physics" — рядом с S_SnatchTargetDetector, чья метка нужна ему в том
# же физкадре.
# Ядро игры — захват тела. По запросу захвата (действие "snatch_body", по умолчанию
# ЛКМ; E_Player._input ставит C_BodySnatch.capture_requested) берёт тело, помеченное
# C_SnatchTargeted (его непрерывно держит S_SnatchTargetDetector — он же рисует
# крестик в прицеле), бросает кубик на capture_success_chance и при успехе
# «вселяется»:
#   - перенимает свежее здоровье из тела (C_Health);
#   - помечает себя C_Embodied;
#   - дозаправляет запас жизни (C_Lifespan) — захват снимает давление распада;
#   - переносит точку присутствия в тело;
#   - поглощает исходную сущность-тело.
class_name S_BodySnatch
extends System


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_BodySnatch]).with_none([C_UIBlocked])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for soul in entities:
		var bs := soul.get_component(C_BodySnatch) as C_BodySnatch
		if not bs.capture_requested:
			continue
		bs.capture_requested = false
		_try_capture(soul, bs)


func _try_capture(soul: Entity, bs: C_BodySnatch) -> void:
	# Луч тут больше не кастуем: цель под крестиком непрерывно держит
	# S_SnatchTargetDetector (он же рисует крестик в HUD) и объявлен Runs.Before,
	# так что метка на этот кадр уже проставлена. Один каст вместо двух и один
	# источник правды: во что целимся — ровно то, что подсвечено игроку.
	var body := ECS.world.query.with_all([C_SnatchTargeted]).execute_one()
	if body == null:
		return

	if randf() > bs.capture_success_chance:
		ECS.world.emit_event(&"body_snatch_failed", soul)
		return

	_embody(soul, body)


## Структурные правки идут через командный буфер (cmd), а не напрямую: с GECS v9
## System.safe_iteration = false по умолчанию — системы обходят массивы архетипов
## zero-copy, и add/remove прямо в process() может пропустить сущности (swap-remove)
## и роняет push_error в debug_mode. Буфер применяется сразу после process() этой
## системы (FlushMode.PER_SYSTEM), коалесцируя remove+add в один переезд архетипа.
func _embody(soul: Entity, body: Entity) -> void:
	var snatchable := body.get_component(C_BodySnatchable) as C_BodySnatchable

	# 1. Перенять здоровье тела — душа получает свежий C_Health.
	if soul.has_component(C_Health):
		cmd.remove_component(soul, C_Health)
	cmd.add_component(soul, C_Health.new(snatchable.max_health))

	# 2. Отметить состояние «во плоти».
	if not soul.has_component(C_Embodied):
		cmd.add_component(soul, C_Embodied.new())

	# 3. Дозаправить запас жизни БФЖ — захват продлевает существование.
	var life := soul.get_component(C_Lifespan) as C_Lifespan
	if life:
		life.current = life.max_duration

	# 4. Перенести точку присутствия в тело (Entity extends Node → двойной каст).
	var soul_node := soul as Node as Node3D
	var body_node := body as Node as Node3D
	if soul_node and body_node:
		soul_node.global_transform = body_node.global_transform

	# 5. Поглотить исходное тело.
	cmd.remove_entity(body)

	# Событие — тоже в буфер: иначе оно ушло бы ДО применения C_Embodied/C_Health,
	# и наблюдатель "body_snatched" увидел бы душу ещё не воплощённой.
	# add_custom исполняется в порядке постановки, т.е. после правок выше.
	cmd.add_custom(func(): ECS.world.emit_event(&"body_snatched", soul))
