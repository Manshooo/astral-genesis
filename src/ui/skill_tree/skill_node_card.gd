# res://src/ui/skill_tree/skill_node_card.gd
## Карточка одного навыка — узел графа дерева.
##
## Вёрстка живёт в skill_node_card.tscn, а не в этом файле: карточку правят
## глазами (отступы, шрифт, полоска ветки, место под деления рангов), и код,
## собирающий её из new(), означал бы, что каждая такая правка — правка кода.
## Скрипт держит только то, что вёрсткой не выражается: текст состояния,
## подсказку и деления рангов, которых столько, сколько у навыка рангов.
##
## Тем же правилом живут и эффекты: появление карточки и покупку ранга играет
## AnimationPlayer «Effects» из сцены, а не тайминги в коде. В скрипте остались
## разве что переходы, зависящие от ТЕКУЩЕГО состояния узла (оживание из
## предпросмотра) — их дорожкой не выразить: у анимации начальный кадр
## фиксированный, а тут он какой есть.
##
## Это Button, а не составной Control с кнопкой внутри: узел графа кликабелен
## целиком, и наведение с подсказкой обязано ловиться всей площадью карточки.
## Поэтому же вся начинка помечена MOUSE_FILTER_IGNORE (в сцене) — иначе подпись
## под курсором «съедала» бы и hover, и tooltip у своего же узла.
##
## Карточка ничего не знает про SkillManager и ничего не решает сама: состояние
## ей приносит граф вызовом refresh(). Так у «можно ли купить» остаётся один
## источник правды — SkillManager.can_unlock.
class_name UI_SkillNode
extends Button

@export_group("Деления рангов")
## Непрожитый ранг тем же цветом ветки, но еле видный. Только это и осталось в
## коде: размер деления и зазор между ними задаёт сцена — `Pip` и `separation`
## у ряда `Pips`.
@export var pip_empty_alpha := 0.22

@export_group("Появление и вспышка")
## Шаг между точками вылета искр по периметру карточки. Меньше — плотнее очередь
## искр по кромке, но и частиц на ту же длину нужно больше: их число задаёт сама
## сцена искр, а точки лишь говорят, ОТКУДА им лететь.
@export var spark_perimeter_step := 14.0

@export_group("Звук")
## Событие byProd на покупку ранга. Путь, а не файл: что прозвучит и из скольких
## вариантов выберется — решает проект звука (см. how-to/Звук.md). Промах по этой
## строке ничего не роняет: byProd один раз предупредит, экран останется
## беззвучным — поэтому её сверяет с проектом dev/byprod_check.tscn. Пустая
## строка — «молча», без предупреждения вовсе.
@export var unlock_event := "event:/ui/skill_unlock"

@export_group("Предпросмотр")
## Серость карточки-предпросмотра. Приглушаются только каналы цвета, а альфа
## сохраняется: ею анимируется появление узла, и запись целого Color оборвала бы
## въезд карточки на середине.
@export var preview_tint := Color(0.62, 0.64, 0.68)
## Переход из предпросмотра в доступный навык.
@export var ungrey_duration := 0.25
## Что стоит в строке состояния, пока навык только показан.
@export var preview_status_text := "Недоступно"
@export var maxed_status_text := "Максимум"

## Искры при разблокировке — своя сцена: их количество, разлёт, тяжесть и цвет
## это вид, а не поведение, и подбираются они глазами в редакторе частиц.
const SPARKS_SCENE := preload("res://src/ui/skill_tree/skill_sparks.tscn")

@onready var _stripe: Panel = %Stripe
@onready var _title: Label = %Title
@onready var _pips: HBoxContainer = %Pips
@onready var _status: Label = %Status
@onready var _sparks_anchor: Control = %SparksAnchor
@onready var _effects: AnimationPlayer = %Effects

var definition: RS_SkillDefinition
var accent: Color = RS_SkillBranch.DEFAULT_COLOR
## Навык показан «на шаг вперёд»: описание читается, купить нельзя.
var previewed: bool = false

var _rank: int = 0


## Зовётся графом ПОСЛЕ добавления карточки в дерево сцены: до этого @onready
## ссылки на начинку ещё не подняты.
func setup(def: RS_SkillDefinition, accent_color: Color) -> void:
	definition = def
	accent = accent_color
	name = "Node_" + String(def.id)

	_title.text = def.display_name
	# Полоска ветки — Panel со своим StyleBoxFlat, а не ColorRect: скругление у
	# неё собственное и подбирается в редакторе под скругление карточки. Обрезать
	# прямоугольник по скруглённым углам родителя движок не умеет — clip_contents
	# режет РОВНО прямоугольник контрола, corner_radius стилбокса не учитывая
	# (godot-proposals#14404 открыт и не реализован); clip_children по альфе
	# родителя работает, но тянет за собой маску на всю начинку карточки ради
	# одной четырёхпиксельной полосы.
	#
	# Стилбокс помечен resource_local_to_scene: без этого он был бы ОДНИМ на все
	# карточки, и цвет последней ветки перекрасил бы всё дерево.
	var stripe_style := _stripe.get_theme_stylebox("panel") as StyleBoxFlat
	if stripe_style != null:
		stripe_style.bg_color = accent
	_build_pips(def.max_rank)


## Делений столько, сколько у навыка рангов, — единственное в карточке, что
## вёрсткой не задать: число приходит из данных. Поэтому в сцене лежит ОДНО
## деление-образец, а остальные — его копии: как выглядит деление (размер,
## скругление, стиль), правится на нём в редакторе, и копии повторяют его сами.
func _build_pips(count: int) -> void:
	var template: Panel = _pips.get_child(0)
	template.visible = count > 0
	for i in range(1, count):
		var pip: Panel = template.duplicate()
		# Уникальное имя у копии сняли бы всё равно: двое владельцев одного
		# «%Pip» — это предупреждение движка и потерянная ссылка на образец.
		pip.unique_name_in_owner = false
		_pips.add_child(pip)


## Карточка появилась в уже открытом графе. Анимацию держит она сама, а не граф:
## это её собственный вид, и подбирать его нужно там же, где её верстают.
func play_reveal() -> void:
	_effects.play(&"reveal")


## Ранг куплен: вспышка, золотая рамка по кромке, искры с этой же кромки и звук.
## Весь эффект живёт на карточке — вспыхивает и сыплет искрами именно она, а не
## граф вокруг неё.
##
## Здесь остался один вызов: КОГДА что происходит, сколько горит рамка, насколько
## тёплая вспышка и в какой момент бьют искры со звуком — дорожки анимации
## «unlock» в сцене. Это не перенос ради переноса: у эффекта из трёх кусков спор
## идёт о совпадении моментов, а совмещать их числами в коде значит подбирать
## тайминг вслепую. Искры и звук зовутся дорожкой методов, поэтому сдвинуть их
## по времени можно, не трогая скрипт.
func play_unlock_effect() -> void:
	_effects.play(&"unlock")


## Зовётся дорожкой методов анимации «unlock».
func _spawn_sparks() -> void:
	# Точку вылета держит узел-якорь в сцене, а не деление размера пополам в
	# коде: откуда бьют искры — решение того же порядка, что и где лежит подпись.
	var sparks: CPUParticles2D = SPARKS_SCENE.instantiate()
	_sparks_anchor.add_child(sparks)
	_emit_from_perimeter(sparks)
	sparks.emitting = true
	# Одноразовые частицы себя не убирают: сцена живёт, пока открыт экран, и
	# каждая покупка иначе оставляла бы после себя ещё один спящий узел.
	get_tree().create_timer(sparks.lifetime).timeout.connect(sparks.queue_free)


## Зовётся дорожкой методов анимации «unlock».
func _play_unlock_sound() -> void:
	if unlock_event.is_empty():
		return
	AudioManager.play_event_ui(unlock_event)


## Искры вылетают с КРОМКИ карточки, а не из её середины: горит рамка, значит и
## сыпаться должно с неё — иначе два куска одного эффекта спорят, где событие.
##
## Периметр раскладывается точками вылета (DIRECTED_POINTS), у каждой своя
## нормаль наружу, поэтому искра отталкивается от своей стороны, а не летит в
## случайную сторону из общего центра. Считается кодом, потому что зависит от
## размера карточки, а он приходит из её же сцены.
func _emit_from_perimeter(sparks: CPUParticles2D) -> void:
	var half := size * 0.5
	var corners := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])

	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	for i in corners.size():
		var from := corners[i]
		var edge := corners[(i + 1) % corners.size()] - from
		# Vector2.orthogonal() — это (y, -x), а стороны перечислены по часовой
		# стрелке в экранных координатах (Y вниз), поэтому ортогональ ребра и
		# есть нормаль НАРУЖУ. Знак здесь легко перепутать, и цена ошибки тихая:
		# искры не пропадут, а посыплются внутрь карточки.
		var normal := edge.normalized().orthogonal()
		var steps := maxi(1, int(edge.length() / maxf(spark_perimeter_step, 1.0)))
		for step in steps:
			points.append(from + edge * (float(step) / float(steps)))
			normals.append(normal)

	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_DIRECTED_POINTS
	sparks.emission_points = points
	sparks.emission_normals = normals


## Состояние приносит граф: ранг, «можно ли купить прямо сейчас» и показан ли
## навык лишь предпросмотром. [param requirement_hint] — чего не хватает; граф
## складывает его из требований, потому что имена соседних навыков знает он.
func refresh(
	rank: int, unlockable: bool, is_preview: bool = false, requirement_hint: String = ""
) -> void:
	_rank = rank
	var was_previewed := previewed
	previewed = is_preview
	var maxed := rank >= definition.max_rank

	if previewed:
		# Стоимость не показывается намеренно: пока условие не выполнено, цена
		# игроку не решение, а шум — ему нужно знать, ЧТО открывает навык.
		_status.text = preview_status_text
	elif maxed:
		_status.text = maxed_status_text
	else:
		_status.text = _points_text(definition.cost_for_next_rank(rank))

	# disabled, а не своя проверка в обработчике нажатия: нужен именно
	# «выключенный» вид из темы, а подсказка на disabled-кнопке всё равно
	# показывается — она про наведение, а не про нажатие.
	disabled = previewed or maxed or not unlockable
	if was_previewed and not previewed:
		# Узел не появился, а ОЖИЛ — это событие того же порядка, что и въезд
		# новой карточки, и мгновенная смена цвета читалась бы как перерисовка.
		create_tween().tween_property(
			self, "modulate", Color(Color.WHITE, modulate.a), ungrey_duration
		)
	else:
		modulate = Color(preview_tint if previewed else Color.WHITE, modulate.a)
	tooltip_text = _tooltip_for(rank, requirement_hint)
	_paint_pips()


## Подсказка при наведении. Пока это движковый tooltip с общей задержкой
## (gui/timers/tooltip_delay_sec) — свой таймер на 300 мс заведён отдельной
## задачей версии; здесь важно лишь то, что подсказка висит на ВСЕЙ карточке.
func _tooltip_for(rank: int, requirement_hint: String) -> String:
	var lines := PackedStringArray([definition.display_name])
	if not definition.description.is_empty():
		lines.append(definition.description)
	if previewed:
		# Ради этой строки предпросмотр и заведён: карточка обязана объяснить,
		# что именно откроет доступ, иначе серый узел — просто дразнилка.
		if not requirement_hint.is_empty():
			lines.append("Требуется: " + requirement_hint)
		return "\n".join(lines)
	if rank >= definition.max_rank:
		lines.append("Ранг %d/%d — максимум" % [rank, definition.max_rank])
	else:
		var cost := definition.cost_for_next_rank(rank)
		lines.append(
			"Ранг %d/%d · следующий за %s" % [rank, definition.max_rank, _points_text(cost)]
		)
	return "\n".join(lines)


## Цвет ветки кладётся делению в modulate, а не в его стилбокс: стилбокс в сцене
## ОДИН на все деления и на все карточки, и покраска через bg_color красила бы
## их все разом. Стилбокс остаётся белым образцом формы, цвет — на узле.
func _paint_pips() -> void:
	var empty := Color(accent, pip_empty_alpha)
	for i in _pips.get_child_count():
		var pip: Control = _pips.get_child(i)
		pip.modulate = accent if i < _rank else empty


## «1 очко / 2 очка / 5 очков» — стоимость показывается игроку, а не логу.
func _points_text(amount: int) -> String:
	var tail := amount % 100
	if tail >= 11 and tail <= 14:
		return "%d очков" % amount
	match amount % 10:
		1:
			return "%d очко" % amount
		2, 3, 4:
			return "%d очка" % amount
	return "%d очков" % amount
