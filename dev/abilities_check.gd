extends Node
## Проверка модели «возможность = компонент»: что умеет душа сама, что приходит с
## телом, что засыпает во плоти и что просыпается обратно.
## Запускать: godot --headless dev/abilities_check.tscn
##
## Берём НАСТОЯЩИЙ e_player.tscn: возможности души авторены в его сцене
## (component_resources), и на заглушке-Entity проверять было бы нечего.

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
## Ростовое тело: ходит и прыгает.
const WALKER_SCENE := "res://src/entities/body/e_body_walker.tscn"
## Тело другой высоты — им проверяется пересадка тело→тело.
const CRAWLER_SCENE := "res://src/entities/body/e_body_crawler.tscn"

var _ok := 0
var _fail := 0

## Сколько физкадров ещё прогнать. Считает _physics_process, а ставит _physics().
var _pending_ticks := 0


func _ready() -> void:
	var world := World.new()
	add_child(world)
	ECS.world = world

	# Полный набор систем группы "physics", как в world.tscn: проверка про то,
	# кого какая выборка забирает, и на неполном наборе она проверяла бы пустоту.
	for system in [
		S_BodySnatch.new(), S_Phasing.new(), S_Gravity.new(),
		S_Walk.new(), S_Jump.new(), S_Flight.new(), S_Movement.new(),
	]:
		system.group = "physics"
		world.add_system(system)

	world.add_observer(O_ExpelFromBody.new())
	world.add_observer(O_BodyVisual.new())
	world.add_observer(O_BodyForm.new())
	world.add_observer(O_SoulTraits.new())

	await _run(world)

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run(world: World) -> void:
	# --- 1. Возможности души авторены в сцене ------------------------------
	# Не в define_components(): у C_Flight есть числа, и тюнить их полагается в
	# инспекторе. Заодно это единственный источник, из которого O_SoulTraits
	# потом собирает их обратно.
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	_check(
		"возможности души лежат в сцене, а не в коде",
		player.soul_traits().size() == 2,
		str(player.soul_traits())
	)

	world.add_entity(player)
	await get_tree().process_frame

	_check("призрак умеет летать", player.has_component(C_Flight), "")
	_check("призрак проходит сквозь решётки", player.has_component(C_Phasing), "")
	_check("призрак не ходит", not player.has_component(C_Walk), "")
	_check("призраку нечем прыгать", not player.has_component(C_Jump), "")

	# --- 2. Во плоти возможности души засыпают -----------------------------
	var walker := _spawn_body(world, WALKER_SCENE, Vector3(6.0, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var bs := player.get_component(C_BodySnatch) as C_BodySnatch
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame

	_check("захват состоялся", player.has_component(C_Embodied), "")
	_check("во плоти летать нечем", not player.has_component(C_Flight), "")
	_check("во плоти сквозь решётки не пройти", not player.has_component(C_Phasing), "")
	_check("тело дало ходьбу", player.has_component(C_Walk), "")
	_check("тело дало прыжок", player.has_component(C_Jump), "")

	# --- 3. Пересадка тело→тело не теряет возможности души -----------------
	# Главная ловушка модели: буфер коалесцирует remove+add C_Embodied в один
	# переезд архетипа, и снятия наблюдатель может не увидеть. Заначка,
	# сделанная при вселении, осталась бы тут пустой — поэтому её и нет.
	var crawler := _spawn_body(world, CRAWLER_SCENE, Vector3(-6.0, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame

	_check("пересадка состоялась", player.has_component(C_Embodied), "")
	_check("после пересадки летать всё ещё нечем", not player.has_component(C_Flight), "")
	_check("после пересадки тело даёт ходьбу", player.has_component(C_Walk), "")
	# У ползуна нет C_Jump — и это значимое отсутствие, а не недоделанный пресет.
	_check(
		"безногому телу прыгать нечем",
		not player.has_component(C_Jump),
		"C_Jump прошлого тела остался на душе (ползун %s его не даёт)" % crawler
	)

	# --- 4. Развоплощение будит возможности души ---------------------------
	O_ExpelFromBody.expel(player, true)
	await get_tree().process_frame

	_check("душа снова летает", player.has_component(C_Flight), "")
	_check("душа снова проходит сквозь решётки", player.has_component(C_Phasing), "")
	_check("ходьба ушла вместе с телом", not player.has_component(C_Walk), "")
	var flight := player.get_component(C_Flight) as C_Flight
	_check(
		"числа полёта вернулись авторские, а не обнулённые",
		flight != null and flight.speed > 0.0 and flight.acceleration > 0.0,
		str(flight.speed) if flight else "нет C_Flight"
	)

	# Второй круг: возможности не должны «износиться» за цикл вселение-выход.
	var walker2 := _spawn_body(world, WALKER_SCENE, Vector3(0.0, 0.0, 6.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame
	_check("второе вселение снова усыпляет полёт", not player.has_component(C_Flight), str(walker2))
	O_ExpelFromBody.expel(player, true)
	await get_tree().process_frame
	_check("второй выход снова его будит", player.has_component(C_Flight), "")

	# --- 5. Системы возможностей: кто кого забирает ------------------------
	# Проверяем ПОВЕДЕНИЕ, а не устройство запросов: разъедется первым делом
	# именно запрос, но увидеть это надо так, как увидит игрок.
	var vel := player.get_component(C_Velocity) as C_Velocity
	var inp := player.get_component(C_PlayerInput) as C_PlayerInput

	# Призрак висит в воздухе: гравитация объявлена with_none([C_Flight]).
	vel.velocity = Vector3.ZERO
	await _physics(3)
	_check(
		"призрак не падает — гравитация мимо летящего",
		is_zero_approx(vel.velocity.y),
		str(vel.velocity.y)
	)

	# Защёлка прыжка гасится даже у того, кому прыгать нечем: иначе нажатие,
	# сделанное призраком, сработает в тот самый миг, когда он вселится.
	inp.jump_pressed = true
	await _physics(1)
	_check("нажатие прыжка не доживает до следующего тела", not inp.jump_pressed, "")

	# Во плоти — наоборот: летать нечем, значит тянет вниз.
	var walker3 := _spawn_body(world, WALKER_SCENE, Vector3(0.0, 0.0, -6.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame
	vel.velocity = Vector3.ZERO
	await _physics(3)
	_check(
		"во плоти тянет вниз — гравитация берёт того, кто не летит",
		vel.velocity.y < 0.0,
		"%.3f (тело %s)" % [vel.velocity.y, walker3]
	)

	# --- 6. Загрузка сейва — второй вход в воплощение ----------------------
	# Воплощают душу ДВА пути: захват и RunManager._restore_embodiment. Правило,
	# расписанное в обоих, разъезжается молча — на этом уже обожглись с посадкой
	# облика. Поэтому усыпление сидит на наблюдателе, и проверяем мы именно
	# второй путь: свежая душа + C_Embodied, поставленный НАПРЯМУЮ, без захвата.
	var loaded := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(loaded)
	await get_tree().process_frame
	_check("свежая душа при загрузке летает", loaded.has_component(C_Flight), "")

	var embodied := C_Embodied.new()
	embodied.body_scene_path = WALKER_SCENE
	loaded.add_component(embodied)
	for worn in E_Body.traits_of_scene(WALKER_SCENE):
		loaded.add_component(worn)
	await get_tree().process_frame

	_check("загруженный во плоти не летает", not loaded.has_component(C_Flight), "")
	_check(
		"загруженный во плоти не проходит сквозь решётки",
		not loaded.has_component(C_Phasing),
		""
	)
	_check("загруженный во плоти ходит телом", loaded.has_component(C_Walk), "")

	O_ExpelFromBody.expel(loaded, true)
	await get_tree().process_frame
	_check("выход из загруженного тела возвращает полёт", loaded.has_component(C_Flight), "")

	# В реальной игре E_Player всегда одна (RunManager._spawn_player проверяет
	# _get_player() != null перед созданием новой). Оставь мы «loaded» в мире —
	# любой код, ищущий игрока по C_PlayerInput без явной ссылки (как это делает
	# HUD ниже), стал бы находить произвольную из двух и путаться. Убираем сразу
	# после того, как её сценарий отыгран.
	world.remove_entity(loaded)

	# --- 7. Прыжок на настоящем полу --------------------------------------
	# Всё выше проверяло ОТСУТСТВИЕ возможностей. Прыжок надо проверить и с той
	# стороны: он единственная механика, которую разнос двигал вместе с порядком
	# систем (S_Gravity объявлен Runs.Before: [S_Jump]), и перепутанный порядок
	# съел бы его молча. Пол ставим только здесь: раньше он мешал бы проверке
	# «влезает ли тело» на месте самих тел.
	# Кладём пол ровно под подошвы там, где риг сейчас стоит: угадывать высоту
	# нельзя — она зависит от габарита надетого тела. Площадка узкая (6×6), а не
	# во всю сцену: тела ниже по файлу вселяются в других точках, и широкий пол
	# зацепил бы их капсулы верхней гранью ровно по y=0 — та же высота, на которой
	# стоят тела, — и `_fits` решал бы, что вселяться некуда, ВООБЩЕ ВЕЗДЕ.
	var floor_node := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 4.0, 6.0)
	floor_node.position = Vector3(
		player.global_position.x,
		player.global_position.y - player.foot_offset().y - box.size.y * 0.5,
		player.global_position.z
	)
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = box
	floor_node.add_child(floor_shape)
	add_child(floor_node)
	await _physics(20)  # дать телу осесть на пол

	var body_node := player as Node as CharacterBody3D
	_check("во плоти стоим на полу", body_node.is_on_floor(), str(player.global_position))
	inp.jump_pressed = true
	await _physics(1)
	_check(
		"прыжок с пола поднимает — S_Jump отработал ПОСЛЕ гравитации",
		vel.velocity.y > 0.0,
		str(vel.velocity.y)
	)

	# --- 8. Обратная связь на недоступное действие --------------------------
	# Раньше S_Jump молча гасил защёлку у безногого тела. Теперь безногому телу
	# отвечают явно, а призраку — нет: по «Управлению» подниматься взглядом это
	# ЗАДУМАННОЕ поведение, а не урезанная возможность, и текст про «тело» был бы
	# враньём — тела у него как раз и нет.
	var crawler2 := _spawn_body(world, CRAWLER_SCENE, Vector3(6.0, 0.0, 6.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame
	# Проверяем ПЕРЕСАДКУ явно, не только «нет прыжка» — у ghost'а его тоже нет,
	# и по одному этому признаку пропущенный захват (напр. «не помещается») от
	# настоящей пересадки было бы не отличить.
	_check("сели в безногое тело для проверки отклика", player.has_component(C_Embodied), str(crawler2))
	_check("это тело действительно без прыжка", not player.has_component(C_Jump), str(crawler2))

	inp.jump_pressed = true
	await _physics(1)
	var msg := player.get_component(C_ScreenMessage) as C_ScreenMessage
	_check(
		"безногому телу отвечают явно, а не тишиной",
		msg != null and msg.text == "Этому телу нечем прыгать",
		str(msg.text) if msg else "нет C_ScreenMessage"
	)

	O_ExpelFromBody.expel(player, true)
	await get_tree().process_frame
	# Развоплощение C_ScreenMessage не трогает (сообщение живёт своим таймером,
	# не привязано к телу) — сносим руками, иначе следующая проверка увидела бы
	# старое сообщение и решила, что призраку ответили, хотя это эхо прошлого.
	if player.has_component(C_ScreenMessage):
		player.remove_component(player.get_component(C_ScreenMessage))
	inp.jump_pressed = true
	await _physics(1)
	_check(
		"призраку на попытку прыжка не отвечают — подниматься взглядом это не баг",
		player.get_component(C_ScreenMessage) == null,
		str(player.get_component(C_ScreenMessage))
	)

	# --- 9. HUD-раскладка: что риг умеет ПРЯМО СЕЙЧАС -----------------------
	# Не по script напрямую (у него @onready-узлы), а инстансом настоящей сцены —
	# иначе проверка прошла бы, ничего не проверяя про реальную разметку.
	var hud := (load("res://src/ui/hud/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	var abilities_panel := hud.get_node("Hud/AbilitiesPanel") as Control
	var move_label := hud.get_node("Hud/AbilitiesPanel/Abilities/MoveLabel") as Label
	var separator := hud.get_node("Hud/AbilitiesPanel/Abilities/HSeparator") as Control
	var jump_label := hud.get_node("Hud/AbilitiesPanel/Abilities/JumpLabel") as Label
	await get_tree().process_frame

	_check("HUD: призрак — «Полёт»", move_label.text == "Полёт", move_label.text)
	_check("HUD: у призрака нет строки прыжка", not jump_label.visible, "")
	_check(
		"HUD: у одинокого «Ход» разделителя нет",
		not separator.visible,
		"строк без прыжка не должно ничего разделять"
	)

	var walker4 := _spawn_body(world, WALKER_SCENE, Vector3(-6.0, 0.0, 6.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame

	_check("HUD: во плоти на ходячем теле — «Ход»", move_label.text == "Ход", move_label.text)
	_check(
		"HUD: у прыгучего тела строка прыжка есть и содержит клавишу",
		jump_label.visible and jump_label.text.contains("Прыжок"),
		jump_label.text
	)
	_check(
		"HUD: между Ход и Прыжок появился разделитель",
		separator.visible,
		"две видимые строки — разделителю пора появиться"
	)

	var crawler3 := _spawn_body(world, CRAWLER_SCENE, Vector3(0.0, 0.0, 12.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame

	_check(
		"HUD: у безногого тела строка прыжка пропадает, а не гаснет",
		not jump_label.visible,
		"тело %s" % crawler3
	)
	_check(
		"HUD: у безногого тела разделитель пропадает вместе с прыжком",
		not separator.visible,
		""
	)

	# --- 10. Подложки у подсказок появляются только при сообщении ----------
	# Раньше PanelContainer-обёртка не имела скрипта и висела на экране пустой
	# плашкой независимо от того, есть ли что показывать. Скрипт теперь на
	# самой подложке (см. hud_prompt.gd/hud_message.gd), и hide()/show() self
	# прячет ЕЁ целиком, а не только текст внутри.
	var prompt_panel := hud.get_node("Hud/PromptPanel") as Control
	var message_panel := hud.get_node("Hud/MessagePanel") as Control
	_check("HUD: подложка подсказки скрыта, пока подсказывать нечего", not prompt_panel.visible, "")
	_check("HUD: подложка сообщения скрыта, пока сообщений нет", not message_panel.visible, "")

	if player.has_component(C_ScreenMessage):
		player.remove_component(player.get_component(C_ScreenMessage))
	inp.jump_pressed = true
	await _physics(1)
	_check(
		"HUD: подложка сообщения появляется вместе с сообщением",
		message_panel.visible,
		str(player.get_component(C_ScreenMessage))
	)


## Гоняет группу "physics" из НАСТОЯЩЕГО _physics_process, как main.gd в игре.
##
## Не из корутины по physics_frame: этот сигнал приходит уже ПОСЛЕ шага физики, а
## Jolt крутится на своём потоке и наружу состояние тел не отдаёт —
## move_and_slide() оттуда роняет «Body state is inaccessible right now». Тот же
## запрет, по которому все кастующие лучи системы обязаны жить в группе "physics"
## (см. [[GECS и правила движка]]).
func _physics_process(delta: float) -> void:
	if _pending_ticks <= 0:
		return
	_pending_ticks -= 1
	ECS.process(delta, "physics")


## Прогоняет [param frames] физкадров и ждёт, пока они отработают.
func _physics(frames: int) -> void:
	_pending_ticks = frames
	while _pending_ticks > 0:
		await get_tree().physics_frame
	await get_tree().physics_frame  # последнему тику дать долететь


func _spawn_body(world: World, path: String, at: Vector3) -> Entity:
	# Entity наследует Node, поэтому до Node3D — через двойной каст, как в
	# S_BodySnatch._embody.
	var body := (load(path) as PackedScene).instantiate() as Entity
	(body as Node as Node3D).position = at
	world.add_entity(body)
	body.add_component(C_SnatchTargeted.new())
	return body


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
