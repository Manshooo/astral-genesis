# res://src/systems/gameplay/s_body_animation.gd
# Группа "gameplay". Пишет параметры AnimationTree облика по тому, что тело делает: ход (скорость из C_Velocity, на полу ли),
# прыжок, удар (сброс перезарядки C_Attack / C_EnemyAI), попадание (падение C_Health), безделье. Одна на тело в комнате,
# врага и игрока в теле; решение пишется во все деревья облика (RS_EntityVisuals.animation_trees). Логики «что я ношу» здесь нет,
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

## Направление шага, ближе к переду которого (косинус угла) идёт обычный ход — шаг, рысь; дальше — шаг вбок или спиной.
const FORWARD_COS := 0.7

const STATE := &"parameters/state/playback"
const PACE := &"parameters/pace/scale"
## Точка смеси клипов шага (BlendSpace2D walk): x — вправо, y — вперёд.
const WALK_BLEND := &"parameters/state/walk/blend_position"
const DEATH := &"death"
## Узел дерева, чьи входы — позы безделья: у каждого типа рига они свои.
const FIDGET_KIND := &"fidget_kind"
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
		var node := entity as Node as Node3D
		var local := node.global_basis.inverse() * velocity if node != null else Vector3.FORWARD
		var pace := _move(anim, speed, Vector2(local.x, -local.z), running, on_floor, velocity.y, delta)
		var swung := _swung(entity, anim)
		var hit := _hit(entity, anim)
		var fidget := _fidget(anim, speed, delta)

		for tree in trees:
			var playback := _playback(tree)
			tree.set(PACE, pace)
			tree.set(WALK_BLEND, anim.walk_direction)
			var current := playback.get_current_node()
			var flying_on := AIRBORNE.has(anim.state) and AIRBORNE.has(current)
			if current != anim.state and not flying_on and not playback.get_travel_path().has(anim.state):
				playback.travel(anim.state)
			if swung:
				tree.set(&"parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			if hit != &"":
				tree.set(&"parameters/hit_kind/transition_request", hit)
				tree.set(&"parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			var kinds := fidgets_of(tree) if fidget else PackedStringArray()
			if not kinds.is_empty():
				tree.set(&"parameters/fidget_kind/transition_request", kinds[randi() % kinds.size()])
				tree.set(&"parameters/fidget/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			elif anim.state != &"idle" and tree.get(&"parameters/fidget/active"):
				tree.set(&"parameters/fidget/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func _playback(tree: AnimationTree) -> AnimationNodeStateMachinePlayback:
	return tree.get(STATE) as AnimationNodeStateMachinePlayback


## Позы безделья дерева — входы узла fidget_kind; пусто — у дерева их нет.
static func fidgets_of(tree: AnimationTree) -> PackedStringArray:
	var names := PackedStringArray()
	var root := tree.tree_root as AnimationNodeBlendTree
	var kinds := root.get_node(FIDGET_KIND) as AnimationNodeTransition if root != null and root.has_node(FIDGET_KIND) else null
	if kinds != null:
		for i in kinds.get_input_count():
			names.append(kinds.get_input_name(i))
	return names


## Выбирает состояние в anim.state и направление шага в anim.walk_direction; возвращает темп клипа.
## [param heading] — горизонтальная скорость в осях тела (x — вправо, y — вперёд).
func _move(anim: C_BodyAnimation, speed: float, heading: Vector2, running: bool, on_floor: bool, rise: float,
		delta: float) -> float:
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
	if running:
		anim.state = &"run"
		return clampf(speed / anim.run_clip_speed, RUN_PACE.x, RUN_PACE.y)
	var direction := heading.normalized() if heading != Vector2.ZERO else Vector2(0.0, 1.0)
	# Рысь — только вперёд: клипов рыси вбок и назад нет, в стрейфе тело идёт смесью клипов шага.
	if direction.y >= FORWARD_COS and anim.trot_clip_speed > 0.0 and speed >= anim.trot_from_speed:
		anim.state = &"trot"
		anim.walk_direction = Vector2(0.0, 1.0)
		return clampf(speed / anim.trot_clip_speed, WALK_PACE.x, WALK_PACE.y)
	anim.state = &"walk"
	anim.walk_direction = direction
	return clampf(speed / walk_clip_speed(anim, direction), WALK_PACE.x, WALK_PACE.y)


## Метров в секунду у смеси клипов шага по [param direction]: вес каждого клипа — доля направления по его оси.
static func walk_clip_speed(anim: C_BodyAnimation, direction: Vector2) -> float:
	var forward := maxf(direction.y, 0.0)
	var back := maxf(-direction.y, 0.0)
	var side := absf(direction.x)
	var back_speed := anim.walk_back_clip_speed if anim.walk_back_clip_speed > 0.0 else anim.walk_clip_speed
	var side_speed := anim.strafe_clip_speed if anim.strafe_clip_speed > 0.0 else anim.walk_clip_speed
	return (forward * anim.walk_clip_speed + back * back_speed + side * side_speed) / maxf(forward + back + side, 0.001)


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


## Постоял — пора почесаться или прислушаться; какой позой — решает дерево (fidgets_of).
func _fidget(anim: C_BodyAnimation, speed: float, delta: float) -> bool:
	if anim.state != &"idle" or speed >= C_BodyAnimation.STILL_SPEED or anim.fidget_left < 0.0:
		anim.fidget_left = randf_range(anim.fidget_interval.x, anim.fidget_interval.y)
		return false
	anim.fidget_left -= delta
	if anim.fidget_left > 0.0:
		return false
	anim.fidget_left = randf_range(anim.fidget_interval.x, anim.fidget_interval.y)
	return true
