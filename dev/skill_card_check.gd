extends "res://dev/check_harness.gd"
## Проверка экрана навыков вокруг карточки (§9 «Меню — спека»): карточка
## выбранного навыка не уходит за низ экрана ни на одном навыке боевого дерева,
## ни по-русски, ни по-английски; кнопка называет ровно ту причину, по которой
## ранг не купить; вкладка Архитектора не видна до первой встречи с ним;
## эссенция с тысячи пишется «тыс.».
## Запускать: godot --headless dev/skill_card_check.tscn
##
## Это проверка с Control'ами, и намеренно: она про ПИКСЕЛИ — как тема, шрифт и
## длина описания складываются в высоту карточки. Длинное описание на одном
## навыке из десяти глазами не заметишь, а headless видит все сразу — и те, что
## появятся позже.
##
## Сейвы SkillManager и ArchitectManager на время проверки подменяются
## заглушками и возвращаются на место: прогресс игрока к геометрии карточки
## отношения не имеет, а покупка здесь не зовётся — сейв не пишется.

const SCREEN_SCENE := preload("res://src/ui/skill_tree/skill_tree_ui.tscn")
const SCREEN_HEIGHT := 720.0

var _original_soul: PlayerSkillSave
var _original_architect: PlayerSkillSave
var _original_locale: String


func _ready() -> void:
	_original_soul = SkillManager.save
	_original_architect = ArchitectManager.save
	_original_locale = TranslationServer.get_locale()

	await _run()

	SkillManager.save = _original_soul
	ArchitectManager.save = _original_architect
	TranslationServer.set_locale(_original_locale)
	_finish()


func _run() -> void:
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		await _check_card_fits(locale)
	TranslationServer.set_locale("ru")
	await _check_reasons()
	await _check_architect_tab()


## Карточка — колонка шириной 340 с переносом по словам: длинное описание растит
## её вниз. Ниже края экрана — значит кнопку покупки не видно.
func _check_card_fits(locale: String) -> void:
	var soul := PlayerSkillSave.new()
	soul.skill_points = 9
	SkillManager.save = soul
	var screen := await _open(SkillManager)
	var graph := screen._graph
	var card := screen._card
	var overflow := PackedStringArray()
	for def in SkillManager.SKILL_TREE.skills:
		# Карточка показывает любой навык дерева, а не только видимый: выбор идёт
		# через экран, и проверять надо все тексты, что есть в данных.
		screen._show_card(def.id)
		await get_tree().process_frame
		var bottom := card.get_global_rect().end.y
		if bottom > SCREEN_HEIGHT:
			overflow.append("%s → низ %.0f" % [def.id, bottom])
		if card.size.x > 341.0:
			var widest := ""
			for child in card.get_children():
				if (child as Control).get_combined_minimum_size().x > 340.0:
					widest += "%s=%.0f " % [child.name, (child as Control).get_combined_minimum_size().x]
			overflow.append("%s → ширина %.0f (%s)" % [def.id, card.size.x, widest])
	_check("%s: карточка влезает в экран на каждом навыке" % locale, overflow.is_empty(), ", ".join(overflow))
	_check("%s: при открытии выбран навык" % locale, graph.selected_id() != &"", "ничего не выбрано")
	screen.queue_free()
	await get_tree().process_frame


## Кнопка либо открывает ранг, либо называет причину — и именно ту, что есть:
## «не хватает очков» при невыполненных требованиях отправила бы игрока копить
## очки, которые ему не помогут.
func _check_reasons() -> void:
	var soul := PlayerSkillSave.new()
	soul.skill_points = 0
	soul.ranks = {&"body_snatch": 3}
	SkillManager.save = soul
	var screen := await _open(SkillManager)
	var button: Button = screen._card._button

	screen._show_card(&"body_snatch")
	_check("освоенный навык — «Освоено полностью»", button.text == "SKILL_MAXED" and button.disabled, button.text)

	screen._show_card(&"capture_precision")
	_check("без очков — «Не хватает очков»", button.text == "SKILL_NO_POINTS" and button.disabled, button.text)

	screen._show_card(&"overflow_control")
	_check("за требованием — «Сначала выполните требования»", button.text == "SKILL_LOCKED" and button.disabled, button.text)

	soul.skill_points = 5
	screen._show_card(&"capture_precision")
	_check("с очками — «Открыть ранг 1»", button.text == tr("SKILL_UNLOCK") % 1 and not button.disabled, button.text)
	screen.queue_free()
	await get_tree().process_frame


## Вкладка Архитектора — только после встречи (решение 02.10): до неё игрок не
## знает, что такое эссенция. Встреча открывает её с любой точки входа.
func _check_architect_tab() -> void:
	SkillManager.save = PlayerSkillSave.new()
	var stranger := PlayerSkillSave.new()
	ArchitectManager.save = stranger
	var screen := await _open(SkillManager)
	_check("до встречи с Архитектором его вкладки нет", not screen._tab_architect.visible, "вкладка видна")
	screen.queue_free()
	await get_tree().process_frame

	var met := PlayerSkillSave.new()
	met.met = true
	met.skill_points = 12400
	ArchitectManager.save = met
	screen = await _open(SkillManager)
	_check("после встречи вкладка есть и у инкубатора", screen._tab_architect.visible, "вкладки нет")
	screen._tab_architect.pressed.emit()
	await get_tree().process_frame
	_check("эссенция с тысячи — «тыс.»", screen._wallet_value.text == tr("SKILL_THOUSANDS") % "12,4",
			screen._wallet_value.text)
	screen.queue_free()
	await get_tree().process_frame

	# Сейв, записанный до поля met: встречу помнят ранги.
	var legacy := PlayerSkillSave.new()
	legacy.ranks = {&"map_level": 1}
	ArchitectManager.save = legacy
	_check("старый сейв с рангами Архитектора считается встречей", ArchitectManager.is_met(), "не считается")


func _open(manager) -> SkillTreeUI:
	var screen: SkillTreeUI = SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.setup(manager, manager.SKILL_TREE)
	await get_tree().process_frame
	await get_tree().process_frame
	return screen
