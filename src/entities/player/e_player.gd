# res://src/entities/player/e_player.gd
@tool
class_name E_Player
extends Entity

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay


## Компоненты-идентичность БФЖ, живущие независимо от текущего тела.
## Здесь, а не в сцене — чтобы «душа» всегда имела их, и чтобы S_ApplySkillEffects
## (запрос C_Lifespan+C_BodySnatch) наконец матчил игрока.
func define_components() -> Array:
	return [C_BodySnatch.new(), C_Lifespan.new()]


## Насколько начало координат рига ВЫШЕ его подошвы.
##
## Нужно всем, кто совмещает рига с чужой геометрией: у сцен тел origin в ступнях
## (капсула стоит дном на y = 0), у игрока — в центре его капсулы, и общая у них
## только точка опоры. Таких мест два, и оба переводят одно соглашение в другое
## именно здесь, а не константой на месте вызова: вселение двигает самого игрока
## (S_BodySnatch — иначе он садится на полроста в пол), а O_BodyVisual сажает по
## подошве надетый облик (см. C_BodyVisual.mesh_transform).
##
## Считаем по коллайдеру, а не константой: капсулу игрока тюнят в сцене, и зашитое
## число разъехалось бы с ней МОЛЧА — игрок снова утонул бы в полу, а надетый облик
## повис бы в воздухе. Не @onready: облик надевается в т.ч. из RunManager при
## загрузке, и полагаться на то, что _ready рига уже прошёл, здесь не на чем.
func foot_offset() -> Vector3:
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var capsule := shape.shape as CapsuleShape3D if shape else null
	if capsule == null:
		push_warning("E_Player: капсула не найдена — считаем, что origin и есть подошва")
		return Vector3.ZERO
	return Vector3(0.0, capsule.height * 0.5 - shape.position.y, 0.0)


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

	# Захват тела — действие "snatch_body" (по умолчанию ЛКМ, задаётся в
	# project.godot [input], переназначаемо). Здесь только ставим запрос-флаг;
	# сам захват (луч/бросок/вселение) выполняет S_BodySnatch по C_BodySnatch.capture_requested.
	if event.is_action_pressed("snatch_body") and not event.is_echo():
		var bs := get_component(C_BodySnatch) as C_BodySnatch
		if bs:
			bs.capture_requested = true

	# Покинуть тело по своей воле. Тоже только флаг: сам выход разбирает
	# S_BodySnatch, потому что это половина модели распада — остаток запаса тела
	# переходит душе только при добровольном выходе (см. O_ExpelFromBody.expel).
	if event.is_action_pressed("leave_body") and not event.is_echo():
		var bs := get_component(C_BodySnatch) as C_BodySnatch
		if bs:
			bs.leave_requested = true
