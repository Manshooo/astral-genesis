# res://src/ui/bank_choice/bank_choice_screen.gd
## Банк полон, а душа поглотила ещё одну способность: заменить ячейку банка или не брать ([[HUD — спека]] §7б, макет 16). С паузой — выход из тела бывает посреди драки.
## Открывает UIManager по C_AbilityLoadout.pending; Esc — то же, что «Не брать». Ячейки банка — инстансы bank_choice_option.tscn. Вики: [[Захват тела]] §«Способности и слоты».
class_name UI_BankChoiceScreen
extends UI_MenuScreen

const OPTION_SCENE := preload("res://src/ui/bank_choice/bank_choice_option.tscn")

@onready var _cell: UI_AbilityCell = %Cell
@onready var _name: Label = %Name
@onready var _origin: Label = %Origin
@onready var _options: HBoxContainer = %Options

var _soul: Entity
var _loadout: C_AbilityLoadout
var _resolved := false


func setup(soul: Entity, loadout: C_AbilityLoadout) -> void:
	_soul = soul
	_loadout = loadout
	var offered: C_Ability = loadout.pending.front()
	_cell.show_ability(UI_AbilityCell.State.SOUL, offered)
	_cell.glowing = true
	_name.text = tr(offered.name_key)
	_origin.text = origin_line(offered)
	for i in loadout.bank.size():
		var option: UI_BankChoiceOption = OPTION_SCENE.instantiate()
		_options.add_child(option)
		option.setup(loadout.bank[i])
		option.chosen.connect(choose.bind(i))
		if i == 0:
			first_focus = option.button()


## «слот 2 · Гончая»: тело в именительном — склонять имена видов ключами было бы на каждый язык своё.
static func origin_line(ability: C_Ability) -> String:
	if ability.source_key == &"":
		return TranslationServer.translate("HUD_BANK_SLOT") % ability.slot
	return TranslationServer.translate("HUD_BANK_ORIGIN") % [ability.slot, TranslationServer.translate(ability.source_key)]


func _on_skip_pressed() -> void:
	choose(-1)


## [param index] — ячейка банка под замену, -1 — не брать.
func choose(index: int) -> void:
	if _resolved:
		return
	_resolved = true
	var offered: C_Ability = _loadout.pending.front()
	_loadout.resolve_pending(index)
	var key := "HUD_MSG_ABILITY_BANKED" if index >= 0 else "HUD_MSG_ABILITY_DROPPED"
	C_ScreenMessage.show_on(_soul, O_ExpelFromBody.tr_line(key, offered))
	UIManager.close_top()


## Закрыли мимо кнопок (Esc, смена сцены) — значит «не брать»: очередь не должна пережить экран.
func on_closed() -> void:
	if not _resolved and is_instance_valid(_soul) and not _loadout.pending.is_empty():
		_resolved = true
		_loadout.resolve_pending(-1)
