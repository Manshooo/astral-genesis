# Игрок — душа-БФЖ (риг): идентичность и мосты между соглашениями об origin. Вики: [[Захват тела]].
@tool
class_name E_Player
extends Entity

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay


## Игрок мира или null (нет мира или не заспавнен). ЕДИНСТВЕННОЕ место, где «игрок» выводится из C_PlayerInput.
## Entity, а не E_Player: в проверках душа бывает голой сущностью.
static func find() -> Entity:
	if ECS.world == null:
		return null
	return ECS.world.query.with_all([C_PlayerInput]).execute_one()


## Игрок во плоти; false и когда игрока нет вовсе.
static func is_embodied() -> bool:
	var player := find()
	return player != null and player.has_component(C_Embodied)


## Поле зрения — из настроек, по горизонтали (60–120, KEEP_WIDTH): на вертикальной шкале 103° было бы рыбьим глазом.
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	SettingsManager.settings_changed.connect(_apply_fov)
	_apply_fov(SettingsManager.settings)


func _apply_fov(settings: RS_Settings) -> void:
	if settings == null:
		return
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = clampf(settings.fov, RS_Settings.FOV_MIN, RS_Settings.FOV_MAX)


## Компоненты-идентичность БФЖ, независимые от тела; C_StatModifiers — слой модификаторов принадлежит душе.
func define_components() -> Array:
	return [C_BodySnatch.new(), C_Lifespan.new(), C_StatModifiers.new(), C_AbilityLoadout.new()]


## Возможности САМОЙ души — свежие копии из сцены. Читаем component_resources: во плоти возможности сняты
## (O_SoulTraits). Копии — ресурс общий на все инстансы. В сцене, а не в define_components(): числа тюнятся в инспекторе.
func soul_traits() -> Array[Component]:
	var found: Array[Component] = []
	for resource in component_resources:
		if resource is C_SoulTrait:
			found.append(resource.duplicate() as Component)
	return found


## Насколько origin рига выше подошвы: мост между соглашениями (у тел origin в ступнях, у игрока — в центре
## коллайдера). Считаем по коллайдеру, не числом. Не @onready — облик надевается из RunManager до _ready рига.
func foot_offset() -> Vector3:
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var half := shape_half_height(shape.shape) if shape else -1.0
	if half < 0.0:
		push_warning(
			"E_Player: не удалось измерить коллайдер (%s) — считаем, что origin и есть подошва"
			% [str(shape.shape) if shape else "нет CollisionShape3D"]
		)
		return Vector3.ZERO
	return Vector3(0.0, half - shape.position.y, 0.0)


## Половина вертикального габарита формы или -1 для неизвестной (ноль утопил бы тело в пол). Публичная: её
## же спрашивает C_BodyForm — перевод между соглашениями считается одной формулой.
static func shape_half_height(shape: Shape3D) -> float:
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).height * 0.5
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).height * 0.5
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size.y * 0.5
	return -1.0


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if has_component(C_UIBlocked):
		return  # не копим mouse look, пока открыт UI

	if event is InputEventMouseMotion:
		var inp := get_component(C_PlayerInput) as C_PlayerInput
		if inp:
			inp.mouse_delta += event.relative

	if event.is_action_pressed("jump") and not event.is_echo():
		var inp := get_component(C_PlayerInput) as C_PlayerInput
		if inp:
			inp.jump_pressed = true

	# Бег читается удержанием; здесь только ФРОНТ нажатия — для отказа «не умеет бегать» раз на нажатие.
	if event.is_action_pressed("sprint") and not event.is_echo():
		var inp := get_component(C_PlayerInput) as C_PlayerInput
		if inp:
			inp.sprint_pressed = true

	# Удар — только фронт нажатия; кому бить нечем, S_Attack отказывает.
	if event.is_action_pressed("attack") and not event.is_echo():
		var inp := get_component(C_PlayerInput) as C_PlayerInput
		if inp:
			inp.attack_pressed = true

	# Клавиша слота — номер; что в слоте и можно ли, решает S_Abilities.
	for i in C_AbilityLoadout.ACTIONS.size():
		if event.is_action_pressed(C_AbilityLoadout.ACTIONS[i]) and not event.is_echo():
			var inp := get_component(C_PlayerInput) as C_PlayerInput
			if inp:
				inp.ability_pressed = i + 1

	# Захват тела (snatch_body): здесь только флаг, выполняет S_BodySnatch.
	if event.is_action_pressed("snatch_body") and not event.is_echo():
		var bs := get_component(C_BodySnatch) as C_BodySnatch
		if bs:
			bs.capture_requested = true

	# Покинуть тело по своей воле — флаг; остаток запаса идёт душе только при добровольном выходе (O_ExpelFromBody.expel).
	if event.is_action_pressed("leave_body") and not event.is_echo():
		var bs := get_component(C_BodySnatch) as C_BodySnatch
		if bs:
			bs.leave_requested = true
