# res://src/entities/player/e_player.gd
@tool
class_name E_Player
extends Entity

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay


## Компоненты-идентичность БФЖ, живущие независимо от текущего тела.
## Здесь, а не в сцене — чтобы «душа» всегда имела их, и чтобы O_ApplySkillEffects
## (запрос C_StatModifiers) матчил игрока.
##
## C_StatModifiers в этом списке — то, что делает душу носителем прокачки:
## характеристики приходят и уходят вместе с телами, а слой модификаторов
## принадлежит именно душе и переживает любую пересадку.
func define_components() -> Array:
	return [C_BodySnatch.new(), C_Lifespan.new(), C_StatModifiers.new()]


## Возможности САМОЙ души — свежие копии того, что авторено в сцене БФЖ.
##
## Читаем component_resources, а не components: во плоти возможности с души
## СНЯТЫ (их усыпляет O_SoulTraits), и спрашивать живой набор в момент
## пробуждения было бы бессмысленно. Авторский же массив remove_component не
## трогает — там лежат оригиналы из сцены, по которым GECS раскладывал сущность
## при добавлении в мир. Тот же приём, что в E_Body.traits_of_scene.
##
## Копии, а не оригиналы: ресурс в сцене общий на все инстансы, и вернуть его
## самого значило бы, что разогнавшийся полёт одной души правит числа всех
## остальных.
##
## В СЦЕНЕ, а не в define_components(), потому что у возможности есть числа
## (C_Flight.speed) и тюнить их полагается в инспекторе — ровно как C_Walk.speed
## у тел. В define_components() живёт только идентичность, которая обязана
## пережить любую пересадку и чисел не имеет.
func soul_traits() -> Array[Component]:
	var found: Array[Component] = []
	for resource in component_resources:
		if resource is C_SoulTrait:
			found.append(resource.duplicate() as Component)
	return found


## Насколько origin рига ВЫШЕ его подошвы. Мост между двумя соглашениями: у сцен
## тел origin в ступнях, у игрока — в ЦЕНТРЕ его коллайдера. Пользуются оба
## перехода — S_BodySnatch сажает сюда самого рига, O_BodyVisual — надетый облик.
##
## Считаем по коллайдеру, а не зашитым числом: форму игрока тюнят в сцене, и
## константа разъехалась бы с ней МОЛЧА — риг сел бы на полроста в пол. Форму уже
## меняли (капсула → сфера), поэтому и тип не зашит: см. shape_half_height.
## Не @onready — облик надевается в т.ч. из RunManager при загрузке, когда _ready
## рига ещё не прошёл.
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


## Половина вертикального габарита формы коллизии, или -1 для формы, которую мы
## измерять не умеем.
##
## Разбор по типу, а не общий AABB через get_debug_mesh(): тот строит меш ради
## одного числа, а список форм, которыми игрок реально бывает, короткий. Молчать
## о неизвестной форме нельзя — ноль здесь читается как «origin в подошве» и
## утапливает надетое тело в пол ровно на полроста.
##
## Публичная, потому что тот же вопрос задаёт C_BodyForm про форму, которую риг
## ЕЩЁ не надел: перевод между соглашениями об origin должен считаться одной
## формулой, а не двумя похожими.
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
