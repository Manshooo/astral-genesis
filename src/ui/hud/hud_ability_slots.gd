# res://src/ui/hud/hud_ability_slots.gd
## Слоты способностей 1–4 над шкалой здоровья и банк правее ([[HUD — спека]] §7б): что в каком слоте, откуда (тело или поглощена), что спит, что закрыто и что на откате.
## Поллинг каждый кадр, как у дуги: откат меняется непрерывно. Ячейки — инстансы ability_cell.tscn в hud.tscn.
class_name UI_HudAbilitySlots
extends Control

const IDLE_ALPHA := 0.55
## Сколько держать в полную силу после изменения (вселение, выход, поглощение, применение).
const BRIGHT_FOR := 2.5
const APPEAR_TAU := 0.12
const FADE_TAU := 0.4

@onready var _slots: Array[UI_AbilityCell] = [%Slot1, %Slot2, %Slot3, %Slot4]
@onready var _bank_cells: Container = %BankCells
@onready var _bank_caption: Label = %BankCaption

## Прозрачность, к которой узел идёт сейчас (для проверок).
var target_alpha := 0.0
var _bright_until := -INF
var _signature := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


func _process(delta: float) -> void:
	var player := E_Player.find()
	var loadout := player.get_component(C_AbilityLoadout) as C_AbilityLoadout if player else null
	if loadout == null:
		target_alpha = 0.0
	else:
		var signature := render(player, loadout)
		if signature != _signature:
			_signature = signature
			_bright_until = UI_HudMood.now() + BRIGHT_FOR
		target_alpha = 1.0 if UI_HudMood.now() < _bright_until else IDLE_ALPHA
	var tau := APPEAR_TAU if target_alpha > modulate.a else FADE_TAU
	modulate.a = UI_HudMood.approach(modulate.a, target_alpha, tau, delta)


## Раскладывает состояние по ячейкам и возвращает его подпись: смена подписи — «заметное изменение».
func render(player: Entity, loadout: C_AbilityLoadout) -> String:
	var parts := PackedStringArray()
	for i in _slots.size():
		var view := loadout.view(player, i + 1)
		var shown := view.shown()
		var state := UI_AbilityCell.State.EMPTY
		if view.locked:
			state = UI_AbilityCell.State.LOCKED
		elif shown:
			state = UI_AbilityCell.State.BODY if shown == view.body else UI_AbilityCell.State.SOUL
		_slots[i].show_ability(state, shown, i + 1, view.sleeping() and not view.locked)
		parts.append("%d:%s:%s:%s" % [state, _id(shown), view.sleeping(), _on_cooldown(shown)])

	var open := C_AbilityLoadout.bank_size(player)
	_bank_caption.text = tr("HUD_BANK") % [loadout.bank.size(), open]
	var cells := _bank_cells.get_children()
	for i in cells.size():
		var cell := cells[i] as UI_AbilityCell
		if i < loadout.bank.size():
			cell.show_ability(UI_AbilityCell.State.SOUL, loadout.bank[i])
		elif i < open:
			cell.show_ability(UI_AbilityCell.State.EMPTY, null)
		else:
			cell.show_ability(UI_AbilityCell.State.LOCKED, null)
	for held in loadout.bank:
		parts.append(_id(held))
	parts.append(str(open))
	return "|".join(parts)


static func _id(ability: C_Ability) -> String:
	return str(ability.get_instance_id()) if ability else "-"


static func _on_cooldown(ability: C_Ability) -> bool:
	return ability != null and ability.cooldown_left > 0.0
