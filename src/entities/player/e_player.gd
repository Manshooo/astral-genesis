# res://src/entities/player/e_player.gd
@tool
class_name E_Player
extends Entity

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var collider: CollisionShape3D = $CollisionShape3D


## Компоненты-идентичность БФЖ, живущие независимо от текущего тела.
## Здесь, а не в сцене — чтобы «душа» всегда имела их, и чтобы S_ApplySkillEffects
## (запрос C_Lifespan+C_BodySnatch) наконец матчил игрока.
func define_components() -> Array:
	return [C_BodySnatch.new(), C_Lifespan.new()]


## Насколько origin игрока ВЫШЕ его подошвы.
##
## У игрока и у тел разные точки отсчёта: капсула игрока центрирована в origin
## (см. e_player.tscn), а тела стоят в комнатах на y = 0 с поднятым коллайдером,
## то есть их origin — это подошва (см. E_Body). Единственное место, где две
## системы координат встречаются, — вселение (S_BodySnatch), и перевод между
## ними живёт здесь, а не константой на месте вызова: правка капсулы в сцене
## иначе снова утопила бы игрока в полу.
##
## Считается от формы вместе с её смещением: коллайдер не обязан быть в origin,
## и это смещение — часть ответа.
func foot_offset() -> float:
	if collider == null or collider.shape == null:
		push_warning("E_Player: нет коллайдера — считаем, что origin и есть подошва")
		return 0.0

	var shape := collider.shape
	var half := 0.0
	if shape is CapsuleShape3D:
		half = (shape as CapsuleShape3D).height * 0.5
	elif shape is CylinderShape3D:
		half = (shape as CylinderShape3D).height * 0.5
	elif shape is BoxShape3D:
		half = (shape as BoxShape3D).size.y * 0.5
	elif shape is SphereShape3D:
		half = (shape as SphereShape3D).radius
	else:
		push_warning("E_Player: форма коллайдера %s неизвестна — подошву не найти" % shape.get_class())

	return half - collider.position.y


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
