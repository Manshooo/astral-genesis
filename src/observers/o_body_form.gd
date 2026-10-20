# res://src/observers/o_body_form.gd
# Наблюдатель: надевает на душу-риг форму захваченного тела (габарит коллизии, уровень глаз) и возвращает призрачную
# при развоплощении; как C_BodyVisual → O_BodyVisual. Правим НА МЕСТЕ, не подменяя узлов: на CollisionShape3D ссылается
# E_Player.foot_offset, камеру держат по @onready S_FPSLook и S_Flight.
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
	# Не player.camera: он @onready, а форму надевают и из RunManager при загрузке (как в E_Player.foot_offset).
	var camera := player.get_node_or_null("Camera3D") as Camera3D

	match event:
		Observer.Event.ADDED:
			# Призрачное запоминаем ПЕРЕД подменой; заполненное не трогаем: при пересадке S_BodySnatch переносит сюда форму БФЖ.
			if form.restore_shape == null:
				form.restore_shape = collision.shape if collision else null
				form.restore_camera = camera.transform if camera else Transform3D.IDENTITY
			if collision and form.shape:
				collision.shape = form.shape
			_place_camera(player, form, camera)
		Observer.Event.REMOVED:
			if collision and form.restore_shape:
				collision.shape = form.restore_shape
			if camera:
				camera.transform = form.restore_camera


## Сажает камеру на уровень глаз тела: маркер Eyes — от подошвы, камера — в координатах рига, перевод через foot_offset
## по НАДЕВАЕМОЙ форме. Нет маркера — доля роста (ноль посадил бы взгляд в подошву).
func _place_camera(player: E_Player, form: C_BodyForm, camera: Camera3D) -> void:
	if camera == null:
		return

	var lift := form.foot_offset()
	if lift == Vector3.ZERO:
		lift = player.foot_offset()  # тело габарита не дало — риг остался собой

	var eyes := form.eye_height
	if eyes < 0.0:
		if lift.y <= 0.0:
			return  # ни маркера, ни измеримого габарита — трогать камеру нечем
		eyes = lift.y * 2.0 * EYE_LEVEL_FALLBACK

	var wanted := camera.transform
	wanted.origin.y = eyes - lift.y
	camera.transform = wanted
