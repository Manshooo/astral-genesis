# res://src/ui/skill_tree/skill_card.gd
## Карточка выбранного навыка справа от сети (§9 «Меню — спека»): ветвь, имя с эхом, ранги точками, описание, цена, требования и кнопка. Кнопка открывает ранг или словами говорит, почему нельзя (§1); покупку не делает —
## отдаёт сигнал экрану. О менеджерах не знает: состояние и название валюты приносит экран в show_skill().
class_name UI_SkillCard
extends VBoxContainer

signal unlock_requested(id: StringName)

## Как называть валюту дерева — экран заполняет под вкладку.
class Currency:
	var cost_text: Callable  ## int -> String
	var no_money_key := "SKILL_NO_POINTS"

const REQUIREMENT_ROW_SCENE := preload("res://src/ui/skill_tree/requirement_row.tscn")
const RANK_VALUE_SCENE := preload("res://src/ui/skill_tree/rank_value.tscn")

@onready var _branch: Label = %Branch
@onready var _title: Label = %CardTitle
@onready var _pips: Control = %Pips
@onready var _rank: Label = %Rank
@onready var _desc: Label = %Desc
@onready var _cost_row: Control = %CostRow
@onready var _cost: Label = %Cost
@onready var _reqs: VBoxContainer = %Reqs
@onready var _ability_note: Label = %AbilityNote
@onready var _values_block: Control = %ValuesBlock
@onready var _values_row: HBoxContainer = %ValuesRow
@onready var _bonus: Label = %Bonus
@onready var _cond_block: Control = %CondBlock
@onready var _conds: VBoxContainer = %Conds
@onready var _button: UI_EchoButton = %Unlock

var _id: StringName = &""
var _rank_value := 0
var _max_rank := 1


func _ready() -> void:
	_pips.draw.connect(_draw_pips)
	_button.pressed.connect(func() -> void: unlock_requested.emit(_id))


## [param manager] — SkillProgression дерева; [param previewed] — навык показан на шаг вперёд.
func show_skill(def: RS_SkillDefinition, tree: RS_SkillTree, manager, currency: Currency) -> void:
	_id = def.id
	_rank_value = manager.get_rank(def.id)
	_max_rank = maxi(def.max_rank, 1)
	_branch.text = tr(tree.branch_display_name(def.branch))
	_title.text = tr(def.display_name)
	_rank.text = tr("SKILL_RANK") % [_rank_value, def.max_rank]
	_desc.text = tr(def.description)
	_pips.custom_minimum_size = Vector2(_max_rank * 13.0, 10.0)
	_pips.queue_redraw()

	var maxed := _rank_value >= def.max_rank
	_cost_row.visible = not maxed
	if not maxed:
		_cost.text = currency.cost_text.call(def.cost_for_next_rank(_rank_value))

	_fill_requirements(def, tree, manager)
	_fill_values(def, manager)
	_fill_conditions(def, manager)
	_fill_ability(def)

	var met: bool = manager.requirements_met(def.id)
	if maxed:
		_set_button("SKILL_MAXED", false)
	elif not met:
		_set_button("SKILL_LOCKED", false)
	elif not manager.can_unlock(def.id):
		_set_button(currency.no_money_key, false)
	else:
		_set_button(tr("SKILL_UNLOCK") % (_rank_value + 1), true)


func _set_button(label: String, enabled: bool) -> void:
	_button.text = label
	_button.disabled = not enabled


## Требования строками с отметкой; имена навыков вклеены в строку, поэтому переводятся здесь (tr).
func _fill_requirements(def: RS_SkillDefinition, tree: RS_SkillTree, manager) -> void:
	for child in _reqs.get_children():
		child.queue_free()
	var any := false
	for req in def.requires:
		if req == null:
			continue
		match req.type:
			RS_SkillRequirement.Type.SKILL_RANK:
				var target := tree.get_definition(req.target_skill)
				var target_name := tr(target.display_name) if target != null else String(req.target_skill)
				_add_requirement(tr("SKILL_REQ_RANK") % [target_name, req.min_value],
						manager.get_rank(req.target_skill) >= req.min_value)
			RS_SkillRequirement.Type.BRANCH_TOTAL_RANKS:
				var total := 0
				for other in tree.get_branch_skills(req.target_branch):
					total += manager.get_rank(other.id)
				_add_requirement(tr("SKILL_REQ_BRANCH")
						% [tr(tree.branch_display_name(req.target_branch)), req.min_value],
						total >= req.min_value)
		any = true
	if not any:
		_add_requirement(tr("SKILL_NO_REQ"), true)


func _add_requirement(text: String, met: bool, parent: Control = null) -> void:
	var row: UI_RequirementRow = REQUIREMENT_ROW_SCENE.instantiate()
	(parent if parent != null else _reqs).add_child(row)
	row.setup(text, met)


## Значения навыка по рангам: текущий выделен. Показывается первый модификатор (числа двух статов в строке читались бы рядом).
func _fill_values(def: RS_SkillDefinition, manager) -> void:
	_clear(_values_row)
	var modifier := _primary_modifier(def)
	_values_block.visible = modifier != null
	if modifier == null:
		return
	for rank in range(1, def.max_rank + 1):
		var cell: Label = RANK_VALUE_SCENE.instantiate()
		_values_row.add_child(cell)
		cell.text = modifier.format_value(modifier.value_at(rank))
		if rank == _rank_value:
			cell.add_theme_color_override(&"font_color", UI_HudMood.SOUL)
		else:
			cell.modulate.a = 0.5

	# Бонус условия — строкой под значениями.
	_bonus.visible = def.condition_bonus > 0.0
	if not _bonus.visible:
		return
	var current_rank := maxi(_rank_value, 1)
	if _rank_value > 0 and manager.is_condition_met(def.id, _rank_value):
		var boosted := modifier.value_at(_rank_value) * (1.0 + def.condition_bonus)
		_bonus.text = tr("SKILL_BONUS_ACTIVE") % modifier.format_value(boosted)
	else:
		_bonus.text = tr("SKILL_BONUS_PENDING") % ("%d%%" % roundi(def.condition_bonus * 100.0))
	# Подпись не обещает бонус рангу без условия.
	_bonus.visible = def.condition_for_rank(current_rank) != null


## Условия текущего и следующего рангов с прогрессом (условие следующего показано заранее — что делать, чтобы бонус заработал).
func _fill_conditions(def: RS_SkillDefinition, manager) -> void:
	_clear(_conds)
	var shown := 0
	for rank in [_rank_value, _rank_value + 1]:
		var condition := def.condition_for_rank(rank)
		if condition == null or rank > def.max_rank:
			continue
		var progress: float = manager.get_condition_progress(def.id, rank)
		_add_requirement(
			tr("SKILL_COND_ROW") % [rank, condition.describe(), condition.progress_text(progress)],
			condition.is_met(progress), _conds
		)
		shown += 1
	_cond_block.visible = shown > 0


## Навык способности честно говорит, что без способности он молчит; вне мира игрока нет — остаётся общее пояснение.
func _fill_ability(def: RS_SkillDefinition) -> void:
	var component := def.ability_component()
	_ability_note.visible = component != null
	if component == null:
		return
	var text := tr("SKILL_ABILITY_NOTE")
	var player := E_Player.find()
	if player != null and not player.has_component(component):
		text += "\n" + tr("SKILL_ABILITY_OFF")
	_ability_note.text = text


func _primary_modifier(def: RS_SkillDefinition) -> RS_StatModifier:
	for modifier in def.modifiers:
		if modifier != null:
			return modifier
	return null


func _clear(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


## Ранги точками Ø7: открытые — сиреневые, остальные — пунктирные.
func _draw_pips() -> void:
	for k in _max_rank:
		var c := Vector2(3.5 + k * 13.0, 5.0)
		if k < _rank_value:
			_pips.draw_circle(c, 3.5, UI_HudMood.SOUL)
		else:
			var a := 0.0
			while a < TAU:
				_pips.draw_arc(c, 3.0, a, a + 0.5, 3, Color(UI_MenuStyle.TEXT, 0.4), 1.0, true)
				a += 1.0


## Вспышка имени после открытия ранга (§7).
func flash() -> void:
	var tween := create_tween()
	_title.add_theme_color_override(&"font_color", UI_HudMood.OVER)
	tween.tween_interval(0.2)
	tween.tween_callback(_title.remove_theme_color_override.bind(&"font_color"))
