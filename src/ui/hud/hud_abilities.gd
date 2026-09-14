# res://src/ui/hud/hud_abilities.gd
## Раскладка управления «на сейчас»: что риг умеет ПРЯМО СЕЙЧАС, а не полный
## список действий игры. Ход/полёт показываем всегда (движение доступно в любом
## состоянии, меняется только его смысл), прыжок — только пока на риге есть
## C_Jump: у безногого тела строка исчезает, а не гаснет серым.
##
## Клавиша прыжка резолвится из InputMap по C_Jump.action_name тем же приёмом,
## что и подсказка взаимодействия (hud_prompt.gd) — после переназначения строка
## обновится сама, без правки этого файла.
##
## Реагируем на component_added/component_removed, а не поллим каждый кадр
## (ср. hud_vitals.gd): набор возможностей — дискретное состояние, меняющееся
## на вселении/выходе/пересадке, а не непрерывное число.
##
## Скрипт — на ПОДЛОЖКЕ (PanelContainer), а не на списке строк: та же причина,
## что у hud_prompt.gd и hud_message.gd.
class_name UI_HudAbilities
extends PanelContainer

@onready var _abilities: VBoxContainer = $Margin/Abilities
@onready var _move_label: Label = $Margin/Abilities/MoveLabel
@onready var _jump_label: Label = $Margin/Abilities/JumpLabel

## Строки-способности и разделители между ними — СОБРАНЫ ИЗ ДЕТЕЙ, а не
## перечислены по именам: авторишь третью строку (сцена) — разделители сами
## подхватят её, без правки этого файла. Порядок в обоих массивах — порядок
## детей: _separators[i] лежит МЕЖДУ _rows[i] и _rows[i+1] (сцена авторится
## строго чередованием Label/HSeparator, см. hud.tscn).
var _rows: Array[Control] = []
var _separators: Array[Control] = []


func _ready() -> void:
	for child in _abilities.get_children():
		if child is HSeparator:
			_separators.append(child)
		else:
			_rows.append(child)

	if ECS.world:
		_connect_world_signals(ECS.world)
	ECS.world_changed.connect(_on_world_changed)
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_render()


func _on_world_changed(world: World) -> void:
	if world:
		_connect_world_signals(world)
	_render()


func _connect_world_signals(world: World) -> void:
	if not world.component_added.is_connected(_on_component_changed):
		world.component_added.connect(_on_component_changed)
	if not world.component_removed.is_connected(_on_component_changed):
		world.component_removed.connect(_on_component_changed)


## Один обработчик на оба события: нас интересует не факт «добавили/сняли», а
## что после него сменился набор возможностей рига — перерисовать дешевле, чем
## различать направление.
func _on_component_changed(_entity: Entity, component: Variant) -> void:
	if component is C_Walk or component is C_Flight or component is C_Jump or component is C_Embodied:
		_render()


## Переназначили клавишу — прыжок обязан показать новую немедленно, а не после
## следующей пересадки.
func _on_settings_changed(_settings: RS_Settings) -> void:
	_render()


func _render() -> void:
	var player := _get_player()
	if player == null:
		hide()
		return
	show()

	_move_label.visible = true
	_move_label.text = "Полёт" if player.has_component(C_Flight) else "Ходьба"

	var jump := player.get_component(C_Jump) as C_Jump
	_jump_label.visible = jump != null
	if jump != null:
		var key := SettingsManager.action_display_name(jump.action_name)
		_jump_label.text = "[%s] Прыжок" % key if key != "" else "Прыжок"

	_sync_separators()

	# Подложка — под столько строк, сколько видно СЕЙЧАС, а не под их
	# наибольшее возможное число: сброс размера заставляет Godot заново
	# посчитать его от текущего минимума VBoxContainer (Control никогда не
	# опускает size ниже get_combined_minimum_size, но и сам никогда не
	# УМЕНЬШАЕТ его обратно — сброс в ZERO и есть тот самый пересчёт).
	size = Vector2.ZERO


## Разделитель — не украшение само по себе, а знак «до этой точки была видимая
## строка, и после неё тоже будет». Прячем ВСЕ разделители и зажигаем ровно по
## одному на каждый переход между двумя видимыми строками — даже если между
## ними есть скрытые: две видимые строки через одну скрытую всё равно должны
## разделяться ровно одной чертой, а не двумя (или ни одной).
func _sync_separators() -> void:
	for separator in _separators:
		separator.visible = false

	var last_visible := -1
	for i in _rows.size():
		if not _rows[i].visible:
			continue
		if last_visible >= 0:
			_separators[last_visible].visible = true
		last_visible = i


func _get_player() -> Entity:
	if ECS.world == null:
		return null
	return ECS.world.query.with_all([C_PlayerInput]).execute_one()
