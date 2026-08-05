# res://src/ui/hud/hud_prompt.gd
## Подсказка взаимодействия: пока крестик наведён на интерактивный объект,
## S_InteractionDetector держит на нём C_Highlighted — показываем его prompt_text
## с префиксом клавиши взаимодействия (напр. "[F] Древо навыков").
##
## Реагируем на добавление/снятие C_Highlighted через сигналы мира — тем же
## паттерном, что и crosshair.gd. C_Highlighted навешивается ТОЛЬКО на интерактивы
## (тела для захвата — на слое enemies, без C_Interactable, сюда не попадают).
class_name UI_HudPrompt
extends Label


func _ready() -> void:
	hide()
	if ECS.world:
		_connect_world_signals(ECS.world)
	ECS.world_changed.connect(_on_world_changed)


func _on_world_changed(world: World) -> void:
	hide()
	if world:
		_connect_world_signals(world)


func _connect_world_signals(world: World) -> void:
	if not world.component_added.is_connected(_on_component_added):
		world.component_added.connect(_on_component_added)
	if not world.component_removed.is_connected(_on_component_removed):
		world.component_removed.connect(_on_component_removed)


func _on_component_added(entity: Entity, component: Variant) -> void:
	if not (component is C_Highlighted):
		return
	var inter := entity.get_component(C_Interactable) as C_Interactable
	if inter == null or inter.prompt_text == "":
		return  # интерактив без подписи — крестик подсветит, но текста нет
	var key := _interact_key_hint() if inter.show_key_hint else ""
	text = "[%s] %s" % [key, inter.prompt_text] if key != "" else inter.prompt_text
	show()


func _on_component_removed(_entity: Entity, component: Variant) -> void:
	if component is C_Highlighted:
		hide()


## Строковое имя клавиши действия "interact" из InputMap — чтобы подсказка
## оставалась верной при переназначении. "" если действие без клавиатурного события.
func _interact_key_hint() -> String:
	for ev in InputMap.action_get_events(&"interact"):
		if ev is InputEventKey:
			var kc: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			return OS.get_keycode_string(kc)
	return ""
