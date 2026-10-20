## res://src/ui/skill_tree/skill_tree_ui.gd
## Экран навыков «Отголосок» (§9 «Меню — спека»): нейросеть слева (UI_SkillGraph), карточка справа (UI_SkillCard), кошелёк сверху, вкладки «Душа» и «Архитектор». Экран держит то, что им знать незачем: какое дерево на
## вкладке, сколько валюты, кто тратит. Обе вкладки с любой точки входа (решение 02.10); вкладка Архитектора — после первой встречи с ним.
class_name SkillTreeUI
extends UI_MenuScreen

## Как долго держится строка «Ранг N открыт» (§7).
const TOAST_TIME := 1.4
const UNLOCK_EVENT := "event:/ui/skill_unlock"

@onready var _graph: UI_SkillGraph = %Graph
@onready var _card: UI_SkillCard = %Card
@onready var _wallet_label: Label = %WalletLabel
@onready var _wallet_value: Label = %WalletValue
@onready var _toast: Label = %Toast
@onready var _tab_soul: BaseButton = %TabSoul
@onready var _tab_architect: BaseButton = %TabArchitect

## Вкладки: [{ manager, tree, wallet_key, no_money_key, thousands, sign }].
var _tabs: Array[Dictionary] = []
var _tab := -1
var _toast_tween: Tween


## Открыть экран на дереве tree_data с прокачкой skill_manager; вторая вкладка — другое дерево игры; подставной менеджер (проверки) получает одну.
func setup(skill_manager, tree_data: RS_SkillTree) -> void:
	_tabs.clear()
	var architect: bool = skill_manager == ArchitectManager
	var soul_tab := _soul_tab(SkillManager if architect else skill_manager,
			SkillManager.SKILL_TREE if architect else tree_data)
	var architect_tab := _architect_tab(ArchitectManager, ArchitectManager.SKILL_TREE if not architect else tree_data)
	_tabs.append(soul_tab)
	var stub: bool = skill_manager != SkillManager and not architect
	if not stub and (architect or ArchitectManager.is_met()):
		_tabs.append(architect_tab)
	_tab_soul.visible = _tabs.size() > 1
	_tab_architect.visible = _tabs.size() > 1
	_tab_soul.pressed.connect(_switch_tab.bind(0))
	_tab_architect.pressed.connect(_switch_tab.bind(1))
	_graph.skill_selected.connect(_on_skill_selected)
	_card.unlock_requested.connect(_on_unlock_requested)
	_switch_tab(1 if architect and _tabs.size() > 1 else 0)


func _soul_tab(manager, tree: RS_SkillTree) -> Dictionary:
	return {"manager": manager, "tree": tree, "wallet_key": "SKILL_POINTS",
			"no_money_key": "SKILL_NO_POINTS", "thousands": false, "sign": false}


## Эссенция считается тысячами (§10, SKILL_THOUSANDS); дерево Архитектора растёт на знаке комплекса.
func _architect_tab(manager, tree: RS_SkillTree) -> Dictionary:
	return {"manager": manager, "tree": tree, "wallet_key": "ARCHITECT_ESSENCE",
			"no_money_key": "SKILL_NO_ESSENCE", "thousands": true, "sign": true}


func _switch_tab(index: int) -> void:
	if index == _tab or index >= _tabs.size():
		return
	_disconnect_manager()
	# Отклик прошлой покупки — про другое дерево.
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_tab = index
	var tab := _tabs[index]
	(_tab_soul if index == 0 else _tab_architect).button_pressed = true
	tab.manager.skill_unlocked.connect(_on_skill_unlocked)
	_wallet_label.text = tr(tab.wallet_key)
	_graph.setup(tab.manager, tab.tree, tab.sign)
	_refresh_wallet()
	var first := _graph.default_selection()
	if first != &"":
		_graph.select(first)
		first_focus = _graph.neuron(first)


func _disconnect_manager() -> void:
	if _tab < 0:
		return
	var manager = _tabs[_tab].manager
	if manager.skill_unlocked.is_connected(_on_skill_unlocked):
		manager.skill_unlocked.disconnect(_on_skill_unlocked)


func _on_skill_selected(id: StringName) -> void:
	_show_card(id)


func _show_card(id: StringName) -> void:
	var tab := _tabs[_tab]
	var def: RS_SkillDefinition = tab.tree.get_definition(id)
	if def == null:
		return
	var currency := UI_SkillCard.Currency.new()
	currency.cost_text = _amount_text
	currency.no_money_key = tab.no_money_key
	_card.show_skill(def, tab.tree, tab.manager, currency)


func _on_unlock_requested(id: StringName) -> void:
	_tabs[_tab].manager.unlock(id)


## Разблокировка меняет валюту, доступность соседей и видимое (мог открыться целая ветка): сеть обновляется полностью, отклик — на открытом нейроне.
func _on_skill_unlocked(id: StringName, new_rank: int) -> void:
	_graph.refresh()
	_graph.play_unlock_effect(id)
	_refresh_wallet()
	_flash(_wallet_value)
	_show_card(id)
	_card.flash()
	_show_toast(tr("SKILL_UNLOCKED") % new_rank)
	AudioManager.play_event_ui(UNLOCK_EVENT)


func _refresh_wallet() -> void:
	_wallet_value.text = _amount_text(_tabs[_tab].manager.save.skill_points)


## Число валюты для кошелька и цены; эссенция с тысячи — «12,4 тыс.» (запятая по языку — часть числа).
func _amount_text(amount: int) -> String:
	if not _tabs[_tab].thousands or amount < 1000:
		return str(amount)
	var value := "%.1f" % (amount / 1000.0)
	if TranslationServer.get_locale().begins_with("ru"):
		value = value.replace(".", ",")
	return tr("SKILL_THOUSANDS") % value


func _flash(label: Label) -> void:
	var tween := create_tween()
	label.add_theme_color_override(&"font_color", UI_HudMood.OVER)
	tween.tween_method(func(c: Color) -> void: label.add_theme_color_override(&"font_color", c),
			UI_HudMood.OVER, UI_MenuStyle.TEXT, 1.2).set_ease(Tween.EASE_OUT)


func _show_toast(line: String) -> void:
	if _toast_tween:
		_toast_tween.kill()
	_toast.text = line
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, TOAST_TIME * 0.2)
	_toast_tween.tween_interval(TOAST_TIME * 0.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, TOAST_TIME * 0.2)


func _on_close_pressed() -> void:
	UIManager.close_top()


func _exit_tree() -> void:
	_disconnect_manager()
