# res://src/ui/hud/hud_prompt.gd
## Подсказка взаимодействия: пока крестик наведён на интерактивный объект,
## S_InteractionDetector держит на нём C_Highlighted — показываем его prompt_text
## с префиксом клавиши (напр. "[F] Древо навыков").
##
## Клавиша НЕ пишется в подсказку руками: она резолвится из InputMap по
## C_Interactable.action_name, поэтому верна для любого действия (у тела для
## захвата это будет «ЛКМ», а не «F») и сама обновляется после переназначения —
## подписаны на SettingsManager.settings_changed.
##
## Реагируем на добавление/снятие C_Highlighted через сигналы мира — тем же
## паттерном, что и crosshair.gd. C_Highlighted навешивается ТОЛЬКО на интерактивы
## (тела для захвата — на слое enemies, без C_Interactable, сюда не попадают).
##
## Скрипт — на ПОДЛОЖКЕ (PanelContainer), а не на самом Label: подложка нужна
## ровно тогда, когда есть что на ней показать, иначе на экране висела бы пустая
## плашка. show()/hide() self прячут подложку целиком вместе с текстом — тот же
## приём, что у hud_message.gd и hud_abilities.gd.
class_name UI_HudPrompt
extends PanelContainer

@onready var _label: Label = $Margin/Prompt

## Интерактив, на который сейчас смотрим (null — подсказка скрыта). Держим ссылку,
## чтобы пересобрать текст при смене раскладки, не дожидаясь нового наведения.
var _shown: C_Interactable = null


func _ready() -> void:
	hide()
	if ECS.world:
		_connect_world_signals(ECS.world)
	ECS.world_changed.connect(_on_world_changed)
	SettingsManager.settings_changed.connect(_on_settings_changed)


func _on_world_changed(world: World) -> void:
	_shown = null
	hide()
	if world:
		_connect_world_signals(world)


func _connect_world_signals(world: World) -> void:
	if not world.component_added.is_connected(_on_component_added):
		world.component_added.connect(_on_component_added)
	if not world.component_removed.is_connected(_on_component_removed):
		world.component_removed.connect(_on_component_removed)


## Текст вместо подсказки, когда механизм требует тела, а БФЖ развоплощён.
const NEEDS_BODY := "Нужно тело"


func _on_component_added(entity: Entity, component: Variant) -> void:
	# Вселение/развоплощение меняет доступность механизмов — если подсказка на
	# экране, она обязана переписаться, а не ждать нового наведения.
	if component is C_Embodied:
		if _shown != null:
			_render()
		return
	if not (component is C_Highlighted):
		return
	var inter := entity.get_component(C_Interactable) as C_Interactable
	if inter == null or inter.prompt_text == "":
		return  # интерактив без подписи — крестик подсветит, но текста нет
	_shown = inter
	_render()


func _on_component_removed(_entity: Entity, component: Variant) -> void:
	if component is C_Embodied:
		if _shown != null:
			_render()
		return
	if component is C_Highlighted:
		_shown = null
		hide()


## Раскладку переназначили — если подсказка на экране, она обязана показать новую
## клавишу немедленно, а не после того как игрок отведёт и наведёт крестик снова.
func _on_settings_changed(_settings: RS_Settings) -> void:
	if _shown != null:
		_render()


func _render() -> void:
	# Механизм, до которого бестелесному не дотянуться: объясняем ПРИЧИНУ и не
	# предлагаем клавишу — нажатие всё равно не пройдёт (см. S_InteractInput).
	if _shown.requires_body and not _player_embodied():
		_label.text = "%s: %s" % [NEEDS_BODY, _shown.prompt_text]
		show()
		return

	var key := SettingsManager.action_display_name(_shown.action_name) if _shown.show_key_hint else ""
	_label.text = "[%s] %s" % [key, _shown.prompt_text] if key != "" else _shown.prompt_text
	show()


func _player_embodied() -> bool:
	if ECS.world == null:
		return false
	var player := ECS.world.query.with_all([C_PlayerInput]).execute_one()
	return player != null and player.has_component(C_Embodied)
