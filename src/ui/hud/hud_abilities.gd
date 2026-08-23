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
## что у hud_prompt.gd и hud_message.gd. Разделитель между строками — туда же:
## он разделяет ДВЕ ВИДИМЫЕ строки, и виден ровно тогда, когда видна строка
## прыжка, иначе торчал бы сиротой под одиноким «Ход».
class_name UI_HudAbilities
extends PanelContainer

@onready var _move_label: Label = $Abilities/MoveLabel
@onready var _separator: HSeparator = $Abilities/HSeparator
@onready var _jump_label: Label = $Abilities/JumpLabel


func _ready() -> void:
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

	_move_label.text = "Полёт" if player.has_component(C_Flight) else "Ход"

	var jump := player.get_component(C_Jump) as C_Jump
	# Разделитель — не украшение сам по себе, а знак «строк больше одной»:
	# прячем его вместе со строкой прыжка, а не оставляем висеть над пустотой.
	_separator.visible = jump != null
	_jump_label.visible = jump != null
	if jump == null:
		return
	var key := SettingsManager.action_display_name(jump.action_name)
	_jump_label.text = "[%s] Прыжок" % key if key != "" else "Прыжок"


func _get_player() -> Entity:
	if ECS.world == null:
		return null
	return ECS.world.query.with_all([C_PlayerInput]).execute_one()
