# res://src/ui/ability_choice/ability_choice_screen.gd
## Банк полон, а душа поглотила ещё одну способность: заменить ячейку банка или не брать (решение 22.10). С паузой — выход из тела бывает посреди драки.
## Открывает UIManager по C_AbilityLoadout.pending; Esc — то же, что «Не брать». Вики: [[Захват тела]] §«Способности и слоты».
class_name UI_AbilityChoiceScreen
extends UI_MenuScreen

const OPTION_SCENE := preload("res://src/ui/ability_choice/ability_choice_option.tscn")

@onready var _offer: Label = %Offer
@onready var _options: VBoxContainer = %Options

var _soul: Entity
var _loadout: C_AbilityLoadout
var _resolved := false


func setup(soul: Entity, loadout: C_AbilityLoadout) -> void:
	_soul = soul
	_loadout = loadout
	var offered: C_Ability = loadout.pending.front()
	_offer.text = tr("ABILITY_CHOICE_NEW") % tr(offered.name_key)
	for i in loadout.bank.size():
		var held := loadout.bank[i]
		var option: UI_EchoButton = OPTION_SCENE.instantiate()
		option.text = tr("ABILITY_CHOICE_REPLACE") % tr(held.name_key)
		option.pressed.connect(choose.bind(i))
		_options.add_child(option)
		if i == 0:
			first_focus = option


func _on_decline_pressed() -> void:
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
