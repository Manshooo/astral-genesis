extends "res://dev/check_harness.gd"
## Проверка слотов способностей: тело даёт способность в свой слот, чистый выход
## оставляет её душе, лишние уходят в банк, полный банк ждёт ответа игрока,
## тело главнее поглощённой, закрытый слот не срабатывает, Регенерация лечит,
## поглощённое переживает сейв. Плюс HUD: ячейки и эффекты «Бесплотности».
## Запускать: godot --headless dev/ability_slots_check.tscn
##
## На диск проверка не пишет: поглощение зовётся напрямую
## (O_ExpelFromBody.absorb_abilities), а не через выход, который начислил бы
## очко за «Чистый выход» в user://skills.tres; WorldSave.record_abilities
## трогает только сейв в памяти, и его поля возвращаются в конце.

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const HOUND_SCENE := "res://src/entities/body/e_body_hound.tscn"
const HUD_SCENE := "res://src/ui/hud/hud.tscn"
const CHOICE_SCENE := "res://src/ui/ability_choice/ability_choice_screen.tscn"


## Разные классы — разные способности: душа не берёт вторую копию того же класса.
class FakeDash:
	extends C_Ability


class FakeShield:
	extends C_Ability


class FakeHowl:
	extends C_Ability


class FakeSpit:
	extends C_Ability


func _ready() -> void:
	var saved_slots := WorldSave.save.ability_slots
	var saved_bank := WorldSave.save.ability_bank

	var world := _new_world()
	_add_systems(world, "gameplay", [
		S_AbilityLoadout.new(), S_Abilities.new(), S_Regeneration.new(), S_Health.new(),
	])

	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	await get_tree().process_frame
	var loadout := player.get_component(C_AbilityLoadout) as C_AbilityLoadout

	_check_hound_scene()
	_check_wear_and_absorb(player, loadout)
	_check_bank(player, loadout)
	await _check_regeneration(player)
	_check_slots_stat(player)
	_check_save_round_trip(loadout)
	await _check_hud(player, loadout)
	await _check_choice_screen(player, loadout)

	WorldSave.save.ability_slots = saved_slots
	WorldSave.save.ability_bank = saved_bank
	_finish()


## Гончая — первое тело со способностью: Регенерация в слоте 1 с черновыми числами 22.10.
func _check_hound_scene() -> void:
	var regen: C_Regeneration = null
	for component in E_Body.traits_of_scene(HOUND_SCENE):
		if component is C_Regeneration:
			regen = component
	_check("у Гончей есть Регенерация", regen != null, "")
	if regen == null:
		return
	_check("Регенерация в слоте 1", regen.slot == 1, "slot=%d" % regen.slot)
	_check("Регенерация: 30 % за 5 с, откат 20 с",
		is_equal_approx(regen.share, 0.3) and is_equal_approx(regen.seconds, 5.0)
			and is_equal_approx(regen.cooldown, 20.0),
		"share=%s seconds=%s cooldown=%s" % [regen.share, regen.seconds, regen.cooldown])
	_check("у Регенерации есть имя и иконка", regen.name_key != &"" and regen.icon != null, "")


func _wear_hound(player: Entity) -> void:
	for worn in E_Body.traits_of_scene(HOUND_SCENE):
		player.add_component(worn)


func _shed_body(player: Entity) -> void:
	for worn in E_Body.worn_by(player):
		player.remove_component(worn)


func _tick(seconds: float, step: float = 0.1) -> void:
	var left := seconds
	while left > 0.0001:
		ECS.process(minf(step, left), "gameplay")
		left -= step


func _check_wear_and_absorb(player: Entity, loadout: C_AbilityLoadout) -> void:
	_check("с начала забега открыт один слот", C_AbilityLoadout.open_slots(player) == 1,
		"open=%d" % C_AbilityLoadout.open_slots(player))
	_check("банк на две ячейки", C_AbilityLoadout.bank_size(player) == 2,
		"bank=%d" % C_AbilityLoadout.bank_size(player))

	_wear_hound(player)
	var view := loadout.view(player, 1)
	_check("во плоти слот 1 — способность тела", view.body is C_Regeneration and view.soul == null, "")

	O_ExpelFromBody.absorb_abilities(player)
	var absorbed := loadout.slots[0]
	_check("чистый выход кладёт способность в открытый слот души",
		absorbed is C_Regeneration and absorbed.absorbed, str(loadout.slots))
	_check("поглощённая — копия, а не компонент тела", absorbed != view.body, "")
	_check("поглощённая не уезжает с телом", not E_Body.is_wearable(absorbed), "")

	view = loadout.view(player, 1)
	_check("пока тело надето, поглощённая под ним спит", view.sleeping() and view.shown() == view.body, "")
	_tick(0.1)
	_check("тело главнее: компонент — способность тела",
		player.get_component(C_Regeneration) == view.body, "")

	_check("та же способность второй раз не берётся",
		loadout.absorb(player, view.body) == C_AbilityLoadout.Placement.KNOWN, "")

	_shed_body(player)
	_tick(0.1)
	_check("вне тела поглощённая просыпается компонентом души",
		player.get_component(C_Regeneration) == absorbed, "")

	var inp := player.get_component(C_PlayerInput) as C_PlayerInput
	inp.ability_pressed = 1
	_tick(0.1)
	var msg := player.get_component(C_ScreenMessage) as C_ScreenMessage
	_check("Регенерация без тела отвечает отказом, а не тишиной",
		msg != null and msg.text == "HUD_MSG_ABILITY_NEEDS_BODY", msg.text if msg else "нет")
	_check("отказ не тратит откат", absorbed.cooldown_left == 0.0, str(absorbed.cooldown_left))

	inp.ability_pressed = 2
	_tick(0.1)
	msg = player.get_component(C_ScreenMessage) as C_ScreenMessage
	_check("закрытый слот отвечает «ещё закрыт»",
		msg != null and msg.text == "HUD_MSG_SLOT_LOCKED", msg.text if msg else "нет")


func _check_bank(player: Entity, loadout: C_AbilityLoadout) -> void:
	_check("слоты полны — способность в банк",
		loadout.absorb(player, FakeDash.new()) == C_AbilityLoadout.Placement.BANK, "")
	_check("вторая — тоже в банк",
		loadout.absorb(player, FakeShield.new()) == C_AbilityLoadout.Placement.BANK, "")
	_check("банк полон — способность ждёт ответа игрока",
		loadout.absorb(player, FakeHowl.new()) == C_AbilityLoadout.Placement.BANK_FULL
			and loadout.pending.size() == 1, str(loadout.pending))

	var dropped := loadout.resolve_pending(0)
	_check("«заменить» ставит новую на место выбранной ячейки",
		loadout.bank[0] is FakeHowl and dropped is FakeDash and loadout.pending.is_empty(), str(loadout.bank))

	loadout.absorb(player, FakeSpit.new())
	loadout.resolve_pending(-1)
	_check("«не брать» оставляет банк как был",
		loadout.bank.size() == 2 and loadout.bank[0] is FakeHowl and loadout.bank[1] is FakeShield
			and loadout.pending.is_empty(), str(loadout.bank))


func _check_regeneration(player: Entity) -> void:
	_wear_hound(player)
	_tick(0.1)
	var regen := player.get_component(C_Regeneration) as C_Regeneration
	var health := player.get_component(C_Health) as C_Health
	health.current = 50.0
	var inp := player.get_component(C_PlayerInput) as C_PlayerInput
	inp.ability_pressed = 1
	_tick(0.1)
	_check("применение ставит откат", regen.cooldown_left > 19.0, str(regen.cooldown_left))
	_tick(5.0)
	var expected := 50.0 + 150.0 * 0.3
	_check("за 5 с вернулось 30 % максимума", absf(health.current - expected) < 1.0,
		"HP=%.1f, ждали %.1f" % [health.current, expected])
	_tick(1.0)
	_check("после конца лечение не идёт", absf(health.current - expected) < 1.0, "HP=%.1f" % health.current)

	inp.ability_pressed = 1
	health.current = 60.0
	_tick(0.1)
	_check("на откате нажатие пропадает", absf(health.current - 60.0) < 0.01, "HP=%.1f" % health.current)
	_shed_body(player)
	_tick(0.1)


func _check_slots_stat(player: Entity) -> void:
	var mods := player.get_component(C_StatModifiers) as C_StatModifiers
	mods.set_source(&"check", {C_StatModifiers.ABILITY_SLOTS: 1.0}, {})
	_check("стат ability_slots открывает слот 2", C_AbilityLoadout.open_slots(player) == 2, "")
	mods.clear_source(&"check")


func _check_save_round_trip(loadout: C_AbilityLoadout) -> void:
	WorldSave.record_abilities(loadout.slots, loadout.bank)
	var restored := C_AbilityLoadout.new()
	RunManager._restore_abilities(restored, WorldSave.save)
	_check("сейв: слот души вернулся поглощённой копией",
		restored.slots[0] is C_Regeneration and restored.slots[0].absorbed
			and restored.slots[0] != loadout.slots[0], str(restored.slots))
	_check("сейв: пустые слоты пустые", restored.slots.size() == 4 and restored.slots[1] == null, "")
	_check("сейв: банк вернулся", restored.bank.size() == 2, str(restored.bank))


func _check_hud(player: Entity, loadout: C_AbilityLoadout) -> void:
	var hud := (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	var slots := hud.get_node("Hud/AbilitySlots") as UI_HudAbilitySlots
	slots.render(player, loadout)
	var cells := hud.get_node("Hud/AbilitySlots/Slots").get_children()
	_check("HUD: четыре ячейки слотов", cells.size() == 4, str(cells.size()))
	_check("HUD: слот 1 — поглощённая", (cells[0] as UI_AbilityCell).state == UI_AbilityCell.State.SOUL, "")
	_check("HUD: слот 2 закрыт", (cells[1] as UI_AbilityCell).state == UI_AbilityCell.State.LOCKED, "")

	_wear_hound(player)
	slots.render(player, loadout)
	var first := cells[0] as UI_AbilityCell
	_check("HUD: во плоти слот 1 — тело, поглощённая спит",
		first.state == UI_AbilityCell.State.BODY and first.sleeping, "")
	_shed_body(player)
	_tick(0.1)

	var effects := UI_HudSoulEffects.active_effects(player)
	_check("HUD: вне тела «Бесплотность» показывает полёт и просачивание",
		effects.has("HUD_EFFECT_FLIGHT") and effects.has("HUD_EFFECT_PHASING"), str(effects))
	hud.queue_free()


func _check_choice_screen(player: Entity, loadout: C_AbilityLoadout) -> void:
	loadout.absorb(player, FakeDash.new())
	var screen := (load(CHOICE_SCENE) as PackedScene).instantiate() as UI_AbilityChoiceScreen
	add_child(screen)
	screen.setup(player, loadout)
	await get_tree().process_frame
	var options := screen.get_node("Content/Column/Options").get_child_count()
	_check("экран выбора: по кнопке на ячейку банка", options == loadout.bank.size(), str(options))
	screen.choose(1)
	_check("экран выбора: замена применилась", loadout.bank[1] is FakeDash and loadout.pending.is_empty(), "")

	loadout.absorb(player, FakeSpit.new())
	var closed := (load(CHOICE_SCENE) as PackedScene).instantiate() as UI_AbilityChoiceScreen
	add_child(closed)
	closed.setup(player, loadout)
	closed.on_closed()
	_check("экран закрыли мимо кнопок — «не брать»", loadout.pending.is_empty() and not _bank_has(loadout, FakeSpit), "")
	screen.queue_free()
	closed.queue_free()


func _bank_has(loadout: C_AbilityLoadout, type: Script) -> bool:
	for held in loadout.bank:
		if held.get_script() == type:
			return true
	return false
