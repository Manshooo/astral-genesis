# res://src/observers/o_body_form.gd
# Наблюдатель: надевает на душу-риг физическую форму захваченного тела —
# габарит коллизии и уровень глаз — и возвращает призрачную при развоплощении.
# Тот же приём развязки логики и представления, что C_BodyVisual → O_BodyVisual:
# захват про узлы рига ничего не знает, он только вешает C_BodyForm.
#
# Правим форму и камеру НА МЕСТЕ, не подменяя узлов: на CollisionShape3D рига
# ссылается E_Player.foot_offset (он измеряет именно его), а камеру держат по
# @onready S_FPSLook и S_Flight.
class_name O_BodyForm
extends Observer

## Доля роста, на которой оказываются глаза, если маркера Eyes в сцене тела нет.
## Число человеческое: у ростовой фигуры глаза примерно на 0.94 высоты.
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
	# Не player.camera: он @onready, а форму надевают в том числе из RunManager
	# при загрузке — там _ready рига может ещё не пройти (та же оговорка, что у
	# E_Player.foot_offset).
	var camera := player.get_node_or_null("Camera3D") as Camera3D

	match event:
		Observer.Event.ADDED:
			# Запоминаем призрачное ПЕРЕД подменой — вернуть его больше неоткуда.
			# Уже заполненное не трогаем: при пересадке из тела в тело
			# S_BodySnatch переносит сюда форму БФЖ, и перезаписать её формой
			# прошлого тела значило бы больше никогда не вернуться к призраку
			# (та же ловушка, что с restore_mesh в C_BodyVisual).
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


## Сажает камеру на уровень глаз тела.
##
## Маркер Eyes авторится ОТ ПОДОШВЫ (уровень глаз — часть модели), а камера живёт
## в координатах рига, у которого origin в ЦЕНТРЕ коллайдера. Перевод — тот же
## foot_offset, что и у посадки самого рига, но считаем его по НАДЕВАЕМОЙ форме,
## а не спрашиваем игрока: коллайдеру мы её только что присвоили, и полагаться на
## порядок строк внутри обработчика ради числа, которое и так известно, незачем.
##
## Нет маркера — берём долю от роста. Заведомо грубо, но лучше молчаливого нуля:
## ноль посадил бы взгляд в подошву, и симптом был бы неотличим от бага посадки
## рига, который эта же карточка и чинила.
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
