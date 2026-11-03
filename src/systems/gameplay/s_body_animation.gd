# res://src/systems/gameplay/s_body_animation.gd
# Группа "gameplay". Пишет параметры AnimationTree облика по тому, что тело делает: ход (скорость из C_Velocity, на полу ли),
# прыжок, удар (сброс перезарядки C_Attack / C_EnemyAI), попадание (падение C_Health), безделье. Одна на тело в комнате,
# врага и игрока в теле; у игрока деревьев два — облик и руки-муляж, решение одно на оба. Логики «что я ношу» здесь нет,
# пороги — в C_BodyAnimation. Не "physics": «на земле» — флаг C_Velocity.grounded, его пишет S_Movement.
# Скорость клипа подгоняется под ход, root motion нет. Вики: [[Захват тела]].
class_name S_BodyAnimation
extends System

## Вертикальная скорость, м/с, выше которой отрыв от земли — прыжок (клип jump), а не сход с края (сразу jump_air).
const LIFT_SPEED := 0.5

## Состояния полёта: из jump в jump_air дерево переходит само, по концу клипа, — назад его не тянуть.
const AIRBORNE: Array[StringName] = [&"jump", &"jump_air"]

## Пределы подгонки клипа под ход: за ними нога скользит заметнее, чем клип ускоряется.
const WALK_PACE := Vector2(0.5, 3.0)
const RUN_PACE := Vector2(0.6, 2.5)

## Сколько приземление держит тело на месте, прежде чем снова решать по скорости.
const LANDING := 0.3

const STATE := &"parameters/state/playback"
const PACE := &"parameters/pace/scale"
const DEATH := &"death"
const FIDGETS: Array[StringName] = [&"idle_listen", &"idle_scratch", &"idle_sniff"]
const HITS: Array[StringName] = [&"hit_front", &"hit_back"]


func query() -> QueryBuilder:
	return q.with_all([C_BodyAnimation])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		# Неактивное дерево — тело лежит рэгдоллом или облик не надет; гибель доигрывает сам труп.
		var trees := RS_EntityVisuals.animation_trees(entity).filter(
			func(tree: AnimationTree) -> bool: return tree.active and _playback(tree) != null
		)
		if trees.is_empty() or trees.any(func(tree: AnimationTree) -> bool: return _playback(tree).get_current_node() == DEATH):
			continue

		var anim := entity.get_component(C_BodyAnimation) as C_BodyAnimation
		var vel := entity.get_component(C_Velocity) as C_Velocity
		var velocity := vel.velocity if vel else Vector3.ZERO
		var speed := Vector2(velocity.x, velocity.z).length()
		var on_floor := vel.grounded if vel else true

		# Бег — это нажатый бег, а не скорость: шаг тела сам бывает быстрее клипа бега. Врагу без C_Sprint — порог.
		var sprint := entity.get_component(C_Sprint) as C_Sprint
		var running := sprint.active if sprint != null else speed >= anim.run_from_speed
		var pace := _move(anim, speed, running, on_floor, velocity.y, delta)
		var swung := _swung(entity, anim)
		var hit := _hit(entity, anim)
		var fidget := _fidget(anim, speed, delta)

		for tree in trees:
			var playback := _playback(tree)
			tree.set(PACE, pace)
			var current := playback.get_current_node()
			var flying_on := AIRBORNE.has(anim.state) and AIRBORNE.has(current)
			if current != anim.state and not flying_on and not playback.get_travel_path().has(anim.state):
				playback.travel(anim.state)
			if swung:
				tree.set(&"parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			if hit != &"":
				tree.set(&"parameters/hit_kind/transition_request", hit)
				tree.set(&"parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			if fidget != &"":
				tree.set(&"parameters/fidget_kind/transition_request", fidget)
				tree.set(&"parameters/fidget/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			elif anim.state != &"idle" and tree.get(&"parameters/fidget/active"):
				tree.set(&"parameters/fidget/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func _playback(tree: AnimationTree) -> AnimationNodeStateMachinePlayback:
	return tree.get(STATE) as AnimationNodeStateMachinePlayback


## Выбирает состояние в anim.state; возвращает темп клипа.
func _move(anim: C_BodyAnimation, speed: float, running: bool, on_floor: bool, rise: float, delta: float) -> float:
	anim.landing_left -= delta
	if not on_floor:
		if not anim.airborne:
			anim.state = &"jump" if rise > LIFT_SPEED else &"jump_air"
		anim.airborne = true
		return 1.0
	if anim.airborne:
		anim.airborne = false
		anim.state = &"jump_land"
		anim.landing_left = LANDING
		return 1.0
	if speed < C_BodyAnimation.STILL_SPEED:
		if anim.landing_left <= 0.0:
			anim.state = &"idle"
		return 1.0
	if not running and anim.trot_clip_speed > 0.0 and speed >= anim.trot_from_speed:
		anim.state = &"trot"
		return clampf(speed / anim.trot_clip_speed, WALK_PACE.x, WALK_PACE.y)
	if not running:
		anim.state = &"walk"
		return clampf(speed / anim.walk_clip_speed, WALK_PACE.x, WALK_PACE.y)
	anim.state = &"run"
	return clampf(speed / anim.run_clip_speed, RUN_PACE.x, RUN_PACE.y)


## Удар узнаём по сбросу перезарядки: она взводится в миг замаха, у игрока (C_Attack) и у врага (C_EnemyAI) одинаково.
func _swung(entity: Entity, anim: C_BodyAnimation) -> bool:
	var cooldown := -1.0
	var attack := entity.get_component(C_Attack) as C_Attack
	var ai := entity.get_component(C_EnemyAI) as C_EnemyAI
	if attack != null:
		cooldown = attack.cooldown_left
	elif ai != null:
		cooldown = ai.attack_cooldown_left
	if cooldown < 0.0:
		return false
	var swung := cooldown > anim.last_cooldown + 0.01
	anim.last_cooldown = cooldown
	return swung


## Попадание — по падению прочности, кто бы ни ударил; клип — случайный из HITS, &"" — не попали.
func _hit(entity: Entity, anim: C_BodyAnimation) -> StringName:
	var health := entity.get_component(C_Health) as C_Health
	if health == null:
		return &""
	var hurt := anim.last_health >= 0.0 and health.current < anim.last_health - 0.01 and health.current > 0.0
	anim.last_health = health.current
	return HITS.pick_random() if hurt else &""


## Постоял — почесался или прислушался; клип или &"".
func _fidget(anim: C_BodyAnimation, speed: float, delta: float) -> StringName:
	if anim.state != &"idle" or speed >= C_BodyAnimation.STILL_SPEED or anim.fidget_left < 0.0:
		anim.fidget_left = randf_range(anim.fidget_interval.x, anim.fidget_interval.y)
		return &""
	anim.fidget_left -= delta
	if anim.fidget_left > 0.0:
		return &""
	anim.fidget_left = randf_range(anim.fidget_interval.x, anim.fidget_interval.y)
	return FIDGETS.pick_random()
