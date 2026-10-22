# res://src/ui/stats_panel/stats_panel.gd
## Показатели по удержанию клавиши ([[HUD — спека]] §7б, макет 14): тело и душа, слоты и банк; перенос из банка в слот — двумя кликами.
## Без паузы, ввод игрока заблокирован (UIManager.push_blocking_screen). Открывает и закрывает UIManager по удержанию действия stats. Вики: [[Захват тела]] §«Способности и слоты».
class_name UI_StatsPanel
extends UI_MenuScreen

const GROUP := &"stats_panel"
const ACTION := &"stats"

@onready var _body_caption: Label = %BodyCaption
@onready var _health_row: Control = %HealthRow
@onready var _health_value: Label = %HealthValue
@onready var _health_bar: Control = %HealthBar
@onready var _health_fill: Control = %Fill
@onready var _reserve_row: Control = %ReserveRow
@onready var _reserve_value: Label = %ReserveValue
@onready var _no_body: Label = %NoBody
@onready var _stability_value: Label = %StabilityValue
@onready var _minds_value: Label = %MindsValue
@onready var _slots: Array[UI_StatsAbilityItem] = []
@onready var _bank: Array[UI_StatsAbilityItem] = []
@onready var _bank_caption: Label = %BankCaption
@onready var _move: UI_ThoughtLine = %Move
@onready var _rules: Label = %Rules
@onready var _refusal: Label = %Refusal
@onready var _release_key: Label = %Key

var _soul: Entity
var _loadout: C_AbilityLoadout
## Ячейка банка, ждущая слота; -1 — ничего не выбрано.
var picked := -1
var _body_path := ""
var _body_name := &""
var _refusal_at := -INF


static func is_open(tree: SceneTree) -> bool:
	return tree.get_first_node_in_group(GROUP) != null


func _ready() -> void:
	super()
	add_to_group(GROUP)
	for item in %Slots.get_children():
		_slots.append(item as UI_StatsAbilityItem)
	for item in %BankCells.get_children():
		_bank.append(item as UI_StatsAbilityItem)
	for i in _slots.size():
		_slots[i].chosen.connect(pick_slot.bind(i + 1))
	for i in _bank.size():
		_bank[i].chosen.connect(pick_bank.bind(i))
	_move.set_line(tr("KEY_MOUSE_LEFT"), tr("HUD_STATS_MOVE"))
	_rules.text = tr("HUD_STATS_RULES") % roundi(GameConfig.config.ability_graft_time)
	_release_key.text = "[%s]" % SettingsManager.action_display_name(ACTION)
	if ECS.world:
		ECS.world.component_added.connect(_on_component_added)


func setup(soul: Entity, loadout: C_AbilityLoadout) -> void:
	_soul = soul
	_loadout = loadout
	render()


func _process(_delta: float) -> void:
	if is_instance_valid(_soul):
		render()
	_show_refusal()


## Уход со стека: HUD-слоты перестают гореть сразу, а не после угасания экрана.
func play_exit() -> void:
	remove_from_group(GROUP)
	if ECS.world and ECS.world.component_added.is_connected(_on_component_added):
		ECS.world.component_added.disconnect(_on_component_added)
	super()


## ЛКМ по ячейке банка: выбрать её под слот; при одном открытом слоте выбирать нечего — сразу в него.
func pick_bank(index: int) -> void:
	if _loadout == null or index >= _loadout.bank.size():
		return
	if C_AbilityLoadout.open_slots(_soul) <= 1:
		place(index, 1)
		return
	picked = -1 if picked == index else index


func pick_slot(number: int) -> void:
	if picked < 0:
		return
	place(picked, number)


func place(bank_index: int, number: int) -> C_AbilityLoadout.Transfer:
	picked = -1
	var result := _loadout.bank_to_slot(_soul, bank_index, number)
	match result:
		C_AbilityLoadout.Transfer.LOCKED:
			C_ScreenMessage.show_on(_soul, "HUD_MSG_SLOT_LOCKED")
		C_AbilityLoadout.Transfer.IN_COMBAT:
			C_ScreenMessage.show_on(_soul, "HUD_MSG_TRANSFER_COMBAT")
	render()
	return result


func render() -> void:
	_render_body()
	var life := _soul.get_component(C_Lifespan) as C_Lifespan
	var left := ceili(life.current) if life else 0
	_stability_value.text = "%d:%02d" % [floori(left / 60.0), left % 60]
	var stats := RunStats.current
	_minds_value.text = str(roundi(stats.value(RS_RunStats.BODIES)) if stats else 0)
	_render_slots()
	_render_bank()


func _render_body() -> void:
	var embodied := _soul.get_component(C_Embodied) as C_Embodied
	var health := _soul.get_component(C_Health) as C_Health
	var decay := _soul.get_component(C_BodyDecay) as C_BodyDecay
	var path := embodied.body_scene_path if embodied else ""
	if path != _body_path:
		# Имя вида — из сцены тела: инстанс сцены дорог, поэтому раз на смену тела.
		_body_path = path
		_body_name = E_Body.name_key_of_scene(path)
	_body_caption.text = tr("HUD_STATS_BODY") % tr(_body_name) if _body_name != &"" else tr("HUD_STATS_BODY_NONE")
	_no_body.visible = embodied == null
	_health_row.visible = health != null
	_health_bar.visible = health != null
	_reserve_row.visible = decay != null
	if health:
		var maximum := health.effective_maximum(_soul)
		_health_value.text = "%d / %d" % [ceili(health.current), roundi(maximum)]
		_health_fill.anchor_right = clampf(health.current / maxf(maximum, 0.001), 0.0, 1.0)
	if decay:
		_reserve_value.text = tr("HUD_STATS_SECONDS") % ceili(decay.remaining)


func _render_slots() -> void:
	for i in _slots.size():
		var view := _loadout.view(_soul, i + 1)
		var item := _slots[i]
		var shown := view.shown()
		if view.locked:
			item.show_item(UI_AbilityCell.State.LOCKED, null, tr("HUD_STATS_LOCKED"),
				tr("HUD_STATS_SLOT_BRANCH") % (i + 1), i + 1, false, true)
		elif shown == null:
			item.show_item(UI_AbilityCell.State.EMPTY, null, tr("HUD_STATS_EMPTY"), "", i + 1, false, true)
		elif shown == view.body:
			item.show_item(UI_AbilityCell.State.BODY, shown, tr(shown.name_key), tr("HUD_STATS_FROM_BODY"),
				i + 1, view.sleeping())
		else:
			item.show_item(UI_AbilityCell.State.SOUL, shown, tr(shown.name_key), origin_line(shown), i + 1)


func _render_bank() -> void:
	var open := C_AbilityLoadout.bank_size(_soul)
	_bank_caption.text = tr("HUD_BANK") % [_loadout.bank.size(), open]
	if picked >= _loadout.bank.size():
		picked = -1
	for i in _bank.size():
		var item := _bank[i]
		if i < _loadout.bank.size():
			var held := _loadout.bank[i]
			var sub := tr("HUD_STATS_PICKED") if i == picked else tr("HUD_BANK_SLOT") % held.slot
			item.show_item(UI_AbilityCell.State.SOUL, held, tr(held.name_key), sub)
		elif i < open:
			item.show_item(UI_AbilityCell.State.EMPTY, null, tr("HUD_STATS_EMPTY"), "", 0, false, true)
		else:
			item.show_item(UI_AbilityCell.State.LOCKED, null, "", tr("HUD_STATS_BANK_LOCKED"))
		item.set_selected(i == picked)


## Происхождение поглощённой: тело-источник в именительном, как на экране полного банка; пока прирастает — остаток.
static func origin_line(ability: C_Ability) -> String:
	if ability.graft_left > 0.0:
		return TranslationServer.translate("HUD_STATS_GRAFTING") % ceili(ability.graft_left)
	if ability.source_key == &"":
		return TranslationServer.translate("HUD_STATS_ABSORBED")
	return TranslationServer.translate("HUD_STATS_ABSORBED_FROM") % TranslationServer.translate(ability.source_key)


## Мысль HUD лежит под затемнением экрана — отказ повторяется строкой здесь, тем же временем показа.
func _on_component_added(entity: Entity, component: Variant) -> void:
	if entity == _soul and component is C_ScreenMessage:
		_refusal.text = tr((component as C_ScreenMessage).text)
		_refusal_at = UI_HudMood.now()


func _show_refusal() -> void:
	var age := UI_HudMood.now() - _refusal_at
	_refusal.visible = age < UI_HudMessage.TOTAL
	if _refusal.visible:
		var fade_from := UI_HudMessage.TOTAL - UI_HudMessage.FADE
		_refusal.modulate.a = 1.0 - clampf((age - fade_from) / UI_HudMessage.FADE, 0.0, 1.0)
