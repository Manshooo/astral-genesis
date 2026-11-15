extends Node3D
## Беговая дорожка: манекен — настоящий враг-hound без «мозга» (C_EnemyInput снят, поэтому S_EnemyAI и S_Walk его не
## берут), бежит по кругу с заданной скоростью, а клип выбирает настоящая S_BodyAnimation — как у врага в забеге. Удар,
## попадание и гибель идут теми же сигналами, по которым их узнаёт система: перезарядка, прочность, смерть. Вики: [[Полигон]].

## Враг, которого гоняет дорожка; его труп — corpse_scene.
@export var puppet_scene: PackedScene
## Радиус круга, м.
@export var radius := 5.0
## Скорость прыжка вверх, м/с, если у трупа врага нет C_Jump (у живого врага прыжка нет).
@export var fallback_jump := 6.0

## Горизонтальная скорость, которую держит манекен, м/с.
var speed := 0.0
var puppet: E_Enemy
## Труп последнего манекена: в него можно вселиться, «Вернуть манекен» его убирает.
var corpse: E_Body

var _heading := Vector3.FORWARD
var _heal_at := -1


func _ready() -> void:
	child_entered_tree.connect(_on_child_entered)


## Новый манекен на круге; прежний и его труп убираются.
func spawn_puppet() -> void:
	clear()
	var enemy := puppet_scene.instantiate() as E_Enemy
	# Место до add_child: коллайдер регистрируется там, где узел вошёл в дерево.
	enemy.position = Vector3(radius, 0.0, 0.0)
	add_child(enemy)
	ECS.world.add_entity(enemy)
	enemy.remove_component(C_EnemyInput)
	puppet = enemy
	_heading = Vector3.FORWARD


func clear() -> void:
	# Без типа у переменной цикла: поглощённый захватом труп уже освобождён, а в типизированную его не присвоить.
	for entity in [puppet, corpse]:
		if is_instance_valid(entity) and ECS.world.entities.has(entity):
			ECS.world.remove_entity(entity)
	puppet = null
	corpse = null


func alive() -> bool:
	return is_instance_valid(puppet) and not puppet.has_component(C_Dead)


## Скорости, на которых тело показывает каждый клип хода, — из его же C_BodyAnimation и C_Walk, а не числами здесь.
func presets() -> Dictionary:
	var anim := _anim()
	if anim == null:
		return {}
	var out := {"стоять": 0.0, "шаг": minf(anim.walk_clip_speed, anim.trot_from_speed - 0.1)}
	if anim.trot_clip_speed > 0.0:
		out["рысь"] = clampf(anim.trot_clip_speed, anim.trot_from_speed, anim.run_from_speed - 0.1)
	out["бег"] = maxf(anim.run_clip_speed, anim.run_from_speed + 0.5)
	var walk := puppet.get_component(C_Walk) as C_Walk
	if walk != null:
		out["как в забеге"] = walk.speed
	return out


func jump() -> void:
	if not alive():
		return
	var vel := puppet.get_component(C_Velocity) as C_Velocity
	if vel.grounded:
		vel.velocity.y = _jump_velocity()


## Замах узнаётся по взводу перезарядки — его и взводим.
func bite() -> void:
	if alive():
		var ai := puppet.get_component(C_EnemyAI) as C_EnemyAI
		ai.attack_cooldown_left = ai.attack_interval


## Попадание узнаётся по падению прочности; через пару кадров она возвращается, чтобы манекен не умер от проверок.
func hit() -> void:
	if alive():
		(puppet.get_component(C_Health) as C_Health).current -= 1.0
		_heal_at = Engine.get_process_frames() + 3


## Гибель — настоящая: прочность в ноль, дальше S_Health и O_EnemyDeath ставят труп, он падает клипом и рэгдоллом.
func kill() -> void:
	if alive():
		(puppet.get_component(C_Health) as C_Health).current = 0.0


## Безделье как в игре: таймер S_BodyAnimation истекает сейчас, клип — случайный.
func fidget() -> void:
	var anim := _anim()
	if anim != null:
		anim.fidget_left = 0.001


## Конкретное безделье мимо случайного выбора системы — те же параметры дерева, которые пишет она.
func fidget_kind(kind: StringName) -> void:
	var tree := animation_tree()
	if tree == null:
		return
	tree.set(&"parameters/fidget_kind/transition_request", kind)
	tree.set(&"parameters/fidget/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func animation_tree() -> AnimationTree:
	if is_instance_valid(puppet):
		return RS_EntityVisuals.animation_tree(puppet)
	if is_instance_valid(corpse):
		return RS_EntityVisuals.animation_tree(corpse)
	return null


## Что сейчас решила система и что играет дерево — для панели.
func status() -> Dictionary:
	var out := {}
	var tree := animation_tree()
	if tree == null or not tree.active:
		out["нет"] = "манекена нет" if not is_instance_valid(corpse) else "труп лежит рэгдоллом"
		return out
	var playback := tree.get(S_BodyAnimation.STATE) as AnimationNodeStateMachinePlayback
	var anim := _anim()
	if anim != null:
		out["решила система"] = anim.state
	out["играет"] = "%s  %.2f / %.2f с" % [playback.get_current_node(), playback.get_current_play_position(),
		playback.get_current_length()]
	var fading := playback.get_fading_from_node()
	if fading != &"":
		out["уходит"] = fading
	if not playback.get_travel_path().is_empty():
		out["путь"] = ", ".join(playback.get_travel_path())
	out["темп клипа"] = "×%.2f" % float(tree.get(S_BodyAnimation.PACE))
	if is_instance_valid(puppet):
		var vel := puppet.get_component(C_Velocity) as C_Velocity
		out["скорость"] = "%.2f м/с" % Vector2(vel.velocity.x, vel.velocity.z).length()
		out["на земле"] = "да" if vel.grounded else "нет"
	if tree.get(&"parameters/action/active"):
		out["поверх"] = "укус"
	elif tree.get(&"parameters/hit/active"):
		out["поверх"] = "попадание"
	elif tree.get(&"parameters/fidget/active"):
		out["поверх"] = "безделье"
	return out


## Пишет скорость манекену по касательной к кругу с подтяжкой к радиусу. Узел обрабатывается после корня полигона,
## то есть после физпрохода ECS, — скорость применится следующим тиком, как у любого ввода.
func _physics_process(delta: float) -> void:
	if not alive():
		return
	var ai := puppet.get_component(C_EnemyAI) as C_EnemyAI
	# Перезарядку убавляет S_EnemyAI, а манекена он не берёт.
	ai.attack_cooldown_left = maxf(0.0, ai.attack_cooldown_left - delta)
	var node := puppet as Node as Node3D
	var from_center := node.global_position - global_position
	from_center.y = 0.0
	if speed > C_BodyAnimation.STILL_SPEED and from_center.length() > 0.01:
		var radial := from_center.normalized()
		var tangent := radial.cross(Vector3.UP)
		var pull := clampf((radius - from_center.length()) / radius, -0.5, 0.5)
		_heading = (tangent + radial * pull).normalized()
		node.global_rotation.y = atan2(-_heading.x, -_heading.z)
	var vel := puppet.get_component(C_Velocity) as C_Velocity
	vel.velocity.x = _heading.x * speed
	vel.velocity.z = _heading.z * speed


func _process(_delta: float) -> void:
	if _heal_at >= 0 and Engine.get_process_frames() >= _heal_at:
		_heal_at = -1
		if alive():
			var health := puppet.get_component(C_Health) as C_Health
			health.current = health.maximum


func _on_child_entered(node: Node) -> void:
	if node is E_Body:
		corpse = node as E_Body


func _anim() -> C_BodyAnimation:
	if not is_instance_valid(puppet):
		return null
	return puppet.get_component(C_BodyAnimation) as C_BodyAnimation


func _jump_velocity() -> float:
	if puppet.corpse_scene != null:
		for component in E_Body.traits_of_scene(puppet.corpse_scene.resource_path):
			if component is C_Jump:
				return (component as C_Jump).velocity
	return fallback_jump
