extends "res://dev/check_harness.gd"
## Проверка экрана показателей и переноса из банка: перенос в пустой слот и обмен
## с занятым, прирастание (способность спит и не применяется, потом просыпается),
## отказ в закрытый слот и в бою (урон за последние combat_window секунд), сейв
## посреди прирастания. Плюс экран: строки колонок и слотов, два клика при
## нескольких открытых слотах, отказ строкой на самом экране, удержание клавиши
## через UIManager и слоты HUD в полную силу, пока экран открыт.
## Запускать: godot --headless dev/stats_panel_check.tscn
##
## На диск проверка не пишет: WorldSave.record_abilities трогает только сейв в
## памяти, его поля возвращаются в конце.

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const HOUND_SCENE := "res://src/entities/body/e_body_hound.tscn"
const HUD_SCENE := "res://src/ui/hud/hud.tscn"
const PANEL_SCENE := "res://src/ui/stats_panel/stats_panel.tscn"


## Разные классы — разные способности: душа не берёт вторую копию того же класса.
class FakeDash:
	extends C_Ability


class FakeShield:
	extends C_Ability


func _ready() -> void:
	var saved_slots := WorldSave.save.ability_slots
	var saved_bank := WorldSave.save.ability_bank

	var world := _new_world()
	_add_systems(world, "gameplay", [
		S_AbilityLoadout.new(), S_Abilities.new(), S_Regeneration.new(), S_Health.new(),
	])
	world.add_observer(O_CombatMark.new())

	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	await get_tree().process_frame
	var loadout := player.get_component(C_AbilityLoadout) as C_AbilityLoadout

	_check_move_into_empty(player, loadout)
	_check_swap_and_graft(player, loadout)
	_check_refusals(player, loadout)
	_check_save_mid_graft(player, loadout)
	await _check_panel(player, loadout)
	await _check_hold(player, loadout)

	WorldSave.save.ability_slots = saved_slots
	WorldSave.save.ability_bank = saved_bank
	_finish()


func _regeneration() -> C_Regeneration:
	for component in E_Body.traits_of_scene(HOUND_SCENE):
		if component is C_Regeneration:
			return component
	return null


## Слоты и банк задаются прямо, мимо поглощения: проверка о переносе, а не о том, куда кладёт выход.
func _arrange(loadout: C_AbilityLoadout, slot: C_Ability, bank: Array[C_Ability]) -> void:
	var slots: Array[C_Ability] = [slot, null, null, null]
	loadout.slots = slots
	loadout.bank = bank
	loadout.combat_left = 0.0


func _tick(seconds: float, step: float = 0.1) -> void:
	var left := seconds
	while left > 0.0001:
		ECS.process(minf(step, left), "gameplay")
		left -= step


func _check_move_into_empty(player: Entity, loadout: C_AbilityLoadout) -> void:
	var dash := FakeDash.new().absorbed_copy(&"BODY_HOUND")
	_arrange(loadout, null, [dash])
	var slots_before := loadout.slots
	var result := loadout.bank_to_slot(player, 0, 1)
	_check("перенос в пустой слот проходит", result == C_AbilityLoadout.Transfer.DONE, str(result))
	_check("перенесённая в слоте, банк опустел", loadout.slots[0] == dash and loadout.bank.is_empty(), "")
	_check("массивы пересобраны, а не правлены на месте", not is_same(loadout.slots, slots_before) and slots_before[0] == null,
		str(slots_before))
	_check("перенесённая прирастает ability_graft_time",
		is_equal_approx(dash.graft_left, GameConfig.config.ability_graft_time), str(dash.graft_left))


func _check_swap_and_graft(player: Entity, loadout: C_AbilityLoadout) -> void:
	var shield := FakeShield.new().absorbed_copy(&"BODY_HOUND")
	shield.graft_left = 1.0
	var regen := _regeneration().absorbed_copy(&"BODY_HOUND")
	var dash := FakeDash.new().absorbed_copy(&"BODY_HOUND")
	_arrange(loadout, shield, [regen, dash])
	loadout.bank_to_slot(player, 0, 1)
	_check("занятый слот меняется местами с ячейкой банка",
		loadout.slots[0] == regen and loadout.bank[0] == shield and loadout.bank[1] == dash,
		"%s / %s" % [loadout.slots, loadout.bank])
	_check("ушедшая в банк больше не прирастает", shield.graft_left == 0.0, str(shield.graft_left))

	_tick(0.1)
	_check("пока прирастает — спит, не компонент", player.get_component(C_Regeneration) == null, "")
	var inp := player.get_component(C_PlayerInput) as C_PlayerInput
	inp.ability_pressed = 1
	_tick(0.1)
	var message := player.get_component(C_ScreenMessage) as C_ScreenMessage
	_check("нажатие во время прирастания — мысль, а не применение",
		message != null and message.text == "HUD_MSG_ABILITY_GRAFTING" and not regen.requested,
		message.text if message else "нет мысли")

	_tick(GameConfig.config.ability_graft_time)
	_check("приросла — отсчёт обнулён", regen.graft_left == 0.0, str(regen.graft_left))
	_check("приросла — проснулась компонентом", player.get_component(C_Regeneration) == regen, "")
	# Регенерация вне тела не применяется — довольно, что она проснулась; снять её, чтобы дальше не мешала.
	_arrange(loadout, null, [])
	_tick(0.1)


func _check_refusals(player: Entity, loadout: C_AbilityLoadout) -> void:
	var dash := FakeDash.new().absorbed_copy()
	_arrange(loadout, null, [dash])
	var result := loadout.bank_to_slot(player, 0, 2)
	_check("в закрытый слот перенос не идёт", result == C_AbilityLoadout.Transfer.LOCKED
		and loadout.bank.size() == 1 and loadout.slots[1] == null, str(result))

	# Урон по телу — настоящим путём: S_Health.deal_damage шлёт damage_dealt, его ловит O_CombatMark.
	for worn in E_Body.traits_of_scene(HOUND_SCENE):
		if not worn is C_Ability:
			player.add_component(worn)
	S_Health.deal_damage(player, 1.0)
	_check("урон по игроку открывает окно боя",
		is_equal_approx(loadout.combat_left, GameConfig.config.combat_window), str(loadout.combat_left))
	result = loadout.bank_to_slot(player, 0, 1)
	_check("в бою перенос не идёт", result == C_AbilityLoadout.Transfer.IN_COMBAT
		and loadout.slots[0] == null and loadout.bank.size() == 1, str(result))
	_tick(GameConfig.config.combat_window + 0.1)
	_check("окно боя истекло", loadout.combat_left == 0.0, str(loadout.combat_left))
	result = loadout.bank_to_slot(player, 0, 1)
	_check("после боя перенос проходит", result == C_AbilityLoadout.Transfer.DONE, str(result))
	for worn in E_Body.worn_by(player):
		player.remove_component(worn)


func _check_save_mid_graft(player: Entity, loadout: C_AbilityLoadout) -> void:
	var regen := _regeneration().absorbed_copy(&"BODY_HOUND")
	_arrange(loadout, null, [regen])
	loadout.bank_to_slot(player, 0, 1)
	regen.graft_left = 1.5
	WorldSave.record_abilities(loadout.slots, loadout.bank)
	var restored := C_AbilityLoadout.new()
	RunManager._restore_abilities(restored, WorldSave.save)
	_check("сейв посреди прирастания: остаток пережил загрузку",
		restored.slots[0] is C_Regeneration and is_equal_approx(restored.slots[0].graft_left, 1.5),
		str(restored.slots[0].graft_left) if restored.slots[0] else "слот пуст")
	_arrange(loadout, null, [])
	_tick(0.1)


func _panel(player: Entity, loadout: C_AbilityLoadout) -> UI_StatsPanel:
	var panel := (load(PANEL_SCENE) as PackedScene).instantiate() as UI_StatsPanel
	add_child(panel)
	panel.setup(player, loadout)
	return panel


func _item(panel: UI_StatsPanel, path: String) -> UI_StatsAbilityItem:
	return panel.get_node("Content/Column/" + path) as UI_StatsAbilityItem


func _label(item: UI_StatsAbilityItem, which: String) -> String:
	return (item.get_node(which) as Label).text


func _check_panel(player: Entity, loadout: C_AbilityLoadout) -> void:
	var regen := _regeneration().absorbed_copy(&"BODY_HOUND")
	var dash := FakeDash.new().absorbed_copy(&"BODY_HOUND")
	_arrange(loadout, null, [regen, dash])
	var panel := _panel(player, loadout)
	await get_tree().process_frame

	var no_body := panel.get_node("%NoBody") as Label
	_check("экран: вне тела колонка тела говорит «без тела», HP скрыт",
		no_body.visible and not (panel.get_node("%HealthRow") as Control).visible, "")
	_check("экран: стабильность в м:сс",
		RegEx.create_from_string("^\\d+:\\d\\d$").search((panel.get_node("%StabilityValue") as Label).text) != null,
		(panel.get_node("%StabilityValue") as Label).text)
	var slot2 := _item(panel, "Abilities/Slots/Slot2")
	_check("экран: слот 2 закрыт и называет свою ветку",
		slot2.cell().state == UI_AbilityCell.State.LOCKED
			and _label(slot2, "Sub") != "", _label(slot2, "Sub"))
	var bank3 := _item(panel, "Bank/BankCells/Bank3")
	_check("экран: третья ячейка банка закрыта навыком души",
		bank3.cell().state == UI_AbilityCell.State.LOCKED, "")

	# Один открытый слот — выбирать нечего: клик по банку ставит сразу.
	panel.pick_bank(0)
	await get_tree().process_frame
	var slot1 := _item(panel, "Abilities/Slots/Slot1")
	_check("экран: один открытый слот — клик по банку ставит сразу", loadout.slots[0] == regen, "")
	regen.graft_left = GameConfig.config.ability_graft_time / 2.0
	panel.render()
	var grafting := _label(slot1, "Sub")
	_check("экран: прирастание видно — заливка до середины и своя строка",
		is_equal_approx(slot1.cell().graft_share, 0.5) and slot1.cell().state == UI_AbilityCell.State.SOUL
			and grafting == UI_StatsPanel.origin_line(regen), "share=%s" % slot1.cell().graft_share)
	regen.graft_left = 0.0
	panel.render()
	_check("экран: приросшая подписана иначе, без заливки",
		_label(slot1, "Sub") != grafting and slot1.cell().graft_share == 0.0, _label(slot1, "Sub"))

	# Два открытых слота — два клика: банк выделяет, слот принимает.
	var mods := player.get_component(C_StatModifiers) as C_StatModifiers
	mods.set_source(&"check", {C_StatModifiers.ABILITY_SLOTS: 1.0}, {})
	panel.pick_bank(0)
	_check("экран: при двух слотах клик по банку только выделяет",
		panel.picked == 0 and loadout.bank[0] == dash, str(panel.picked))
	panel.pick_slot(2)
	_check("экран: второй клик ставит в выбранный слот",
		loadout.slots[1] == dash and loadout.bank.is_empty() and panel.picked == -1, "")
	mods.clear_source(&"check")

	# Отказ — мыслью на игроке и строкой на самом экране: мысль HUD лежит под затемнением.
	var shield := FakeShield.new().absorbed_copy()
	_arrange(loadout, null, [shield])
	panel.place(0, 3)
	await get_tree().process_frame
	var message := player.get_component(C_ScreenMessage) as C_ScreenMessage
	var refusal := panel.get_node("%Refusal") as Label
	_check("экран: в закрытый слот — отказ мыслью",
		message != null and message.text == "HUD_MSG_SLOT_LOCKED", message.text if message else "нет мысли")
	_check("экран: отказ повторён строкой на экране",
		refusal.visible and message != null and refusal.text == tr(message.text), refusal.text)
	panel.queue_free()
	_arrange(loadout, null, [])
	await get_tree().process_frame


## Удержание: UIManager открывает экран по нажатию и закрывает, когда клавишу отпустили; ввод игрока блокирован без паузы.
func _check_hold(player: Entity, loadout: C_AbilityLoadout) -> void:
	_arrange(loadout, null, [])
	var hud := (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	var hud_slots := hud.get_node("Hud/AbilitySlots") as UI_HudAbilitySlots
	await get_tree().process_frame
	await get_tree().process_frame

	UIManager.enabled = true
	Input.action_press(UI_StatsPanel.ACTION)
	var panel := UIManager.open_stats_panel()
	await get_tree().process_frame
	_check("удержание: экран открыт", panel != null and UI_StatsPanel.is_open(get_tree()), "")
	_check("удержание: ввод игрока заблокирован", player.has_component(C_UIBlocked), "")
	_check("удержание: без паузы", not get_tree().paused, "")
	_check("удержание: слоты HUD в полную силу", hud_slots.target_alpha == 1.0, str(hud_slots.target_alpha))

	Input.action_release(UI_StatsPanel.ACTION)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("отпустили — экран закрыт", not UIManager.has_screens() and not UI_StatsPanel.is_open(get_tree()), "")
	_check("отпустили — ввод вернулся", not player.has_component(C_UIBlocked), "")
	UIManager.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.queue_free()
