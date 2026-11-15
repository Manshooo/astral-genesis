# res://src/observers/o_body_form.gd
# Наблюдатель: надевает на душу-риг форму захваченного тела (габарит коллизии, уровень глаз) и возвращает призрачную
# при развоплощении; как C_BodyVisual → O_BodyVisual. Правим НА МЕСТЕ, не подменяя узлов: на CollisionShape3D ссылается
# E_Player.foot_offset, на маркер Eyes — E_Player.eye_point (лучи прицела, взгляд врага).
class_name O_BodyForm
extends Observer

## Доля роста для глаз, если маркера Eyes нет (у ростовой фигуры ~0.94).
const EYE_LEVEL_FALLBACK := 0.94


func query() -> QueryBuilder:
	return q.with_all([C_BodyForm]).on_added().on_removed()


func each(event: Variant, entity: Entity, payload: Variant = null) -> void:
	var player := entity as E_Player
	if player == null:
		return
	var form := payload as C_BodyForm
	if form == null:
		return

	var collision := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	# Не player.eyes: он @onready, а форму надевают и из RunManager при загрузке (как в E_Player.foot_offset).
	var eyes_node := player.get_node_or_null("Eyes") as Node3D

	match event:
		Observer.Event.ADDED:
			# Призрачное запоминаем ПЕРЕД подменой; заполненное не трогаем: при пересадке S_BodySnatch переносит сюда форму БФЖ.
			if form.restore_shape == null:
				form.restore_shape = collision.shape if collision else null
				form.restore_eyes = eyes_node.transform if eyes_node else Transform3D.IDENTITY
			if collision and form.shape:
				collision.shape = form.shape
			_place_eyes(player, form, eyes_node)
		Observer.Event.REMOVED:
			if collision and form.restore_shape:
				collision.shape = form.restore_shape
			if eyes_node:
				eyes_node.transform = form.restore_eyes
	_remember_eyes(player, eyes_node)


## Сажает глаза рига на уровень глаз тела: маркер Eyes тела — от подошвы, глаза рига — в его координатах, перевод через
## foot_offset по НАДЕВАЕМОЙ форме. Нет маркера — доля роста (ноль посадил бы взгляд в подошву).
func _place_eyes(player: E_Player, form: C_BodyForm, eyes_node: Node3D) -> void:
	if eyes_node == null:
		return

	var lift := form.foot_offset()
	if lift == Vector3.ZERO:
		lift = player.foot_offset()  # тело габарита не дало — риг остался собой

	var eyes := form.eye_height
	if eyes < 0.0:
		if lift.y <= 0.0:
			return  # ни маркера, ни измеримого габарита — трогать глаза нечем
		eyes = lift.y * 2.0 * EYE_LEVEL_FALLBACK

	var wanted := eyes_node.transform
	var look := player.get_component(C_Eyes) as C_Eyes
	if look and look.eye_position != Vector3.INF:
		wanted.origin = look.eye_position
	wanted.origin.y = eyes - lift.y
	eyes_node.transform = wanted


## База глаз (опора камеры от третьего лица) — там, куда форма только что поставила маркер Eyes.
func _remember_eyes(player: E_Player, eyes_node: Node3D) -> void:
	var look := player.get_component(C_Eyes) as C_Eyes
	if look and eyes_node:
		look.eye_position = eyes_node.position
