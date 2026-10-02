# res://src/ui/skill_tree/skill_card.gd
## Карточка выбранного навыка справа от сети (§9 «Меню — спека»): ветвь, имя с
## эхом, ранги точками, описание, цена, требования и кнопка. Подробности ушли из
## узлов сюда, когда дерево стало нейросетью: нейрон — точка с именем, и
## описанию в нём негде жить.
##
## Кнопка либо открывает ранг, либо словами говорит, почему нельзя (§1
## «недоступное объясняет себя»): нет очков, требования, всё освоено. Покупку
## карточка не делает сама — отдаёт сигнал экрану, у которого менеджер.
##
## Карточка ничего не знает о SkillManager и ArchitectManager по имени: всё
## состояние ей приносит экран в show_skill(), включая то, как называется валюта
## этого дерева.
class_name UI_SkillCard
extends VBoxContainer

signal unlock_requested(id: StringName)

## Как называть валюту дерева в карточке — экран заполняет под вкладку.
class Currency:
	var cost_text: Callable  ## int -> String
	var no_money_key := "SKILL_NO_POINTS"

@onready var _branch: Label = %Branch
@onready var _title: Label = %CardTitle
@onready var _pips: Control = %Pips
@onready var _rank: Label = %Rank
@onready var _desc: Label = %Desc
@onready var _cost_row: Control = %CostRow
@onready var _cost: Label = %Cost
@onready var _reqs: VBoxContainer = %Reqs
@onready var _button: UI_EchoButton = %Unlock

var _id: StringName = &""
var _rank_value := 0
var _max_rank := 1


func _ready() -> void:
	_pips.draw.connect(_draw_pips)
	_button.pressed.connect(func() -> void: unlock_requested.emit(_id))


## [param manager] — SkillProgression дерева; [param previewed] — навык показан
## на шаг вперёд и требования ещё не выполнены.
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


## Требования строками с отметкой: выполненное — сиреневый кружок, нет —
## пунктирный. Слова — из перевода; имена навыков и веток вклеиваются в строку,
## поэтому переводятся здесь (tr), автоперевод подписи до них не достал бы.
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


func _add_requirement(text: String, met: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(12, 12)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.draw.connect(_draw_requirement_mark.bind(mark, met))
	row.add_child(mark)
	var label := Label.new()
	label.theme_type_variation = &"MenuReq"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not met:
		label.modulate.a = 0.5
	row.add_child(label)
	_reqs.add_child(row)


func _draw_requirement_mark(mark: Control, met: bool) -> void:
	var c := Vector2(6, 6)
	if met:
		mark.draw_circle(c, 4.0, UI_HudMood.SOUL)
	else:
		var a := 0.0
		while a < TAU:
			mark.draw_arc(c, 4.0, a, a + 0.25, 3, Color(UI_MenuStyle.TEXT, 0.5), 1.0, true)
			a += 0.75


## Ранги точками Ø7: открытые — сиреневые, остальные — пунктирные кружки.
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
